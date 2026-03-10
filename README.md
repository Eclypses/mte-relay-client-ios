<center>
<img src="Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
MteRelay Mobile Client  
Swift Package</div>

![Latest Release](https://img.shields.io/github/v/release/Eclypses/mte-relay-client-ios?style=flat-square)

## Introduction
This Swift Package provides the Eclypses MteRelay Mobile Client for iOS. It enables secure, encrypted HTTP(S) communication between your iOS app and your backend via an MteRelay server. You must have licensed access to an MteRelay server instance. [More Info](https://eclypses.com/mte-technology/amazon-web-services-aws/)

**Purpose of MteRelay:**
- Securely relay HTTP requests to your server
- Protect sensitive headers and data with MTE encryption
- Stream large files efficiently

## Quick Links

📚 **[Official Getting Started Guide](https://public-docs.eclypses.com/docs/mte-relay-server/client-libraries/iOS)** - Concise guide for experienced developers

💡 This README provides comprehensive reference documentation with detailed examples suitable for developers at all experience levels. If you're already familiar with Swift async/await and MTE concepts, the official docs above offer a faster quick-start path.

## Prerequisites

- **iOS 14.0 or later** - Required because this library uses modern URLSession APIs and Swift concurrency features (async/await) that were stabilized in iOS 14
- **Swift 5.5 or later** - Needed for async/await support, which is central to how this library handles network operations
- **Xcode 13.0 or later** - For Swift 5.5 support and iOS 14.0 deployment
- **Access to a licensed MteRelay server instance** - This client library communicates with an MteRelay server that handles the encryption/decryption. You'll need the server URL and proper licensing credentials

## Installation

### Swift Package Manager (Recommended)

1. In Xcode, go to **File > Add Packages...**
2. Enter the package URL: `https://github.com/Eclypses/mte-relay-client-ios.git`
3. Select the version rule (we recommend "Up to Next Major Version")
4. Click **Add Package**
5. Select the target(s) where you want to use MteRelay
6. Click **Add Package** again to confirm

**Common SPM Issues:**
- **"Package resolution failed"** - Make sure you have a stable internet connection and GitHub is accessible
- **"Failed to clone repository"** - Verify you have access to the repository (some versions may be private)
- **Build errors after adding package** - Try **Product > Clean Build Folder** (Cmd+Shift+K) and rebuild

### CocoaPods

Add the following to your `Podfile`:
```ruby
pod 'MteRelay', :git => 'https://github.com/Eclypses/mte-relay-client-ios.git'
```

Then run:
```bash
pod install
```

**Common CocoaPods Issues:**
- **"Unable to find a specification"** - Run `pod repo update` to refresh your CocoaPods repository
- **Version conflicts** - Check that your iOS deployment target in the Podfile matches your project settings

## Setup

### Step 1: Configure Your MteRelay Server

**Important:** 
Before using this client library, ensure your MteRelay server is set up and configured to receive encrypted requests from your iOS app. The server handles the decryption and forwards requests to your actual backend API.

This is where you configure the connection between your MteRelay server and your actual backend API. The MteRelay server acts as a secure intermediary - it receives encrypted requests from your iOS app, decrypts them, and forwards them to your backend API endpoint.

### Step 2: Import the Module

In any Swift file where you'll use MteRelay, add the import statement:

```swift
import MteRelay
```

### Step 3: Create a Relay Instance

The `Relay` class is your main interface to the library. Here's a complete example of setting it up in a typical iOS app:

```swift
import Foundation
import MteRelay

// This class manages your network communication through MteRelay
class YourNetworkManager: RelayResponseDelegate {
    // The relay instance handles all encrypted communication
    var relay: Relay!
    
    // Store your MteRelay server URL (e.g., "https://your-relay-server.com")
    let relayServerUrl: String
    
    init(relayServerUrl: String) async throws {
        self.relayServerUrl = relayServerUrl
        
        // Initialize the Relay - this is an async operation that:
        // 1. Validates MTE licensing
        try await instantiateMteRelay()
    }
    
    func instantiateMteRelay() async throws {
        // Create the Relay instance - this may throw an error if licensing fails
        relay = try await Relay()
        
        // Set yourself as the delegate to receive pairing responses and errors
        // This is required for handling re-pairing operations and error notifications
        relay.relayResponseDelegate = self
        
        // Note: Pairing with the MteRelay server happens automatically when you
        // send your first request. You don't need to manually pair unless you're
        // re-pairing or adjusting settings.
    }
    
    // MARK: - RelayResponseDelegate
    
    /// This delegate method is called when pairing/re-pairing completes or fails
    /// - Parameters:
    ///   - success: Whether the pairing operation succeeded
    ///   - responseStr: A message describing the result
    ///   - errorMessage: If failed, contains details about the error
    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        if success {
            print("✅ Relay pairing successful: \(responseStr)")
        } else {
            print("❌ Relay pairing failed: \(errorMessage ?? "Unknown error")")
            // Handle pairing failure - you might want to:
            // - Show an alert to the user
            // - Retry pairing
            // - Fall back to unencrypted communication (not recommended)
        }
    }
}
```

**Understanding async/await:**
If you're new to Swift's async/await, here's what you need to know:
- Functions marked with `async` can perform operations that take time (like network requests)
- You call them with `await`, which means "wait for this to complete before continuing"
- Your calling context must also be `async` or wrap the call in a `Task { }`

**Example usage in a SwiftUI view:**
```swift
struct ContentView: View {
    @StateObject private var yourNetworkManager: YourNetworkManager?
    
    var body: some View {
        Text("Hello, MteRelay!")
            .task {
                // .task modifier provides an async context
                do {
                    let networkManager = try await YourNetworkManager(
                        relayServerUrl: "https://your-relay-server.com"
                    )
                    // Use the networkManager for network requests
                } catch {
                    print("Failed to initialize NetworkManager: \(error)")
                }
            }
    }
}
```

**Example usage in a UIKit view controller:**
```swift
class MyViewController: UIViewController {
    var yourNetworkManager: YourNetworkManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create an async task to initialize the network manager
        Task {
            do {
                networkManager = try await YourNetworkManager(
                    relayServerUrl: "https://your-relay-server.com"
                )
                print("NetworkManager ready to use")
            } catch {
                print("Failed to initialize: \(error)")
                // Show error to user
            }
        }
    }
}
```

## Usage

### Making Secure HTTP Requests

Once you've set up your `Relay` instance, you can use it to make secure requests. The library automatically encrypts your data, sends it through the MteRelay server, and decrypts the response.

**Important:** When creating your `URLRequest`, use your **MteRelay server URL** (not your actual backend API URL). The MteRelay server will decrypt your request and forward it to your actual backend.

#### Basic Example - GET Request

```swift
import Foundation

// Create a URLRequest using your MteRelay server URL
// The MteRelay server will forward the decrypted request to your actual backend API
var request = URLRequest(url: URL(string: "https://your-relay-server.com/api/users/123")!)
request.httpMethod = "GET"

// Add any headers your API needs
request.addValue("application/json", forHTTPHeaderField: "Accept")
request.addValue("Bearer abc123", forHTTPHeaderField: "Authorization")

// Specify which headers should be encrypted (optional but recommended for sensitive data)
// "Content-Type" header, if it exists, will always be encrypted.
// Headers not in this list will be sent unencrypted
let headersToEncrypt = ["Authorization"]

// Make the request through MteRelay
await relay.dataTask(
    with: request,
    headersToEncrypt: headersToEncrypt,
    pathnamePrefix: nil  // Optional path prefix, usually nil
) { (data, response, error) in
    // This closure is called when the request completes
    
    // Step 1: Check for errors
    if let error = error {
        print("Request failed: \(error.localizedDescription)")
        return
    }
    
    // Step 2: Verify we received data
    guard let data = data else {
        print("No data received")
        return
    }
    
    // Step 3: Check the HTTP response status
    if let httpResponse = response as? HTTPURLResponse {
        print("Status code: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("Server returned error status")
            return
        }
    }
    
    // Step 4: Parse the response data
    do {
        let json = try JSONSerialization.jsonObject(with: data)
        print("Response: \(json)")
        // Or decode into your model:
        // let user = try JSONDecoder().decode(User.self, from: data)
    } catch {
        print("Failed to parse response: \(error)")
    }
}
```

#### POST Request with JSON Body

```swift
// Create the request
var request = URLRequest(url: URL(string: "https://your-relay-server.com/users")!)
request.httpMethod = "POST"
request.addValue("application/json", forHTTPHeaderField: "Content-Type")
request.addValue("Bearer abc123", forHTTPHeaderField: "Authorization")

// Create and encode the request body
let userData = ["name": "John Doe", "email": "john@example.com"]
request.httpBody = try? JSONSerialization.data(withJSONObject: userData)

// Encrypt the Authorization header
let headersToEncrypt = ["Authorization"]

// Make the request
await relay.dataTask(
    with: request,
    headersToEncrypt: headersToEncrypt,
    pathnamePrefix: nil
) { (data, response, error) in
    // Handle the response (same as GET example above)
    guard let data = data, error == nil else {
        print("Error: \(error?.localizedDescription ?? "Unknown")")
        return
    }
    
    // Parse response
    if let httpResponse = response as? HTTPURLResponse {
        print("Created user, status: \(httpResponse.statusCode)")
    }
}
```

**Parameter Details:**

- **`with`** (`URLRequest`) - Your standard URLRequest object configured with URL, method, headers, and body
- **`headersToEncrypt`** (`[String]?`) - Array of header names to encrypt. For example, `["Authorization", "X-API-Key"]`. Headers not in this list are sent unencrypted. Pass `nil` or `[]` to send all headers unencrypted (not recommended for sensitive data)
- **`pathnamePrefix`** (`String?`) - Optional path to prepend to requests on the relay server. This is typically `nil` unless your relay server is configured with specific routing paths. For example, if your relay handles multiple backends, you might use `"/api/v1"` to route to a specific one
- **`preventStreaming`** (`Bool`, default `false`) - When `true`, signals the relay server to disable its normal HTTP streaming handling and redirect the request for non-standard processing. This is rarely needed in a mobile client; omit it or pass `false` for all typical requests. Not available on streaming upload/download calls.
- **Completion handler** - A closure called when the request completes, providing the decrypted `Data`, `URLResponse`, and any `Error`

### File Upload (Streaming)

For uploading files, especially large ones, use the streaming upload API. This is more memory-efficient than loading the entire file into memory.

**When to use streaming vs regular requests:**
- **Use streaming** for files larger than a few MB, video uploads, or when you want progress tracking
- **Use regular `dataTask`** for small payloads (JSON, small images under 1-2 MB)

**Important:** The `uploadFileStream()` method is synchronous but uses delegates for completion. It throws errors if it cannot start the upload. The actual upload completion is reported through `RelayStreamResponseDelegate`.

#### Complete Streaming Upload Example

```swift
import Foundation
import MteRelay

class FileUploadManager: RelayStreamDelegate, 
                         RelayStreamResponseDelegate, 
                         RelayStreamCompletionDelegate {
    
    var relay: Relay!
    private var multipartHelper: MultipartHelper?
    
    init(relay: Relay) {
        self.relay = relay
        
        // Set up all three streaming delegates
        relay.relayStreamDelegate = self
        relay.relayStreamResponseDelegate = self
        relay.relayStreamCompletionDelegate = self
    }
    
    /// Upload a file using streaming with multipart/form-data
    func uploadFile(at fileURL: URL) throws {
        // Create multipart helper for assembling the request body
        multipartHelper = try MultipartHelper(fileURL: fileURL)
        
        guard let helper = multipartHelper else { return }
        
        // Create the upload request
        var request = URLRequest(url: URL(string: "https://your-relay-server.com/users")!)
        request.httpMethod = "POST"
        
        // Set multipart content type with boundary
        request.setValue("multipart/form-data; boundary=\(helper.boundary)", 
                        forHTTPHeaderField: "Content-Type")
        
        // Calculate and set content length (required for streaming uploads)
        let contentLength = helper.calculateContentLength()
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        
        // Optional: encrypt sensitive headers
        let headersToEncrypt: [String]? = nil  // Ex. ["Authorization"] if needed
        
        // Start the upload - this throws if it cannot start
        // Completion is reported through RelayStreamResponseDelegate
        try relay.uploadFileStream(
            request: request,
            headersToEncrypt: headersToEncrypt,
            pathnamePrefix: nil
        )
    }
    
    // MARK: - RelayStreamDelegate
    
    /// Called by the Relay to get the file data to upload.
    /// You MUST write the complete multipart body to the outputStream:
    /// 1. Multipart prefix (boundary + headers)
    /// 2. File data
    /// 3. Multipart postfix (closing boundary)
    /// Then close the outputStream when done.
    func getRequestBodyStream(outputStream: OutputStream) {
        guard let helper = multipartHelper else {
            print("No multipart helper available")
            return
        }
        
        // Check stream is ready
        if outputStream.hasSpaceAvailable {
            // Write complete multipart body to stream
            // This includes: prefix + file data + postfix
            helper.assembleMultipartWithFile(outputStream: outputStream)
            // Note: assembleMultipartWithFile closes the outputStream when done
        }
    }
    
    // MARK: - RelayStreamCompletionDelegate
    
    /// Called periodically during upload to report progress
    func streamCompletionPercentage(from relayServerUrl: String, 
                                   bytesCompleted: Double, 
                                   totalBytes: Double) {
        let percentage = (bytesCompleted / totalBytes) * 100
        print("Upload progress: \(String(format: "%.1f", percentage))%")
        
        // Update your UI on the main thread
        DispatchQueue.main.async {
            // Update progress bar, label, etc.
            // self.progressBar.progress = Float(bytesCompleted / totalBytes)
        }
    }
    
    // MARK: - RelayStreamResponseDelegate
    
    /// Called when upload completes (successfully or with error)
    func relayStreamResponse(from relayServerUrl: String, 
                           data: Data?, 
                           response: URLResponse?, 
                           error: Error?) {
        if let error = error {
            print("❌ Upload failed: \(error.localizedDescription)")
            // Handle error - retry, show alert, etc.
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response")
            return
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            print("✅ Upload successful!")
            
            // Parse response data if needed
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) {
                print("Server response: \(json)")
            }
        } else {
            print("❌ Server returned error: \(httpResponse.statusCode)")
        }
    }
}

// MARK: - MultipartHelper

/// Helper class for assembling multipart/form-data uploads
class MultipartHelper {
    let boundary: String
    let fileURL: URL
    let filename: String
    private var fileHandle: FileHandle?
    
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.filename = fileURL.lastPathComponent
        self.boundary = "Boundary-\(UUID().uuidString)"
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "MultipartHelper", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "File not found at \(fileURL.path)"])
        }
    }
    
    /// Calculate total content length (prefix + file + postfix)
    func calculateContentLength() -> Int {
        var contentLength = 0
        
        // Prefix length
        contentLength += getMultipartPrefix().count
        
        // File size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fileSize = attributes[.size] as? Int {
            contentLength += fileSize
        }
        
        // Postfix length
        contentLength += getMultipartPostfix().count
        
        return contentLength
    }
    
    /// Get multipart prefix (boundary and headers)
    func getMultipartPrefix() -> [UInt8] {
        var buffer = [UInt8]()
        buffer.append(contentsOf: "--\(boundary)\r\n".utf8)
        buffer.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8)
        buffer.append(contentsOf: "Content-Type: application/octet-stream\r\n\r\n".utf8)
        return buffer
    }
    
    /// Get multipart postfix (closing boundary)
    func getMultipartPostfix() -> [UInt8] {
        var buffer = [UInt8]()
        buffer.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
        return buffer
    }
    
    /// Assemble and write complete multipart data to output stream
    @discardableResult
    func assembleMultipartWithFile(outputStream: OutputStream) -> Int {
        var totalBytesWritten = 0
        
        do {
            // Open file handle
            fileHandle = try FileHandle(forReadingFrom: fileURL)
            
            // Write prefix
            let prefixBytes = writeToOutputStream(outputStream: outputStream, 
                                                  buffer: Data(getMultipartPrefix()))
            totalBytesWritten += prefixBytes
            
            // Write file data in chunks
            let bufferSize = 1024 * 1024 // 1MB chunks
            var data: Data
            
            repeat {
                if let handle = fileHandle {
                    data = handle.readData(ofLength: bufferSize)
                    if data.count > 0 {
                        let fileBytes = writeToOutputStream(outputStream: outputStream, buffer: data)
                        totalBytesWritten += fileBytes
                    }
                } else {
                    break
                }
            } while data.count > 0
            
            // Write postfix
            let postfixBytes = writeToOutputStream(outputStream: outputStream, 
                                                   buffer: Data(getMultipartPostfix()))
            totalBytesWritten += postfixBytes
            
            // Close stream and file
            outputStream.close()
            try fileHandle?.close()
            
        } catch {
            print("Error assembling multipart: \(error.localizedDescription)")
        }
        
        return totalBytesWritten
    }
    
    /// Write data buffer to output stream
    private func writeToOutputStream(outputStream: OutputStream, buffer: Data) -> Int {
        var bytesLeft = buffer.count
        var totalBytesWritten = 0
        
        while bytesLeft > 0 {
            let range = totalBytesWritten..<totalBytesWritten + bytesLeft
            let chunk = buffer.subdata(in: range)
            
            let bytesWritten = chunk.withUnsafeBytes {
                outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytesLeft)
            }
            
            if bytesWritten < 0 {
                if let streamError = outputStream.streamError {
                    print("Stream error: \(streamError.localizedDescription)")
                }
                break
            }
            
            totalBytesWritten += bytesWritten
            bytesLeft -= bytesWritten
        }
        
        return totalBytesWritten
    }
}

// Usage:
do {
    let uploadManager = FileUploadManager(relay: myRelay)
    let fileURL = URL(fileURLWithPath: "/path/to/large-file.mp4")
    try uploadManager.uploadFile(at: fileURL, to: "https://your-relay-server.com/api/upload")
} catch {
    print("Failed to start upload: \(error)")
}
```

### File Download (Streaming)

Download large files efficiently using the streaming download API.

**Important:** 
- The `downloadFileStream()` method is **synchronous** (not async) but **throws** errors
- You must **pre-create the destination file** before calling `downloadFileStream()`
- Completion is reported through `RelayStreamResponseDelegate`
- Progress is reported through `RelayStreamCompletionDelegate`

#### Complete Streaming Download Example

```swift
import Foundation
import MteRelay

class FileDownloadManager: RelayStreamResponseDelegate, 
                          RelayStreamCompletionDelegate {
    
    var relay: Relay!
    private var downloadedFileURL: URL?
    
    init(relay: Relay) {
        self.relay = relay
        
        // Set up streaming delegates
        relay.relayStreamResponseDelegate = self
        relay.relayStreamCompletionDelegate = self
    }
    
    /// Download a file and save it to the specified location
    /// - Parameters:
    ///   - endpoint: The download URL (should include urlEncoded filename in path)
    ///   - localURL: Where to save the downloaded file
    func downloadFile(from endpoint: String, saveTo localURL: URL) throws {
        self.downloadedFileURL = localURL
        
        // Create the download request
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        
        // Optional: Add authorization if needed
        // request.addValue("Bearer your-token", forHTTPHeaderField: "Authorization")
        
        // Create parent directory if needed
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, 
                                                withIntermediateDirectories: true)
        
        // IMPORTANT: Pre-create the file - the relay writes to an existing file
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        
        // Encrypt sensitive headers if needed (use empty array if none)
        // Note: Don't try to encrypt headers that don't exist in the request
        let headersToEncrypt: [String] = []  // Or ["Authorization"] if you added one
        
        // Start the download - this throws if it cannot start
        // Completion is reported through RelayStreamResponseDelegate
        try relay.downloadFileStream(
            request: request,
            downloadUrl: localURL,
            headersToEncrypt: headersToEncrypt,
            pathnamePrefix: nil
        )
    }
    
    // MARK: - RelayStreamCompletionDelegate
    
    /// Called periodically during download to report progress
    func streamCompletionPercentage(from relayServerUrl: String, 
                                   bytesCompleted: Double, 
                                   totalBytes: Double) {
        let percentage = (bytesCompleted / totalBytes) * 100
        print("Download progress: \(String(format: "%.1f", percentage))%")
        
        // Update UI on main thread
        DispatchQueue.main.async {
            // Update progress indicator
            // self.progressView.progress = Float(bytesCompleted / totalBytes)
            // self.statusLabel.text = "\(Int(percentage))% complete"
        }
    }
    
    // MARK: - RelayStreamResponseDelegate
    
    /// Called when download completes
    func relayStreamResponse(from relayServerUrl: String, 
                           data: Data?, 
                           response: URLResponse?, 
                           error: Error?) {
        if let error = error {
            print("❌ Download failed: \(error.localizedDescription)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response")
            return
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            print("✅ Download complete!")
            print("File saved to: \(downloadedFileURL?.path ?? "unknown")")
            
            // Verify the file exists and get size
            if let url = downloadedFileURL, 
               FileManager.default.fileExists(atPath: url.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes?[.size] as? Int ?? 0
                print("File size: \(fileSize) bytes")
            }
        } else {
            print("❌ Server returned error: \(httpResponse.statusCode)")
        }
    }
}

// Usage:
do {
    let downloadManager = FileDownloadManager(relay: myRelay)
    
    // Create save location
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let saveURL = documentsDir
        .appendingPathComponent("Downloads")
        .appendingPathComponent("video.mp4")
    
    // Download - note the filename is typically in the URL path
    try downloadManager.downloadFile(
        from: "https://your-relay-server.com/api/files/download/video.mp4",
        saveTo: saveURL
    )
} catch {
    print("Failed to start download: \(error)")
}
```

### Re-Pairing with the Server

**What is pairing?**
When your app first connects to the MteRelay server, it establishes encryption "pairs" - synchronized encryption/decryption states. Sometimes you need to re-establish these pairs, such as:
- After server restart or deployment
- When encountering persistent decryption errors
- When switching between development/production environments
- As part of a security refresh policy

**When to re-pair:**
- After receiving specific error messages from the relay server
- If you implement a periodic re-pairing schedule (e.g., every 24 hours)
- When you detect authentication or encryption failures

```swift
do {
    // Re-establish encryption pairs with the relay server
    // This is an async operation that may take a few seconds
    try await relay.rePairwithRelayServer(
        relayServerUrlString: "https://your-relay-server.com",
        pathnamePrefix: nil
    )
    print("✅ Re-pairing successful")
    
    // Your relayResponseDelegate.relayResponse() will also be called
    // with the pairing result
    
} catch {
    print("❌ Re-pairing failed: \(error.localizedDescription)")
    // Handle failure - maybe retry or alert user
}
```

**Alternative without pathnamePrefix:**
```swift
try await relay.rePairwithRelayServer(relayServerUrlString: "https://your-relay-server.com")
```

### Adjusting Relay Settings

You can customize how the Relay behaves by adjusting various settings. These affect performance, memory usage, and security.

#### Settings Explained

**`streamChunkSize`** (bytes, default: 1,048,576 = 1MB)
- Size of chunks when streaming files
- **Larger values** = faster transfer but more memory usage
- **Smaller values** = slower transfer but lower memory footprint
- **Recommendations:**
  - **Low-end devices** or **limited bandwidth**: 512KB (524,288)
  - **Standard usage**: 1MB (1,048,576) - default
  - **High-performance needs**: 2-4MB (2,097,152 - 4,194,304)

**`pairPoolSize`** (default: 5)
- Number of encryption pairs to maintain
- Each pair allows one concurrent request
- **Larger values** = more concurrent requests but more memory
- **Smaller values** = fewer concurrent requests but less overhead
- **Recommendations:**
  - **Light usage** (few concurrent requests): 3
  - **Standard usage**: 5 - default
  - **Heavy usage** (many concurrent requests): 10

**`persistPairs`** (boolean, default: false)
- Whether to save pairs to device storage between app launches
- **`true`** = Faster app startup (no re-pairing needed), but pairs stored on device
- **`false`** = Must re-pair on each app launch, but no persistent storage
- **Recommendations:**
  - **Use `true`** for apps that make frequent restarts and need fast startup
  - **Use `false`** for maximum security or infrequent startups

#### Complete Settings Example

```swift
// Adjust settings and re-pair with new configuration
do {
    try await relay.adjustRelaySettings(
        serverUrl: "https://your-relay-server.com",
        pathnamePrefix: nil,
        newStreamChunkSize: 2_097_152,  // 2MB chunks for better performance
        newPairPoolSize: 10,             // Support 10 concurrent requests
        persistPairs: true               // Persist pairs for faster app startup
    )
    print("✅ Settings updated and re-paired successfully")
    
    // The relayResponseDelegate.relayResponse() method will be called
    // with details about what changed
    
} catch {
    print("❌ Failed to adjust settings: \(error.localizedDescription)")
}
```

**Note:** Setting any size parameter to `0` means "don't change this setting."

### Logging

The MteRelay library includes built-in file logging to help you debug issues during development and diagnose problems in production.

#### When to Use Logging

**✅ Enable logging when:**
- Developing and testing your integration
- Troubleshooting pairing or encryption issues
- Diagnosing network problems
- Investigating user-reported issues (in production, temporarily)

**❌ Consider disabling logging when:**
- App is stable and working correctly
- Concerned about storage space (logs can grow large)
- Maximum performance is needed

#### Enabling File Logging

```swift
import MteRelay

// Enable logging (typically in AppDelegate or app initialization)
Relay.enableFileLogging(true)

// Now all Relay operations will be logged to a file
// This includes:
// - Pairing operations
// - Encryption/decryption events
// - Network requests and responses
// - Errors and warnings
```

#### Reading Log Files

```swift
do {
    // Read the entire log file contents
    if let logContents = try Relay.readLogFile() {
        print("=== MteRelay Logs ===")
        print(logContents)
        
        // You might want to:
        // 1. Display in a debug view in your app
        // 2. Send to your analytics service
        // 3. Email to support
        // 4. Write to console for Xcode debugging
    } else {
        print("No log file exists yet")
    }
} catch {
    print("Error reading log file: \(error.localizedDescription)")
}
```

#### Clearing Log Files

```swift
// Clear the log file to free up space
// Good to do periodically or after resolving an issue
Relay.clearLogFile()
print("Log file cleared")
```

#### Interpreting Logs

**Understanding log levels:**
```
ℹ️ INFO    - Normal operations (pairing started, request sent, etc.)
⚠️ WARNING - Potential issues (retry attempts, deprecated API usage)
❌ ERROR   - Failures (pairing failed, decryption error, network timeout)
🔥 FAULT   - Critical errors (licensing failure, fatal configuration error)
```

**Common log entries and what they mean:**

```
"Using iOS Relay Version X.X.X and MTE Version Y.Y.Y"
  ✅ Relay initialized successfully

"License Check failed"
  ❌ MTE license is invalid or expired - check your credentials

"RelayResponse Error: ..."
  ❌ Pairing operation failed - check network and server status

"RelayStreamResponse Error: ..."
  ❌ File streaming failed - check file permissions and network

"Unable to retrieve Relay Server URL from request"
  ❌ Request URL is invalid or missing
```

#### Complete Logging Example

```swift
class DebugViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Enable logging for debugging
        Relay.enableFileLogging(true)
    }
    
    @IBAction func showLogsTapped(_ sender: Any) {
        do {
            guard let logs = try Relay.readLogFile() else {
                showAlert("No logs available")
                return
            }
            
            // Display logs in a text view or share sheet
            let alert = UIAlertController(
                title: "Debug Logs",
                message: logs,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            alert.addAction(UIAlertAction(title: "Clear Logs", style: .destructive) { _ in
                Relay.clearLogFile()
            })
            present(alert, animated: true)
            
        } catch {
            showAlert("Error reading logs: \(error.localizedDescription)")
        }
    }
    
    @IBAction func clearLogsTapped(_ sender: Any) {
        Relay.clearLogFile()
        showAlert("Logs cleared successfully")
    }
    
    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

**Best Practice:**
In production apps, consider adding a hidden debug menu (e.g., tap app version 5 times) that allows you to:
1. Enable/disable logging
2. View current logs
3. Export logs for support
4. Clear logs

## Delegates Reference

The MteRelay library uses delegates to communicate asynchronous events back to your app. Understanding these delegates is crucial for proper integration.

### RelayResponseDelegate (Required)

**Purpose:** Receives responses from pairing operations and general relay errors.

**When to use:** You must implement this delegate when using the Relay class.

```swift
public protocol RelayResponseDelegate: AnyObject {
    func relayResponse(success: Bool, responseStr: String, errorMessage: String?)
}
```

**Parameters:**
- `success`: `true` if operation succeeded, `false` if failed
- `responseStr`: Description of what happened (e.g., "Re-Paired with server successfully")
- `errorMessage`: If `success` is `false`, contains error details; otherwise `nil`

**Example implementation:**
```swift
func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
    if success {
        print("✅ Relay operation successful: \(responseStr)")
        // Update UI to show ready state
    } else {
        print("❌ Relay operation failed: \(errorMessage ?? "Unknown error")")
        // Show error alert to user
        // Maybe attempt retry
    }
}
```

---

### RelayStreamDelegate (Required for file uploads)

**Purpose:** Provides file data to upload when streaming files.

**When to use:** Required when calling `uploadFileStream()`.

```swift
public protocol RelayStreamDelegate: AnyObject {
    func getRequestBodyStream(outputStream: OutputStream)
}
```

**Parameters:**
- `outputStream`: The stream to write your file data to

**What this does:** The Relay calls this method when it's ready to send data. You must write the complete request body to `outputStream` and close it when done. For multipart uploads, this includes the boundary headers, file data, and closing boundary.

**Example implementation:**
```swift
func getRequestBodyStream(outputStream: OutputStream) {
    guard let helper = multipartHelper else { return }
    
    if outputStream.hasSpaceAvailable {
        // Write complete multipart body (prefix + file + postfix)
        // then close the stream
        helper.assembleMultipartWithFile(outputStream: outputStream)
    }
}
```

---

### RelayStreamResponseDelegate (Required for streaming operations)

**Purpose:** Receives the final response when a streaming operation (upload or download) completes.

**When to use:** Required when using `uploadFileStream()` or `downloadFileStream()` to know when the operation finishes and whether it succeeded.

```swift
public protocol RelayStreamResponseDelegate: AnyObject {
    func relayStreamResponse(from relayServerUrl: String, 
                           data: Data?, 
                           response: URLResponse?, 
                           error: Error?)
}
```

**Parameters:**
- `relayServerUrl`: URL of the relay server that handled this request
- `data`: Response body data (if any)
- `response`: HTTP response with status code and headers
- `error`: If operation failed, contains the error; otherwise `nil`

**Example implementation:**
```swift
func relayStreamResponse(from relayServerUrl: String, 
                        data: Data?, 
                        response: URLResponse?, 
                        error: Error?) {
    if let error = error {
        print("Streaming failed: \(error.localizedDescription)")
        return
    }
    
    if let httpResponse = response as? HTTPURLResponse {
        print("Streaming completed with status: \(httpResponse.statusCode)")
        
        if let data = data {
            // Parse response (e.g., server might return file info)
            print("Received \(data.count) bytes")
        }
    }
}
```

---

### RelayStreamCompletionDelegate (Optional, for progress tracking)

**Purpose:** Provides progress updates during streaming operations.

**When to use:** Set this delegate when you want to show upload/download progress to the user.

```swift
public protocol RelayStreamCompletionDelegate: AnyObject {
    func streamCompletionPercentage(from relayServerUrl: String, 
                                   bytesCompleted: Double, 
                                   totalBytes: Double)
}
```

**Parameters:**
- `relayServerUrl`: URL of the relay server
- `bytesCompleted`: Number of bytes transferred so far
- `totalBytes`: Total bytes to transfer

**Call frequency:** Called periodically during the transfer (approximately every chunk).

**Example implementation:**
```swift
func streamCompletionPercentage(from relayServerUrl: String, 
                               bytesCompleted: Double, 
                               totalBytes: Double) {
    let percentage = (bytesCompleted / totalBytes) * 100
    
    DispatchQueue.main.async {
        // Update UI on main thread
        self.progressBar.progress = Float(bytesCompleted / totalBytes)
        self.statusLabel.text = String(format: "%.1f%% (%.1f MB / %.1f MB)", 
                                      percentage,
                                      bytesCompleted / 1_048_576,
                                      totalBytes / 1_048_576)
    }
}
```

---

### Summary: Which Delegates Do I Need?

| Operation | Required Delegates | Optional Delegates |
|-----------|-------------------|-------------------|
| Basic requests (`dataTask`) | `RelayResponseDelegate` | None |
| File upload (`uploadFileStream`) | `RelayResponseDelegate`<br>`RelayStreamDelegate`<br>`RelayStreamResponseDelegate` | `RelayStreamCompletionDelegate` |
| File download (`downloadFileStream`) | `RelayResponseDelegate`<br>`RelayStreamResponseDelegate` | `RelayStreamCompletionDelegate` |
| Re-pairing | `RelayResponseDelegate` | None |
| Adjust settings | `RelayResponseDelegate` | None |

## Troubleshooting

This section covers common issues and their solutions.

### Pairing Issues

**Problem: "License Check failed" error**
```swift
// Error in logs: "License Check failed."
```
**Solutions:**
1. Verify your license credentials in the Settings.swift file (or your configuration)
2. Check that `Settings.licCompanyName` and `Settings.licCompanyKey` are correct
3. Contact Eclypses support to verify your license is active
4. Ensure your bundle identifier matches your license

---

**Problem: Pairing fails repeatedly**
```swift
// relayResponse(success: false, ...)
```
**Solutions:**
1. **Check relay server is running:**
   ```bash
   curl https://your-relay-server.com/health
   ```
2. **Verify server URL is correct:**
   - No trailing slashes
   - Correct protocol (https:// vs http://)
   - Correct port if using non-standard
3. **Check network connectivity:**
   - Device has internet access
   - No firewall blocking the connection
   - VPN not interfering
4. **Check server logs** for errors on the relay server side
5. **Try re-pairing manually:**
   ```swift
   try await relay.rePairwithRelayServer(relayServerUrlString: serverUrl)
   ```

---

### Network & Connection Issues

**Problem: Requests fail with timeout errors**
**Solutions:**
1. Increase timeout in URLRequest:
   ```swift
   var request = URLRequest(url: url)
   request.timeoutInterval = 60 // seconds
   ```
2. Check relay server is responsive
3. For large files, ensure `streamChunkSize` isn't too large:
   ```swift
   try await relay.adjustRelaySettings(
       serverUrl: serverUrl,
       pathnamePrefix: nil,
       newStreamChunkSize: 524_288, // Try smaller: 512KB
       newPairPoolSize: 5,
       persistPairs: false
   )
   ```

---

**Problem: "Unable to retrieve Relay Server URL from request"**
**Solutions:**
1. Ensure your URLRequest has a valid URL:
   ```swift
   guard let url = URL(string: "https://your-relay-server.com/endpoint") else {
       print("Invalid URL")
       return
   }
   let request = URLRequest(url: url)
   ```
2. Check URL is properly formatted (no spaces, valid characters)

---

### Streaming Issues

**Problem: File uploads fail or freeze**
**Solutions:**
1. **Verify file exists and is readable:**
   ```swift
   let fileManager = FileManager.default
   guard fileManager.fileExists(atPath: fileURL.path),
         fileManager.isReadableFile(atPath: fileURL.path) else {
       print("File not accessible")
       return
   }
   ```
2. **Check file size isn't exceeding limits:**
   ```swift
   let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
   let fileSize = attributes[.size] as! Int
   print("File size: \(fileSize) bytes")
   // Some servers have upload size limits
   ```
3. **Ensure all required delegates are set:**
   ```swift
   relay.relayStreamDelegate = self
   relay.relayStreamResponseDelegate = self
   relay.relayStreamCompletionDelegate = self
   ```
4. **Verify `getRequestBodyStream` implementation closes the stream**
5. **Ensure Content-Length header is set correctly** (must match total multipart size)

---

**Problem: Downloads fail with 500 error**
**Solutions:**
1. **Don't encrypt headers that don't exist in the request:**
   ```swift
   // WRONG: Trying to encrypt Content-Type on a GET request
   let headersToEncrypt = ["Content-Type"]  // ❌
   
   // CORRECT: Use empty array or only encrypt headers you actually set
   let headersToEncrypt: [String] = []  // ✅
   ```
2. **Ensure the destination file is pre-created:**
   ```swift
   FileManager.default.createFile(atPath: saveURL.path, contents: nil)
   ```
3. **Verify the download URL path is correct**

---

**Problem: Downloads fail or save corrupted files**
**Solutions:**
1. **Pre-create the destination file:**
   ```swift
   // Remove existing file first
   if FileManager.default.fileExists(atPath: localURL.path) {
       try FileManager.default.removeItem(at: localURL)
   }
   // Create empty file for relay to write to
   FileManager.default.createFile(atPath: localURL.path, contents: nil)
   ```
2. **Ensure download directory exists:**
   ```swift
   let parentDir = localURL.deletingLastPathComponent()
   try FileManager.default.createDirectory(at: parentDir, 
                                           withIntermediateDirectories: true)
   ```
3. **Check disk space is available**
4. **Verify response status code is successful (200-299)**

---

### Memory & Performance Issues

**Problem: High memory usage during file operations**
**Solutions:**
1. **Use streaming APIs, not `dataTask` for large files**
2. **Reduce chunk size:**
   ```swift
   try await relay.adjustRelaySettings(
       serverUrl: serverUrl,
       pathnamePrefix: nil,
       newStreamChunkSize: 524_288, // 512KB instead of 1MB
       newPairPoolSize: 5,
       persistPairs: false
   )
   ```
3. **Reduce pair pool size if making few concurrent requests:**
   ```swift
   newPairPoolSize: 3 // Instead of 10+
   ```

---

**Problem: Slow performance**
**Solutions:**
1. **Increase chunk size for better throughput:**
   ```swift
   newStreamChunkSize: 2_097_152 // 2MB
   ```
2. **Enable pair persistence to avoid re-pairing:**
   ```swift
   persistPairs: true
   ```
3. **Increase pair pool size for more concurrent requests:**
   ```swift
   newPairPoolSize: 10
   ```
4. **Check network conditions** (Wi-Fi vs cellular)

---

### Platform-Specific Issues

**Problem: Works in simulator but fails on device**
**Solutions:**
1. **Check App Transport Security settings** in Info.plist if using HTTP (not recommended):
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   ```
2. **Verify code signing and provisioning profiles**
3. **Check device has network permissions in Settings**

---

**Problem: Issues with iOS 14.x but works on iOS 15+**
**Solutions:**
1. Test on actual iOS 14 device (simulators can behave differently)
2. Check for iOS 14-specific URLSession bugs (rare)
3. Ensure async/await code is compatible with iOS 14

---

### Debugging Tips

1. **Enable detailed logging:**
   ```swift
   Relay.enableFileLogging(true)
   ```

2. **Add breakpoints** in delegate methods to inspect data

3. **Use network debugging tools:**
   - Charles Proxy or Proxyman to inspect traffic
   - Xcode's Network Instruments

4. **Check both client and server logs** - issues can be on either side

5. **Test with a simple request first:**
   ```swift
   // Start with minimal example
   var request = URLRequest(url: URL(string: "https://your-relay-server.com/ping")!)
   request.httpMethod = "GET"
   
   await relay.dataTask(with: request, headersToEncrypt: nil, pathnamePrefix: nil) { data, response, error in
       print("Simple request result: \(String(describing: response))")
   }
   ```

6. **Verify MTE version compatibility:**
   ```swift
   print("MTE Version: \(MteBase.getVersion())")
   ```

7. **For contributors running coverage locally:**
    - Coverage outputs are generated under `artifacts/coverage/`
    - This directory is git-ignored by design, so local coverage runs do not pollute diffs

---

### Getting Help

If you're still stuck after trying these solutions:

1. **Gather information:**
   - iOS version
   - Device model
   - MteRelay library version
   - Error messages from logs
   - Steps to reproduce

2. **Check official documentation:**
   - [Getting Started Guide](https://public-docs.eclypses.com/docs/mte-relay-server/client-libraries/iOS)
   - Server-side MteRelay documentation

3. **Contact support:**
   - Email: [info@eclypses.com](mailto:info@eclypses.com)
   - Developer Portal: [developers.eclypses.com/dashboard](https://developers.eclypses.com/dashboard)
   - Include logs and detailed description

## API Reference

Complete reference of the main Relay class methods.

### Relay Class Methods

#### `init() async throws`
Initializes the Relay instance.
- **Throws:** Error if MTE license validation fails
- **Usage:** `let relay = try await Relay()`

---

#### `dataTask(with:headersToEncrypt:pathnamePrefix:completionHandler:)`
Makes an encrypted HTTP request.
- **Parameters:**
  - `with`: URLRequest to send
  - `headersToEncrypt`: Array of header names to encrypt (optional)
  - `pathnamePrefix`: Path prefix for relay routing (optional)
  - `completionHandler`: Closure called with (Data?, URLResponse?, Error?)
- **Returns:** Void (async)
- **Usage:** See "Making Secure HTTP Requests" section above

---

#### `uploadFileStream(request:headersToEncrypt:pathnamePrefix:) throws`
Uploads a file using streaming. This is a **synchronous** method that **throws**.
- **Parameters:**
  - `request`: URLRequest configured for upload (must include Content-Type and Content-Length headers)
  - `headersToEncrypt`: Array of header names to encrypt (optional)
  - `pathnamePrefix`: Path prefix for relay routing (optional)
- **Throws:** Error if upload cannot start
- **Requires:** `relayStreamDelegate` must be set to provide file data
- **Completion:** Reported through `RelayStreamResponseDelegate.relayStreamResponse()`
- **Usage:** See "File Upload (Streaming)" section above

---

#### `downloadFileStream(request:downloadUrl:headersToEncrypt:pathnamePrefix:) throws`
Downloads a file using streaming. This is a **synchronous** method that **throws**.
- **Parameters:**
  - `request`: URLRequest configured for download
  - `downloadUrl`: Local URL where file will be saved (**file must be pre-created**)
  - `headersToEncrypt`: Array of header names to encrypt (optional) - only include headers that exist in the request
  - `pathnamePrefix`: Path prefix for relay routing (optional)
- **Throws:** Error if download cannot start
- **Completion:** Reported through `RelayStreamResponseDelegate.relayStreamResponse()`
- **Important:** You must create an empty file at `downloadUrl` before calling this method
- **Usage:** See "File Download (Streaming)" section above

---

#### `rePairwithRelayServer(relayServerUrlString:pathnamePrefix:)`
Re-establishes encryption pairs with the relay server.
- **Parameters:**
  - `relayServerUrlString`: URL of your relay server
  - `pathnamePrefix`: Path prefix (optional)
- **Throws:** Error if re-pairing fails
- **Returns:** Void (async)
- **Usage:** See "Re-Pairing with the Server" section above

---

#### `adjustRelaySettings(serverUrl:pathnamePrefix:newStreamChunkSize:newPairPoolSize:persistPairs:)`
Updates relay configuration and re-pairs if settings changed.
- **Parameters:**
  - `serverUrl`: URL of your relay server
  - `pathnamePrefix`: Path prefix (optional)
  - `newStreamChunkSize`: Chunk size in bytes (0 = no change)
  - `newPairPoolSize`: Number of pairs to maintain (0 = no change)
  - `persistPairs`: Whether to persist pairs to storage
- **Throws:** Error if adjustment fails
- **Returns:** Void (async)
- **Usage:** See "Adjusting Relay Settings" section above

---

#### Static Methods

##### `enableFileLogging(_:)`
Enables or disables file logging.
- **Parameters:**
  - `enabled`: true to enable logging, false to disable
- **Usage:** `Relay.enableFileLogging(true)`

##### `readLogFile() throws -> String?`
Reads the contents of the log file.
- **Returns:** Log file contents as String, or nil if no log file
- **Throws:** Error if log file cannot be read
- **Usage:** `let logs = try Relay.readLogFile()`

##### `clearLogFile()`
Deletes the log file.
- **Usage:** `Relay.clearLogFile()`

---

### Delegate Properties

Set these properties on your Relay instance to receive callbacks:

```swift
var relayResponseDelegate: RelayResponseDelegate?        // Required
var relayStreamDelegate: RelayStreamDelegate?            // For uploads
var relayStreamResponseDelegate: RelayStreamResponseDelegate?  // For streaming completion
var relayStreamCompletionDelegate: RelayStreamCompletionDelegate? // For streaming progress
```

See the "Delegates Reference" section for detailed information.

---

### Key Classes and Protocols

- **`Relay`** - Main entry point for secure requests and file streaming
- **`RelayResponseDelegate`** - Protocol for receiving pairing responses and errors
- **`RelayStreamDelegate`** - Protocol for providing file data during upload
- **`RelayStreamResponseDelegate`** - Protocol for receiving streaming operation results
- **`RelayStreamCompletionDelegate`** - Protocol for receiving progress updates
- **`Settings`** - Internal configuration (typically not accessed directly)

## Support
**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)  
**Developer Portal:** [developers.eclypses.com/dashboard](https://developers.eclypses.com/dashboard)

---
**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
