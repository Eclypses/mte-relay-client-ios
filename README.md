<center>
<img src="Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
MTE Relay Mobile Client  
Swift Package</div>

![Latest Release](https://img.shields.io/github/v/release/Eclypses/mte-relay-client-ios?style=flat-square)

## Introduction
This Swift Package provides the Eclypses MTE Relay Mobile Client for iOS. It enables secure, encrypted HTTP(S) communication between your iOS app and your backend via an MTE Relay server. You must have licensed access to an MTE Relay server instance. [More Info](https://eclypses.com/mte-technology/amazon-web-services-aws/)

**Purpose of MTE Relay:**
- Securely relay HTTP requests to your server
- Protect sensitive headers and data with MTE encryption
- Stream large files efficiently without loading them into memory

## Quick Links

📚 **[Official Getting Started Guide](https://public-docs.eclypses.com/docs/mte-relay-server/client-libraries/iOS)** - Concise guide for experienced developers

🚀 **[Quick-Start Guide (in this repo)](quick-start/iOS.md)** - Fast setup for experienced developers

💡 This README provides comprehensive reference documentation with detailed examples suitable for developers at all experience levels. If you're already familiar with Swift async/await and MTE concepts, the official docs above offer a faster quick-start path.

## The whole integration, at a glance

Everything below is expanded on later; this is the shape of it, so you know what
you are working towards. Three changes, and your request-building and
response-handling code is untouched.

```swift
// 1. Add the package — product `Relay`, from 5.2.0.       → Installation
import Relay

// 2. Create one Relay. It validates the licence; pairing
//    happens on its own with the first request.           → Setup
let relay = try await Relay()

// 3. Point the request at your relay server instead of the
//    origin, and swap the one call.                       → Usage
//    Before:  let (data, response) = try await URLSession.shared.data(for: request)
let (data, response) = try await relay.dataTask(with: request)
```

`dataTask` returns the same `(Data, URLResponse)` `URLSession` would have, with
the origin's status code and body, so your existing decoding and error handling
carry over unchanged.

**You do not need any delegates for this.** The library defines four delegate
protocols, but they exist for streaming uploads, downloads and SSE. A `dataTask`
integration requires none of them — see
[Which Delegates Do I Need?](#summary-which-delegates-do-i-need) if you later add
file transfer or event streams.

Two things worth knowing before you start: **`Relay()` is `async throws`**, so
whatever constructs it becomes async too — that ripple is usually the largest
part of the change — and **your app must be code-signed**, because Relay keeps a
small host record in the keychain.

## Prerequisites

- **iOS 16.0 or later** - Required by the package platform target
- **Swift 5.7 or later** - Needed for modern async/await support used throughout the API
- **Xcode 14.0 or later** - For iOS 16 and Swift 5.7 toolchain compatibility
- **MTE core 4.2.1** (via `mte-client-ios`) - Provided automatically as a Swift Package dependency; no separate download is required. SPM resolves it when you add `Relay`
- **Access to a licensed MTE Relay server instance** - This client library communicates with an MTE Relay server that handles the encryption/decryption. You need its URL. The MTE license is embedded in this package — there is no key, credential or configuration file for you to supply
- **A code-signed app** - Relay stores a small host record (the relay's URL and your client id) in the keychain, so the app must be code-signed. Ad-hoc signing is enough and **no entitlements file is required** — in Xcode this is the default, but a generated or CI project that disables signing will fail at pairing with a keychain error. Pair state itself is *not* persisted

## Installation

### Swift Package Manager (Recommended)

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the package URL: `https://github.com/Eclypses/mte-relay-client-ios.git`
3. Choose **Up to Next Major Version**, starting from `5.2.0`
4. Click **Add Package**
5. Add the **`Relay`** library product to your app target
6. Click **Add Package** again to confirm

#### Declaring it in a manifest instead

The steps above are for Xcode's UI. If your project is generated (XcodeGen,
Tuist, CI) or you are adding Relay to a Swift package, declare it directly:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Eclypses/mte-relay-client-ios.git", from: "5.2.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "Relay", package: "mte-relay-client-ios")
        ]
    )
]
```

```yaml
# XcodeGen project.yml
packages:
  mte-relay-client-ios:
    url: https://github.com/Eclypses/mte-relay-client-ios.git
    from: "5.2.0"
targets:
  YourApp:
    dependencies:
      - package: mte-relay-client-ios
        product: Relay
```

The package *identity* is `mte-relay-client-ios`, taken from the URL; the library
product you depend on is `Relay`. They differ, and both are required.

**Common SPM Issues:**
- **"Package resolution failed"** - Make sure you have a stable internet connection and GitHub is accessible
- **"Failed to clone repository"** - Verify you have access to the repository (some versions may be private)
- **Build errors after adding package** - Try **Product > Clean Build Folder** (Cmd+Shift+K) and rebuild

## Setup

### Step 1: Configure Your MTE Relay Server

**Important:**
Before using this client library, ensure your MTE Relay server is set up and configured to receive encrypted requests from your iOS app. The server handles the decryption and forwards requests to your actual backend API.

The MTE Relay server acts as a secure intermediary — it receives encrypted requests from your iOS app, decrypts them, and forwards them to your backend API endpoint.

### Step 2: Import the Module

In any Swift file where you'll use Relay, add the import statement:

```swift
import Relay
```

### Step 3: Create a Relay Instance

The `Relay` class is your main interface to the library. Here's a complete example of setting it up in a typical iOS app:

```swift
import Foundation
import Relay

