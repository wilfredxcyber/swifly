import Foundation
import Network
import NIO
import NIOHTTP1
import NIOTLS
import NIOTransportServices

class SwiflyServer: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let pairingCode: String
    private let token: String
    private let fileURL: URL
    
    init(pairingCode: String, token: String, fileURL: URL) {
        self.pairingCode = pairingCode
        self.token = token
        self.fileURL = fileURL
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let request):
            handleRequest(context: context, request: request)
        case .body, .end:
            break
        }
    }
    
    private func handleRequest(context: ChannelHandlerContext, request: HTTPRequestHead) {
        var responseHeaders = HTTPHeaders()
        responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
        
        if request.method == .OPTIONS {
            let head = HTTPResponseHead(version: request.version, status: .ok, headers: responseHeaders)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            return
        }
        
        let uri = request.uri
        
        if uri.starts(with: "/ping.js") {
            servePing(context: context, request: request, headers: responseHeaders)
        } else if uri == "/file/\(token)" {
            serveFile(context: context, request: request, headers: responseHeaders)
        } else {
            let head = HTTPResponseHead(version: request.version, status: .notFound, headers: responseHeaders)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
    
    private func servePing(context: ChannelHandlerContext, request: HTTPRequestHead, headers: HTTPHeaders) {
        var responseHeaders = headers
        responseHeaders.add(name: "Content-Type", value: "application/javascript")
        
        let urlComponents = URLComponents(string: request.uri)
        let queryItems = urlComponents?.queryItems
        let reqCode = queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let reqIp = queryItems?.first(where: { $0.name == "ip" })?.value ?? ""
        
        if reqCode.caseInsensitiveCompare(pairingCode) == .orderedSame {
            let filename = fileURL.lastPathComponent
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            let json = """
            {"status":"ok", "token":"\(token)", "filename":"\(filename)", "size":\(size), "ip":"\(reqIp)"}
            """
            let jsResponse = "swiflyCallback(\(json));"
            
            var buffer = context.channel.allocator.buffer(capacity: jsResponse.utf8.count)
            buffer.writeString(jsResponse)
            
            responseHeaders.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            let head = HTTPResponseHead(version: request.version, status: .ok, headers: responseHeaders)
            
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        } else {
            let jsResponse = "/* not found */"
            var buffer = context.channel.allocator.buffer(capacity: jsResponse.utf8.count)
            buffer.writeString(jsResponse)
            
            responseHeaders.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            let head = HTTPResponseHead(version: request.version, status: .notFound, headers: responseHeaders)
            
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
    
    private func serveFile(context: ChannelHandlerContext, request: HTTPRequestHead, headers: HTTPHeaders) {
        var responseHeaders = headers
        responseHeaders.add(name: "Content-Type", value: "application/octet-stream")
        
        let filename = fileURL.lastPathComponent
        responseHeaders.add(name: "Content-Disposition", value: "attachment; filename=\"\(filename)\"")
        
        guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            let head = HTTPResponseHead(version: request.version, status: .internalServerError, headers: responseHeaders)
            context.writeAndFlush(self.wrapOutboundOut(.head(head)), promise: nil)
            return
        }
        
        responseHeaders.add(name: "Content-Length", value: "\(fileSize)")
        let head = HTTPResponseHead(version: request.version, status: .ok, headers: responseHeaders)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        
        // Use SwiftNIO's NonBlockingFileIO to stream the file efficiently
        // For simplicity in this implementation we read the whole file if small, 
        // or just use NSData. In a real production app we'd use FileRegion.
        if let fileData = try? Data(contentsOf: fileURL) {
            var buffer = context.channel.allocator.buffer(capacity: fileData.count)
            buffer.writeBytes(fileData)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}

class SwiflyServerManager: ObservableObject {
    private var group: NIOTSEventLoopGroup?
    private var channel: Channel?
    
    @Published var isRunning = false
    @Published var pairingCode = ""
    
    func startServer(fileURL: URL, pairingCode: String) {
        self.pairingCode = pairingCode
        let token = UUID().uuidString.prefix(8).lowercased()
        let port = 7845
        
        group = NIOTSEventLoopGroup()
        let bootstrap = NIOTSListenerBootstrap(group: group!)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(SwiflyServer(pairingCode: pairingCode, token: String(token), fileURL: fileURL))
                }
            }
        
        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    func stopServer() {
        channel?.close(mode: .all, promise: nil)
        try? group?.syncShutdownGracefully()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { return nil }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) { // IPv4
                    let name = String(cString: interface.ifa_name)
                    // En0 is WiFi, bridge100 is Personal Hotspot on iOS
                    if name == "en0" || name == "bridge100" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        if name == "bridge100" { return address } // Prefer hotspot if both exist
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
