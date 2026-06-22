package com.swifly

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import java.io.InputStream
import java.net.URLEncoder

class SwiflyServer(
    private val context: Context,
    private val port: Int,
    private val pairingCode: String,
    private val token: String,
    private val fileUri: Uri
) : NanoHTTPD(port) {

    private val TAG = "SwiflyServer"
    private var fileName: String = "unknown_file"
    private var fileSize: Long = 0

    init {
        // Resolve file info
        context.contentResolver.query(fileUri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex != -1) fileName = cursor.getString(nameIndex)
                if (sizeIndex != -1) fileSize = cursor.getLong(sizeIndex)
            }
        }
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        Log.d(TAG, "Request: ${session.method} $uri")

        // CORS headers common builder
        fun cors(r: Response): Response {
            r.addHeader("Access-Control-Allow-Origin", "*")
            r.addHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
            return r
        }

        if (session.method == Method.OPTIONS) {
            val response = newFixedLengthResponse(Response.Status.OK, MIME_PLAINTEXT, "")
            return cors(response)
        }

        return when (uri) {
            "/ping.js" -> {
                // JSONP probe endpoint
                val reqCode = session.parameters["code"]?.firstOrNull() ?: ""
                val reqIp = session.parameters["ip"]?.firstOrNull() ?: ""
                
                if (reqCode.equals(pairingCode, ignoreCase = true)) {
                    val json = JSONObject()
                    json.put("status", "ok")
                    json.put("token", token)
                    json.put("filename", fileName)
                    json.put("size", fileSize)
                    json.put("ip", reqIp)
                    
                    val jsResponse = "swiflyCallback(${json.toString()});"
                    cors(newFixedLengthResponse(Response.Status.OK, "application/javascript", jsResponse))
                } else {
                    // Fail silently for bad probes to keep noise low
                    cors(newFixedLengthResponse(Response.Status.NOT_FOUND, "application/javascript", "/* not found */"))
                }
            }
            "/file/$token" -> {
                // Stream the file
                try {
                    val inputStream: InputStream? = context.contentResolver.openInputStream(fileUri)
                    if (inputStream == null) {
                        cors(newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "File not found"))
                    } else {
                        val mimeType = context.contentResolver.getType(fileUri) ?: "application/octet-stream"
                        val response = newFixedLengthResponse(Response.Status.OK, mimeType, inputStream, fileSize)
                        
                        // Content-Disposition forces download
                        val encodedFileName = URLEncoder.encode(fileName, "UTF-8").replace("+", "%20")
                        response.addHeader("Content-Disposition", "attachment; filename=\"$fileName\"; filename*=UTF-8''$encodedFileName")
                        cors(response)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error serving file", e)
                    cors(newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "Error reading file"))
                }
            }
            else -> {
                if (uri.startsWith("/file/")) {
                    cors(newFixedLengthResponse(Response.Status.UNAUTHORIZED, MIME_PLAINTEXT, "Invalid or expired token"))
                } else {
                    cors(newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Not Found"))
                }
            }
        }
    }
}