final class YourNetworkManager {
    /// The relay server your requests are addressed to.
    ///
    /// Note this is *not* passed to `Relay()`. Relay works out which host to pair
    /// with from the URL of each `URLRequest` you hand it, so the relay server URL
    /// belongs in the requests you build — nowhere else.
    private let relayServerUrl = URL(string: "https://your-relay-server.com")!

    private var relay: Relay?

    /// `Relay()` is `async throws`, so create it on first use rather than in an
    /// initializer. See "Where to create it" below — this choice is the difference
    /// between changing one file and changing several.
    private func relayInstance() async throws -> Relay {
        if let relay { return relay }
        // Validates the MTE license. Pairing happens automatically on the first request.
        let relay = try await Relay()
        self.relay = relay
        return relay
    }

    func login(email: String, password: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: relayServerUrl.appendingPathComponent("api/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        return try await relayInstance().dataTask(with: request)
    }
}
```

**Where to create it.** `Relay()` is `async throws`, and where you call it decides
how far that ripples:

- **On first use, as above.** The `async` is absorbed by a function that was
  already `async`, so callers and views are untouched. Recommended.
- **In an initializer.** Your initializer becomes `async throws` too, and so does
  every place that constructs it — in SwiftUI that usually means holding the
  object as optional `@State`, building it in `.task`, and handling the window
  where it does not exist yet. That is a larger change for no benefit unless you
  genuinely need the Relay to exist before the first request.

Reuse one `Relay` rather than creating one per request: it holds the pairs
established with each host, and discarding it discards them.


## Usage

All API methods are `async throws`. Use `try await` at every call site, and wrap in a `do/catch` block to handle errors.

### Making Secure HTTP Requests

Once you've set up your `Relay` instance, use it to make secure requests. The library automatically encrypts your data, sends it through the MTE Relay server, and decrypts the response.

**Important:** When creating your `URLRequest`, use your **MTE Relay server URL** (not your actual backend API URL). The MTE Relay server will decrypt your request and forward it to your actual backend.

#### Basic Example — GET Request

```swift
import Foundation

var request = URLRequest(url: URL(string: "https://your-relay-server.com/api/users/123")!)
request.httpMethod = "GET"
request.addValue("application/json", forHTTPHeaderField: "Accept")
request.addValue("Bearer abc123", forHTTPHeaderField: "Authorization")

// List headers whose values should be encrypted in transit.
// "Content-Type", if present, is always encrypted. Headers not listed here
// are sent unencrypted.
let headersToEncrypt = ["Authorization"]

do {
    let (data, response) = try await relay.dataTask(
        with: request,
        headersToEncrypt: headersToEncrypt,
        pathnamePrefix: nil
    )

    if let httpResponse = response as? HTTPURLResponse {
        print("Status code: \(httpResponse.statusCode)")
        guard (200...299).contains(httpResponse.statusCode) else { return }
    }

    let json = try JSONSerialization.jsonObject(with: data)
    print("Response: \(json)")
} catch {
    print("Request failed: \(error.localizedDescription)")
}
```

#### POST Request with JSON Body

```swift
var request = URLRequest(url: URL(string: "https://your-relay-server.com/users")!)
request.httpMethod = "POST"
request.addValue("application/json", forHTTPHeaderField: "Content-Type")
request.addValue("Bearer abc123", forHTTPHeaderField: "Authorization")

let userData = ["name": "John Doe", "email": "john@example.com"]
request.httpBody = try? JSONSerialization.data(withJSONObject: userData)

do {
    let (data, response) = try await relay.dataTask(
        with: request,
        headersToEncrypt: ["Authorization"],
        pathnamePrefix: nil
    )
    if let httpResponse = response as? HTTPURLResponse {
        print("Created user, status: \(httpResponse.statusCode)")
    }
} catch {
    print("Error: \(error.localizedDescription)")
}
```

**Parameter Details:**

- **`with`** (`URLRequest`) - Your standard URLRequest configured with URL, method, headers, and body
- **`headersToEncrypt`** (`[String]?`) - Header names to encrypt, matched case-insensitively. `Content-Type` is always encrypted whether or not you list it; any header you do not list is sent unencrypted. Passing `nil` or `[]` therefore encrypts `Content-Type` only
- **`pathnamePrefix`** (`String?`) - Optional path prefix for relay routing, usually `nil`
- **Returns** - `(Data, URLResponse)` on success
- **Throws** - `RelayClientError` on failure

### File Upload (Streaming)

For uploading files, especially large ones, use the streaming upload API. File bytes are sourced from `relayStreamDelegate` and encrypted chunk-by-chunk — the file is never loaded entirely into memory.

**When to use streaming vs regular requests:**
- **Use streaming** for files larger than a few MB, video uploads, or when you want progress tracking
- **Use regular `dataTask`** for small payloads (JSON, small images under 1–2 MB)

**Requirements:**
- Set `relay.relayStreamDelegate` before calling `uploadFileStream`
- The `URLRequest` must include a positive `Content-Length` header matching the exact total unencrypted byte count

#### Streaming Upload Example

```swift
import Foundation
import Relay

class FileUploadManager: RelayStreamDelegate,
                         RelayStreamResponseDelegate,
                         RelayStreamCompletionDelegate {

    var relay: Relay!
    private var writer: RelayMultipartWriter?

    init(relay: Relay) {
        self.relay = relay
        relay.relayStreamDelegate = self
        relay.relayStreamResponseDelegate = self
        relay.relayStreamCompletionDelegate = self
    }

    func uploadStreamedFile(at fileURL: URL) async throws {
        // Only needed if your endpoint expects multipart/form-data. The relay
        // imposes no body format — write whatever your endpoint accepts.
        let writer = try RelayMultipartWriter(fileURL: fileURL)
        self.writer = writer

        var request = URLRequest(url: URL(string: "https://your-relay-server.com/upload")!)
        request.httpMethod = "POST"
        request.setValue(writer.contentType, forHTTPHeaderField: "Content-Type")
        // Must be the exact total unencrypted byte count, framing included.
        // The writer computes it so the two cannot disagree.
        request.setValue(String(writer.contentLength), forHTTPHeaderField: "Content-Length")

        let (_, _) = try await relay.uploadFileStream(request: request)
    }

    // MARK: - RelayStreamDelegate

    // Called by the Relay to request bytes. Write the complete request body to
    // outputStream; the Relay chunks and encrypts it as you write.
    func getRequestBodyStream(outputStream: OutputStream) {
        try? writer?.write(to: outputStream)
    }

    // MARK: - RelayStreamCompletionDelegate

    func streamCompletionPercentage(from relayServerUrl: String,
                                    bytesCompleted: Double,
                                    totalBytes: Double) {
        let percentage = (bytesCompleted / totalBytes) * 100
        DispatchQueue.main.async {
            // Update progress bar, label, etc.
        }
    }

    // MARK: - RelayStreamResponseDelegate

    func relayStreamResponse(from relayServerUrl: String,
                              data: Data?,
                              response: URLResponse?,
                              error: Error?) {
        if let error = error {
            print("Upload failed: \(error.localizedDescription)")
            return
        }
        if let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) {
            print("Upload successful")
        }
    }
}
```

`RelayMultipartWriter` is **optional**, and shipped only because the framing and
the `Content-Length` have to agree and computing them separately is the usual way
this goes wrong. If your endpoint wants some other body format, build that
instead and write it to the same stream — the relay does not care what the bytes
are.

### File Download (Streaming)

Download large files efficiently using the async streaming download API. Decrypted bytes are written to disk incrementally — the full file is never held in memory.

**Important:**
- `downloadFile(with:to:headersToEncrypt:pathnamePrefix:timeout:)` is async/throws.
- The library creates and writes the destination file; pre-create the parent directory but you do not need to pre-create the file itself.
- Progress callbacks are available via `RelayStreamCompletionDelegate`.

#### Streaming Download Example

```swift
import Foundation
import Relay

