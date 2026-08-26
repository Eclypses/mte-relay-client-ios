---
title: MTE Relay Client for iOS using Swift
sidebar_label: iOS
description: An MTE Relay client for iOS applications.
---

![Latest Release](https://img.shields.io/github/v/release/Eclypses/mte-relay-client-ios?style=flat-square)

## Introduction

This Swift Package provides the Eclypses MTE Relay Client for iOS. It enables secure, encrypted HTTP(S) communication between your iOS app and your backend via an MTE Relay server. Requests you already build with `URLRequest` are transparently encrypted with MTE (including Kyber-512 post-quantum key exchange) and relayed to the server, which decrypts them and forwards them to your real backend.

**Purpose of the Relay Client:**

- Securely relay ordinary HTTP requests to your backend
- Protect sensitive headers and bodies with MTE encryption
- Stream large files efficiently without loading them into memory
- Drop-in shaped: build the `URLRequest` you already build, receive `(Data, URLResponse)` as you already do

:::tip Comprehensive Documentation
This guide provides a quick-start for experienced developers. For detailed examples, streaming/upload APIs, troubleshooting, and in-depth explanations, see the **[complete documentation on GitHub](https://github.com/Eclypses/mte-relay-client-ios)**.
:::

## Prerequisites

- iOS 16.0 or later
- Swift 5.7 or later
- Xcode 14.0 or later
- **MTE core 4.2.1** (via `mte-client-ios`) — resolved automatically as a Swift Package dependency; no separate download required
- Access to a licensed MTE Relay server instance (the server URL, not your backend URL, is what you point requests at). The MTE licence is embedded in this package — there is nothing for you to supply
- A code-signed app — Relay keeps a small host record in the keychain. Ad-hoc signing is enough and no entitlements file is needed; a generated or CI project that disables signing fails at pairing

## Installation

### Swift Package Manager (Recommended)

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the package URL: `https://github.com/Eclypses/mte-relay-client-ios.git`
3. Choose the **Up to Next Major Version** rule starting from `5.2.0` and add the **Relay** product to your target.

The `Mte` dependency (from `mte-client-ios`) is resolved transitively — no extra setup.

## Setup

1. Import the module:

```swift
import Relay
```

2. Create a `Relay` instance. `init()` is `async throws`: it validates the MTE license; pairing with the server happens automatically on the first request.

```swift
import Foundation
import Relay

final class YourNetworkManager {
    // Not passed to Relay() — Relay derives the host it pairs with from each
    // URLRequest, so the relay server URL belongs in the requests you build.
    private let relayServerUrl = URL(string: "https://your-relay-server.com")!

    private var relay: Relay?

    // Relay() is async throws, so create it on first use. The async is absorbed
    // by a function that was already async, leaving your views unchanged.
    private func relayInstance() async throws -> Relay {
        if let relay { return relay }
        let relay = try await Relay()
        self.relay = relay
        return relay
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await relayInstance().dataTask(with: request)
    }
}
```

Reuse one `Relay`; it holds the pairs established with each host. Creating it in
an initializer instead makes that initializer `async throws` and pushes the same
requirement onto everything that constructs it — usually an optional `@State`
plus `.task` in SwiftUI. Creating it on first use avoids that entirely.


## Usage

All request methods are `async throws` — use `try await` and a `do/catch`.

> **Important:** point your `URLRequest` at your **MTE Relay server URL**, not your backend API URL. The relay server decrypts the request and forwards it to your actual backend.

### GET Request

```swift
var request = URLRequest(url: URL(string: "https://your-relay-server.com/api/users/123")!)
request.httpMethod = "GET"
request.addValue("application/json", forHTTPHeaderField: "Accept")
request.addValue("Bearer abc123", forHTTPHeaderField: "Authorization")

// Header names whose values should be encrypted in transit. "Content-Type",
// if present, is always encrypted. Headers not listed here are sent as-is.
let headersToEncrypt = ["Authorization"]

do {
    let (data, response) = try await relay.dataTask(
        with: request,
        headersToEncrypt: headersToEncrypt,
        pathnamePrefix: nil
    )

    if let httpResponse = response as? HTTPURLResponse {
        guard (200...299).contains(httpResponse.statusCode) else { return }
    }

    let json = try JSONSerialization.jsonObject(with: data)
    print("Response: \(json)")
} catch {
    print("Request failed: \(error.localizedDescription)")
}
```

### POST Request with JSON Body

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

**`dataTask` parameters:**

- **`with`** (`URLRequest`) — the request you already build (URL, method, headers, body)
- **`headersToEncrypt`** (`[String]?`, defaults to `nil`) — header names to encrypt, matched case-insensitively. `Content-Type` is always encrypted whether or not you list it; `nil`/`[]` encrypts `Content-Type` only
- **`pathnamePrefix`** (`String?`, defaults to `nil`) — set this only if your relay is mounted under a path prefix rather than at the host root; otherwise omit it

### Files & Server-Sent Events

- `relay.uploadFileStream(request:...)` / `relay.downloadFile(with:...)` — stream large files without buffering them in memory
- `RelayMultipartWriter` — optional. If the endpoint you are uploading to expects `multipart/form-data`, this writes the framing into the stream `uploadFileStream` hands your delegate, and gives you the matching `contentType` and `contentLength`. The relay imposes no body format; use this only if your endpoint wants multipart
- `relay.openServerSentEventStream(with:...)` / `relay.cancelServerSentEventStream(...)` — long-lived `text/event-stream` responses
- `relay.rePairwithRelayServer(relayServerUrlString:)` — force a fresh pairing handshake

See the GitHub README for full signatures and streaming examples.

## Error Handling

Request methods throw `RelayClientError` (which conforms to `LocalizedError`, so `error.localizedDescription` is always meaningful). Match specific cases when you need to react:

```swift
do {
    let (data, response) = try await relay.dataTask(with: request,
                                                    headersToEncrypt: ["Authorization"],
                                                    pathnamePrefix: nil)
    // ...
} catch let error as RelayClientError {
    switch error {
    case .licenseCheckFailed:
        print("MTE license invalid")
    case .pairingFailed(let reason):
        print("Pairing failed: \(reason)")
    case .networkFailure:
        print("Network failure — check connectivity / relay server")
    default:
        print("Relay error: \(error.localizedDescription)")
    }
} catch {
    print("Unexpected error: \(error.localizedDescription)")
}
```

## API Reference

See the **[complete documentation on GitHub](https://github.com/Eclypses/mte-relay-client-ios)** for full details. Key types:

- **`Relay`**: main interface
  - `init() async throws` — validate license; pair lazily on first request
  - `dataTask(with:headersToEncrypt:pathnamePrefix:preventStreaming:) async throws -> (Data, URLResponse)` — buffered. Everything except `with` has a default, so `dataTask(with: request)` is a complete call
  - `request(with:headersToEncrypt:pathnamePrefix:) -> AsyncThrowingStream<RelayResponseEvent, Error>` — streamed
  - `uploadFileStream(request:...)` · `downloadFile(with:...)`
  - `openServerSentEventStream(with:...)` · `cancelServerSentEventStream(...)`
  - `rePairwithRelayServer(relayServerUrlString:)`
- **`RelayClientError`**: customer-facing `LocalizedError` (e.g. `licenseCheckFailed`, `pairingFailed`, `networkFailure`, `relayStatus`, `operationCancelled`, …)

## Support

**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)

## Additional Resources

- **[GitHub Repository](https://github.com/Eclypses/mte-relay-client-ios)** – Complete documentation with examples
- **[Release Notes](https://github.com/Eclypses/mte-relay-client-ios/releases)** – Latest updates and changes

---

**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
