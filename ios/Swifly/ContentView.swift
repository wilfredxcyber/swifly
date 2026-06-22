import SwiftUI
import VisionKit

struct ScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: ScannerView
        
        init(_ parent: ScannerView) {
            self.parent = parent
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .barcode(barcode) = item {
                if let payload = barcode.payloadStringValue {
                    parent.onScan(payload)
                }
            }
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item {
                    if let payload = barcode.payloadStringValue {
                        parent.onScan(payload)
                        break
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Nothing to update
    }
}

struct ContentView: View {
    @StateObject private var serverManager = SwiflyServerManager()
    @State private var showingFilePicker = false
    @State private var showingScanner = false
    @State private var selectedFileURL: URL?
    
    var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255).ignoresSafeArea() // bg-color
            
            VStack {
                Text("Swifly")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(Color(red: 59/255, green: 130/255, blue: 246/255))
                    .padding(.bottom, 8)
                
                Text("Zero-friction PC file transfer")
                    .foregroundColor(.gray)
                    .padding(.bottom, 32)
                
                if !serverManager.isRunning {
                    if selectedFileURL == nil {
                        Button(action: { showingFilePicker = true }) {
                            Text("Pick a File to Send")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(red: 59/255, green: 130/255, blue: 246/255))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Selected File:")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Text(selectedFileURL?.lastPathComponent ?? "")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(red: 30/255, green: 41/255, blue: 59/255))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)
                            
                            Button(action: {
                                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                                    showingScanner = true
                                } else {
                                    print("Scanner not supported on this device/simulator.")
                                }
                            }) {
                                Text("Scan QR Code on PC")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color(red: 59/255, green: 130/255, blue: 246/255))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 24)
                            
                            Button(action: { selectedFileURL = nil }) {
                                Text("Pick a different file")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                } else {
                    VStack {
                        Text("Ready & Serving")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                        
                        Text("Pairing Code: \(serverManager.pairingCode)")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(red: 59/255, green: 130/255, blue: 246/255))
                            .padding(.bottom, 24)
                        
                        Text("Keep this app open until the transfer completes on your PC.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.bottom, 32)
                        
                        Button(action: { serverManager.stopServer() }) {
                            Text("Stop Transfer")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        self.selectedFileURL = url
                    } else {
                        print("Failed to access security scoped resource")
                    }
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingScanner) {
            ScannerView { code in
                showingScanner = false
                if let url = selectedFileURL {
                    serverManager.startServer(fileURL: url, pairingCode: code)
                }
            }
            .ignoresSafeArea()
        }
    }
}