class FileDownloadManager: RelayStreamCompletionDelegate {

    var relay: Relay!

    init(relay: Relay) {
        self.relay = relay
        relay.relayStreamCompletionDelegate = self
    }

    func downloadFile(from endpoint: String, saveTo localURL: URL) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"

        _ = try await relay.downloadFile(
            with: request,
            to: localURL,
            headersToEncrypt: [],
            pathnamePrefix: nil,
            timeout: 60
        )
        print("Download complete: \(localURL.path)")
    }

    // MARK: - RelayStreamCompletionDelegate

    func streamCompletionPercentage(from relayServerUrl: String,
                                    bytesCompleted: Double,
                                    totalBytes: Double) {
        let percentage = (bytesCompleted / totalBytes) * 100
        DispatchQueue.main.async {
            // Update progress indicator
        }
    }
}

// Usage:
Task {
    do {
        let downloadManager = FileDownloadManager(relay: myRelay)
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let saveURL = documentsDir.appendingPathComponent("video.mp4")

        // Ensure the parent directory exists.
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await downloadManager.downloadFile(
            from: "https://your-relay-server.com/api/files/video.mp4",
            saveTo: saveURL
        )
    } catch {
        print("Download failed: \(error)")
    }
}
```

### Server-Sent Events (SSE)

Open a relay-backed SSE stream and receive decrypted events through the `RelayServerSentEventDelegate` protocol. Multiple SSE streams can be active concurrently against the same relay host; each stream is identified by its `streamId: UUID`.

#### SSE Example

```swift
import Relay

class SSEManager: RelayServerSentEventDelegate {

    var relay: Relay!
    private var activeStreamId: UUID?

    init(relay: Relay) {
        self.relay = relay
        relay.relayServerSentEventDelegate = self
    }

    func openStream(endpoint: String) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"

        let result = try await relay.openServerSentEventStream(
            with: request,
            headersToEncrypt: ["Authorization"],
            pathnamePrefix: nil,
            timeout: 30
        )
        activeStreamId = result.streamId
        print("SSE stream opened: \(result.streamId)")
    }

    func closeStream() async throws {
        guard let streamId = activeStreamId else { return }
        try await relay.cancelServerSentEventStream(
            relayServerUrlString: "https://your-relay-server.com",
            streamId: streamId
        )
        activeStreamId = nil
    }

    // MARK: - RelayServerSentEventDelegate

    func relayServerSentEventDidReceiveResponse(from relayServerUrl: String,
                                                streamId: UUID,
                                                response: URLResponse) {
        print("SSE stream \(streamId) opened")
    }

    func relayServerSentEventDidReceiveData(from relayServerUrl: String,
                                            streamId: UUID,
                                            data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            print("SSE event on stream \(streamId): \(text)")
        }
    }

    func relayServerSentEventDidComplete(from relayServerUrl: String,
                                         streamId: UUID,
                                         response: URLResponse?) {
        print("SSE stream \(streamId) completed")
        activeStreamId = nil
    }
}
```

### Re-Pairing with the Server

When your app first connects to the MTE Relay server, it establishes MTE pairs automatically. Sometimes you need to re-establish these pairs, for example after a server restart or when you detect persistent encryption failures.

**When to re-pair:**
- After receiving `RelayClientError.decodingFailed` that persists after an automatic retry
- If you implement a periodic re-pairing schedule for your security policy
- After server deployment or restart that clears relay state

```swift
do {
    try await relay.rePairwithRelayServer(
        relayServerUrlString: "https://your-relay-server.com",
        pathnamePrefix: nil
    )
    print("Re-pairing successful")
} catch {
    print("Re-pairing failed: \(error.localizedDescription)")
}
```

### Adjusting Relay Settings

Customize per-host relay behavior using `RelayHostSettings`. Call `adjustRelaySettings` with a `RelayHostSettings` value; if any setting has changed, the library triggers an automatic re-pair.

#### Settings Reference

| Setting | Default | Valid Range | Description |
|---------|---------|-------------|-------------|
| `streamChunkSize` | 1 MB | 4 KB – 10 MB | Bytes per streaming chunk |
| `minPairs` | 5 | > 0 | Pool repairs to `basePairs` when available count drops below this value |
| `basePairs` | 8 | ≥ `minPairs` | Target pool size after a repair |
| `maxPairs` | 15 | ≥ `basePairs` | Hard upper limit on concurrent pairs |
| `keepAliveInterval` | 300 s | 60 – 600 s | Relay keep-alive ping cadence |
| `acquisitionWaitTime` | 1.0 s | ≥ 0 | How long to wait for a free pair when the pool is saturated |

**Note:** `persistPairs` was removed in V5. Pair state is no longer persisted to the keychain.

#### Settings Example

```swift
do {
    try await relay.adjustRelaySettings(
        serverUrl: "https://your-relay-server.com",
        pathnamePrefix: nil,
        settings: RelayHostSettings(
            streamChunkSize: 2_097_152,   // 2 MB chunks
            minPairs: 5,
            basePairs: 8,
            maxPairs: 15,
            keepAliveInterval: 300,
            acquisitionWaitTime: 1.0
        )
    )
    print("Settings updated and re-paired successfully")
} catch {
    print("Failed to adjust settings: \(error.localizedDescription)")
}
```

**Lower-memory / lower-bandwidth configuration:**
```swift
try await relay.adjustRelaySettings(
    serverUrl: "https://your-relay-server.com",
    settings: RelayHostSettings(
        streamChunkSize: 524_288,   // 512 KB chunks
        minPairs: 3,
        basePairs: 5,
        maxPairs: 8
    )
)
```

**Read current settings for a host:**
```swift
let currentSettings = try await relay.relaySettings(serverUrl: "https://your-relay-server.com")
print("Chunk size: \(currentSettings.streamChunkSize)")
```

### Logging

#### Enabling File Logging

```swift
// Enable logging (typically in AppDelegate or app initialization).
// Off by default.
Relay.enableFileLogging(true)
```

#### Reading and Clearing Logs

```swift
do {
    if let logContents = try Relay.readLogFile() {
        print(logContents)
    }
} catch {
    print("Error reading log: \(error.localizedDescription)")
}

Relay.clearLogFile()
```

#### Log Levels

```
INFO    - Normal operations (pairing started, request sent, etc.)
WARNING - Potential issues (retry attempts, unsupported usage)
ERROR   - Failures (pairing failed, decryption error, network timeout)
FAULT   - Critical errors (licensing failure, fatal configuration error)
[TRACE] - Detailed diagnostic steps (pair IDs, state fingerprints); enabled by default
```

**Common log entries:**
```
"Using iOS Relay Version 5.2.0 and MTE Version 4.2.1"  → Relay initialized
"License Check failed"                                  → Invalid or expired MTE license
"RelayStreamResponse Error: ..."                        → File streaming failed
```

---

## Delegates Reference

The MTE Relay library uses delegates for streaming-specific callbacks. Non-streaming requests and control operations are async/throws and do not require delegates.

### RelayStreamDelegate (Required for file uploads)

```swift
public protocol RelayStreamDelegate: AnyObject {
    func getRequestBodyStream(outputStream: OutputStream)
}
```

Called during `uploadFileStream` to ask your app to write request body bytes into `outputStream`. You must write all bytes and close the stream when done.

---

### RelayStreamResponseDelegate (Optional for streaming operations)

```swift
public protocol RelayStreamResponseDelegate: AnyObject {
    func relayStreamResponse(from relayServerUrl: String,
                             data: Data?,
                             response: URLResponse?,
                             error: Error?)
}
```

Delivers the final response from a streaming upload operation.

---

### RelayStreamCompletionDelegate (Optional, for progress tracking)

```swift
public protocol RelayStreamCompletionDelegate: AnyObject {
    func streamCompletionPercentage(from relayServerUrl: String,
                                    bytesCompleted: Double,
                                    totalBytes: Double)
}
```

Called periodically during upload or download to report progress.

---

### RelayServerSentEventDelegate (Required for SSE)

```swift
public protocol RelayServerSentEventDelegate: AnyObject {
    func relayServerSentEventDidReceiveResponse(from relayServerUrl: String,
                                                streamId: UUID,
                                                response: URLResponse)
    func relayServerSentEventDidReceiveData(from relayServerUrl: String,
                                            streamId: UUID,
                                            data: Data)
    func relayServerSentEventDidComplete(from relayServerUrl: String,
                                          streamId: UUID,
                                          response: URLResponse?)
}
```

All three methods include `streamId` so your app can route interleaved callbacks for concurrent streams. The protocol provides default no-op implementations for all three methods.

---

### Summary: Which Delegates Do I Need?

| Operation | Required Delegates | Optional Delegates |
|-----------|-------------------|--------------------|
| Basic requests (`dataTask`) | None | None |
| File download (`downloadFile`) | None | `RelayStreamCompletionDelegate` |
| Chunked upload (`uploadFileStream`) | `RelayStreamDelegate` | `RelayStreamCompletionDelegate`, `RelayStreamResponseDelegate` |
| SSE (`openServerSentEventStream`) | `RelayServerSentEventDelegate` | None |
| Re-pairing / adjust settings | None | None |

---

## Troubleshooting

### Pairing Issues

**Problem: "License Check failed" error**

Solutions:
The MTE license is embedded in this package; there is nothing to configure in
your app, and your bundle identifier is not tied to it. If this check fails the
package itself is at fault, not your setup.

1. Confirm you are on a released version of the package rather than a local or
   modified copy
2. Contact [info@eclypses.com](mailto:info@eclypses.com)

---

**Problem: Pairing fails repeatedly**

Solutions:
1. Check relay server is running and reachable
2. Verify server URL has no trailing slash and uses the correct protocol (https)
3. Check network connectivity (firewall, VPN)
4. Try explicit re-pair:
   ```swift
   try await relay.rePairwithRelayServer(relayServerUrlString: serverUrl)
   ```

---

**Problem: Requests fail with `decodingFailed` / token mismatch after server restart**

The relay automatically detects `mte_status_token_does_not_exist` decode errors and performs a single transparent re-pair-and-retry. If a request still fails, catch `RelayClientError.decodingFailed` and call `rePairwithRelayServer` manually.

---

**Problem: `pairCapacityExhausted` error**

All `maxPairs` pairs are checked out and none became available within `acquisitionWaitTime`. Increase `maxPairs` or `acquisitionWaitTime` in `RelayHostSettings`, or reduce concurrency on the app side.

---

### Network & Connection Issues

**Problem: Requests fail with timeout errors**

Solutions:
1. Increase timeout in URLRequest: `request.timeoutInterval = 60`
2. For large files, reduce `streamChunkSize`:
   ```swift
   try await relay.adjustRelaySettings(
       serverUrl: serverUrl,
       settings: RelayHostSettings(streamChunkSize: 524_288)
   )
   ```

---

**Problem: "Unable to retrieve Relay Server URL from request"**

Ensure your URLRequest has a valid, properly formatted URL with no spaces.

---

### Streaming Issues

**Problem: File uploads fail or freeze**

Solutions:
1. Verify the file exists and is readable
2. Ensure `relay.relayStreamDelegate` is set
3. Ensure `getRequestBodyStream` closes the output stream when done
4. Verify `Content-Length` header is set and matches the exact total multipart byte count

---

**Problem: Downloads fail with 500 error**

Solutions:
1. Don't encrypt headers that don't exist in the request:
   ```swift
   // Wrong: encrypting Content-Type on a GET request (no body, no Content-Type)
   let headersToEncrypt = ["Content-Type"]  // fails

   // Correct: only encrypt headers you actually set
   let headersToEncrypt: [String] = []      // or ["Authorization"]
   ```
2. Ensure the destination directory exists before calling `downloadFile`

---

**Problem: Downloads produce corrupted files**

1. Ensure the destination directory exists:
   ```swift
   try FileManager.default.createDirectory(
       at: localURL.deletingLastPathComponent(),
       withIntermediateDirectories: true
   )
   ```
2. Check disk space
3. Verify response status code is 200–299

---

### Memory & Performance Issues

**Problem: High memory usage during file operations**

1. Use streaming APIs for all large files — never `dataTask` for multi-MB transfers
2. Reduce `streamChunkSize`:
   ```swift
   try await relay.adjustRelaySettings(
       serverUrl: serverUrl,
       settings: RelayHostSettings(streamChunkSize: 524_288)
   )
   ```

---

**Problem: Slow performance**

1. Increase `streamChunkSize` (up to 10 MB) for better throughput
2. Increase `maxPairs` for more concurrent request capacity
3. Check network conditions

---

### Debugging Tips

1. **Enable file logging:**
   ```swift
   Relay.enableFileLogging(true)
   ```

2. **Use network debugging tools** — Charles Proxy or Proxyman to inspect traffic

3. **Test with a simple request first:**
   ```swift
   var request = URLRequest(url: URL(string: "https://your-relay-server.com/ping")!)
   let (data, response) = try await relay.dataTask(with: request)
   print("Ping: \(response), bytes=\(data.count)")
   ```

4. **Check MTE version:**
   ```swift
   print("MTE Version: \(MteBase.getVersion())")
   ```

---

## API Reference

### `RelayClientError` — Typed Error Surface

All async `Relay` methods throw `RelayClientError`. Catch it to handle specific failure modes:

```swift
do {
    let (data, response) = try await relay.dataTask(with: request)
} catch RelayClientError.decodingFailed {
    try await relay.rePairwithRelayServer(relayServerUrlString: serverUrl)
} catch RelayClientError.pairingFailed(let reason) {
    print("Pairing failed: \(reason)")
} catch RelayClientError.pairCapacityExhausted(let max) {
    print("All \(max) pairs are saturated — reduce concurrency or raise maxPairs")
} catch RelayClientError.operationTimedOut(let seconds) {
    print("Request timed out after \(seconds)s")
} catch {
    print("Unexpected error: \(error)")
}
```

| Case | Meaning |
|------|---------|
| `licenseCheckFailed` | MTE license is invalid or expired |
| `invalidServerURL` | Server URL could not be parsed |
| `invalidRequestURL` | Request URL is missing or malformed |
| `invalidURLComponents` | Request URL components could not be constructed |
| `hostResolutionFailed` | Could not resolve or create a relay host for the request |
| `requestPreparationFailed` | Frame or request could not be encoded (e.g. missing Content-Length) |
| `pairCapacityExhausted(Int)` | All pairs are in-use and none freed within `acquisitionWaitTime`; value is `maxPairs` |
| `encodingFailed` | MTE encode step failed |
| `decodingFailed` | MTE decode step failed (auto-repair already attempted) |
| `networkFailure` | Underlying URLSession error |
| `invalidRelayResponse` | Relay response was missing required metadata |
| `fileWriteFailed(String)` | Downloaded file could not be written to the given path |
| `operationCancelled` | Operation was explicitly cancelled |
| `operationTimedOut(TimeInterval)` | Operation exceeded the provided timeout |
| `pairingFailed(String)` | Pairing handshake failed with given reason |
| `statePersistenceFailed(String)` | MTE state could not be persisted |
| `pairReplaced(Int)` | Per-pair repair succeeded after the given relay status code; caller may retry |
| `pairReplaceFailed(Int)` | Per-pair repair failed after the given relay status code |
| `fullRepairSuccess(Int)` | Full repair succeeded after the given relay status code; caller may retry |
| `fullRepairCatastrophic(Int)` | Full repair failed after the given relay status code |
| `relayStatus(Int, String?)` | Relay returned an unhandled status code |
| `serverSentEventsSetupFailed(String)` | SSE setup failed before the stream could start |
| `serverSentEventsAlreadyActive` | Legacy SSE exclusivity error retained in the public surface |
| `serverSentEventsMalformedStream` | SSE stream format was invalid |
| `serverSentEventsBufferLimitExceeded` | SSE buffering exceeded the internal pending-buffer limit |
| `logReadFailed` | Log file could not be read |
| `underlying(String)` | Wraps an unrecognized underlying error |

---

### Relay Class Methods

#### `init(httpClient: RelayHTTPClient = URLSessionRelayHTTPClient()) async throws`
Initializes the Relay instance.
- Validates the MTE license on construction. Throws `RelayClientError.licenseCheckFailed` if invalid.
- `httpClient` is injectable for testing or custom transport (e.g. certificate pinning).
- **Usage:** `let relay = try await Relay()`

---

#### `dataTask(with:headersToEncrypt:pathnamePrefix:preventStreaming:) async throws -> (Data, URLResponse)`
Makes an encrypted HTTP request. Every parameter except `with` has a default, so
`relay.dataTask(with: request)` is a complete call — which is why the examples
above pass only the request.

```swift
func dataTask(with origRequest: URLRequest,
              headersToEncrypt: [String]? = nil,
              pathnamePrefix: String? = nil,
              preventStreaming: Bool = false) async throws -> (Data, URLResponse)
```

- **Parameters:**
  - `with`: URLRequest to send (URL scheme+host+port is used to locate the relay host)
  - `headersToEncrypt`: Header names to encrypt, matched case-insensitively. `Content-Type` is always encrypted; `nil` or `[]` encrypts `Content-Type` only
  - `pathnamePrefix`: Optional path prefix for relay routing
  - `preventStreaming`: Forces the response to be delivered as one buffered reply instead of being streamed. Leave it `false` unless a server sends a `text/event-stream` response you want buffered
- **Returns:** `(Data, URLResponse)`
- **Throws:** `RelayClientError`

---

#### `uploadFileStream(request:headersToEncrypt:pathnamePrefix:) async throws -> (Data, URLResponse)`
Uploads a file using chunked MKE streaming. Bytes are never loaded entirely into memory.
- **Requires:** `relayStreamDelegate` must be set; `Content-Length` header must be a positive integer matching the total unencrypted body size
- **`headersToEncrypt`:** reserved on this path and currently ignored — pass `nil`. All request metadata is MTE-encoded regardless, so listing headers here has no effect
- **Progress:** Reported via `relayStreamCompletionDelegate`
- **Returns:** `(Data, URLResponse)` — decoded server response

---

#### `downloadFile(with:to:headersToEncrypt:pathnamePrefix:timeout:) async throws -> URLResponse`
Downloads and decrypts a file, writing it to `destinationURL` incrementally.
- **Parameters:**
  - `with`: URLRequest configured for download
  - `to`: Local destination `URL`
  - `headersToEncrypt`: Header names to encrypt (optional)
  - `pathnamePrefix`: Path prefix for relay routing (optional)
  - `timeout`: Optional timeout in seconds; non-positive values throw `operationTimedOut` immediately
- **Returns:** `URLResponse`
- **Throws:** `RelayClientError`

---

#### `openServerSentEventStream(with:headersToEncrypt:pathnamePrefix:timeout:) async throws -> RelayServerSentEventOpenResult`
Opens a relay-backed SSE stream.
- **Requires:** `relayServerSentEventDelegate` must be set to receive callbacks
- **Returns:** `RelayServerSentEventOpenResult` — contains `streamId: UUID` and `response: URLResponse`
- Multiple SSE streams may be active concurrently against the same relay host

---

#### `cancelServerSentEventStream(relayServerUrlString:streamId:pathnamePrefix:) async throws`
Cancels one active SSE stream for the given relay origin.
- No-ops if the host is not instantiated or the `streamId` is unknown

---

#### `rePairwithRelayServer(relayServerUrlString:pathnamePrefix:) async throws`
Forces a full MTE re-pairing with the relay server. In normal operation this is automatic; call explicitly when you need to reset the session on demand.

---

#### `cancelStreamingOperations(relayServerUrlString:pathnamePrefix:) async throws`
Cancels all in-progress streaming upload and download operations for the given relay origin. No-ops if no operations are in progress.

---

#### `relaySettings(serverUrl:pathnamePrefix:) async throws -> RelayHostSettings`
Returns the current per-host settings for the given relay origin.

---

#### `adjustRelaySettings(serverUrl:settings:) async throws`
#### `adjustRelaySettings(serverUrl:pathnamePrefix:settings:) async throws`
Updates host-scoped relay configuration. Triggers an automatic re-pair if any setting has changed.
- **Parameters:**
  - `serverUrl`: URL of your relay server
  - `pathnamePrefix`: Path prefix (optional)
  - `settings`: `RelayHostSettings` with the desired configuration
- **Validation:** `keepAliveInterval` 60–600 s; `streamChunkSize` 4 KB–10 MB; pool ordering `minPairs ≤ basePairs ≤ maxPairs`

---

#### Static Methods

##### `enableFileLogging(_ enabled: Bool)`
Enables or disables file logging (default: off).

##### `readLogFile() throws -> String?`
Returns the log file contents, or `nil` if no log file exists.
- **Throws:** `RelayClientError.logReadFailed`

##### `clearLogFile()`
Deletes the log file.

---

### Delegate Properties

```swift
var relayStreamDelegate: RelayStreamDelegate?                        // strong — required for upload
weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
weak var relayServerSentEventDelegate: RelayServerSentEventDelegate?
```

`relayStreamDelegate` is a **strong** reference to keep the delegate alive during streaming. The others are `weak`.

---

### Key Classes and Protocols

- **`Relay`** — Main entry point for all secure network operations
- **`RelayClientError`** — Typed `Error` enum thrown by all async `Relay` methods
- **`RelayHostSettings`** — Per-host configuration struct passed to `adjustRelaySettings`
- **`RelayHTTPClient`** — Injectable async transport protocol; default is `URLSessionRelayHTTPClient`
- **`RelayStreamDelegate`** — Protocol for providing body bytes during chunked upload
- **`RelayStreamResponseDelegate`** — Protocol for receiving streaming operation results
- **`RelayStreamCompletionDelegate`** — Protocol for receiving progress updates
- **`RelayServerSentEventDelegate`** — Protocol for relay-backed SSE lifecycle callbacks
- **`RelayServerSentEventOpenResult`** — SSE open result: `streamId` and `response`

---

## Migration from V4

If you are upgrading from V4 (any 4.x release), the following breaking changes require code updates.

### Minimum platform requirements

| | V4 | V5 |
|--|--|--|
| Minimum iOS | 14.0 | **16.0** |
| Minimum Swift | 5.5 | **5.7** |

### `dataTask` — callback → async/throws

```swift
// V4 — callback closure
await relay.dataTask(with: request, headersToEncrypt: headers, pathnamePrefix: prefix) { data, response, error in
    // handle result
}

// V5 — async/throws
let (data, response) = try await relay.dataTask(with: request,
                                                headersToEncrypt: headers,
                                                pathnamePrefix: prefix)
```

Remove any conformance to `RelayResponseDelegate` — the `relayResponse(success:responseStr:errorMessage:)` protocol is gone.

### `downloadFile` — renamed and now async

```swift
// V4 — synchronous throws
try relay.downloadFileStream(request: request,
                             downloadUrl: destinationURL,
                             headersToEncrypt: headers,
                             pathnamePrefix: prefix)

// V5 — async/throws; parameter labels changed
let response = try await relay.downloadFile(with: request,
                                            to: destinationURL,
                                            headersToEncrypt: headers,
                                            pathnamePrefix: prefix,
                                            timeout: 60)
```

### `uploadFileStream` — now async/throws

```swift
// V4 — synchronous throws (result delivered via RelayStreamResponseDelegate only)
try relay.uploadFileStream(request: request,
                           headersToEncrypt: headers,
                           pathnamePrefix: prefix)

// V5 — async/throws; result returned directly
let (data, response) = try await relay.uploadFileStream(request: request,
                                                        headersToEncrypt: headers,
                                                        pathnamePrefix: prefix)
```

### `adjustRelaySettings` — individual params → `RelayHostSettings` struct

```swift
// V4 — individual parameters (removed in V5)
try await relay.adjustRelaySettings(serverUrl: url,
                                    pathnamePrefix: prefix,
                                    newStreamChunkSize: 1_048_576,
                                    newPairPoolSize: 5,
                                    persistPairs: false)

// V5 — RelayHostSettings struct
try await relay.adjustRelaySettings(
    serverUrl: url,
    pathnamePrefix: prefix,
    settings: RelayHostSettings(
        streamChunkSize: 1_048_576,
        minPairs: 5,
        basePairs: 8,
        maxPairs: 15,
        keepAliveInterval: 300,
        acquisitionWaitTime: 1.0
    )
)
```

Note: `persistPairs` has been **removed** — pair state is no longer persisted to the keychain.

### `rePairwithRelayServer` — argument label added

```swift
// V4 — positional first argument
try await relay.rePairwithRelayServer("https://your-relay-server.com", pathnamePrefix: prefix)

// V5 — named argument required
try await relay.rePairwithRelayServer(relayServerUrlString: "https://your-relay-server.com",
                                      pathnamePrefix: prefix)
```

### New error cases

V5 adds several new `RelayClientError` cases used by the dynamic pair pool and repair paths. Update any exhaustive `switch` statements over `RelayClientError` to handle: `pairCapacityExhausted(Int)`, `pairReplaced(Int)`, `pairReplaceFailed(Int)`, `fullRepairSuccess(Int)`, `fullRepairCatastrophic(Int)`, `relayStatus(Int, String?)`.

---

## Support
**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)  
**Developer Portal:** [developers.eclypses.com/dashboard](https://developers.eclypses.com/dashboard)

---

## Source Layout (for contributors)

The `Classes/Relay/` directory keeps the public interface clearly separated from implementation:

```
Classes/Relay/
├── API/                        # Primary public entry points
│   ├── Relay.swift             # Main entry point (Relay class)
│   ├── RelayClientError.swift  # Typed error surface
│   └── RelaySseParser.swift    # Opt-in text/event-stream line parser
├── Internal/                   # Implementation detail — not part of the public API
│   ├── Models/                 # Internal data models (APIResult, StoredPair, etc.)
│   ├── Enums.swift
│   ├── Extensions.swift
│   ├── GeneralHelpers.swift
│   ├── HeaderHelper.swift
│   ├── HostStorageHelper.swift
│   ├── KeychainHelper.swift
│   ├── LogHelper.swift
│   ├── MteHelper.swift
│   ├── PairingHelper.swift
│   ├── PairPool.swift
│   └── RelayHeaderCodec.swift
├── Pairing/
│   └── Pair.swift              # MTE encoder/decoder pair lifecycle
├── Storage/
│   ├── RelayHostSettings.swift # Public per-host settings struct
│   └── Settings.swift          # Internal global configuration
├── Streaming/
│   ├── FileStreamDownload.swift
│   ├── FileStreamUpload.swift
│   ├── RelayServerSentEventOpenResult.swift   # Public SSE open result
│   ├── RelayServerSentEventStream.swift
│   └── Delegates/              # Public and internal stream callback protocols
└── Transport/
    ├── Host.swift
    ├── HostPairingCoordinator.swift
    ├── HostRepairCoordinator.swift
    ├── HostSession.swift
    ├── HostSessionRegistry.swift
    ├── RelayHTTPClient.swift   # Public protocol + default implementation
    ├── RelayRequestBuilder.swift
    ├── RelayResponseDecoder.swift
    ├── ReservedPairFinalizer.swift
    ├── ServerSentEventPairFinalizer.swift
    └── StreamingRelayStatusHandler.swift
```

**Rule of thumb:** `Relay.swift`, `RelayClientError.swift`, `RelayHostSettings.swift`, the public delegate/result types under `Streaming/`, and `RelayHTTPClient.swift` are the supported public API surface.

---
**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
