<center>
<img src="Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
MteRelay Mobile Client  
Swift Package</div>

![Latest Release](https://img.shields.io/github/v/release/Eclypses/eclypses-aws-mte-relay-client-ios?style=flat-square)

## Introduction
This Swift Package provides the Eclypses MteRelay Mobile Client for iOS. It enables secure, encrypted HTTP(S) communication between your iOS app and your backend via an MteRelay server. You must have licensed access to an MteRelay server instance. [More Info](https://eclypses.com/mte-technology/amazon-web-services-aws/)

**Purpose of MteRelay:**
- Securely relay HTTP requests to your server
- Protect sensitive headers and data with MTE encryption
- Stream large files efficiently

## Prerequisites
- iOS 14.0 or later
- Swift 5.5 or later
- Access to a licensed MteRelay server instance

## Installation

### Swift Package Manager (Recommended)
1. In Xcode, go to **File > Add Packages...**
2. Enter the package URL: `https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git`
3. Follow the prompts to add the package to your project.

### CocoaPods
Add the following to your `Podfile`:
```ruby
pod 'MteRelay', :git => 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git'
```

## Setup
1. Set up and configure your MteRelay server API to receive and decode requests from your application.
2. In your iOS app, import the MteRelay module:

```swift
import MteRelay
```

3. Create a `Relay` instance and set its delegate:

```swift
class YourClass: RelayResponseDelegate {
    var relay: Relay!

    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        // Handle relay callback responses and errors
    }

    init() async throws {
        try await instantiateMteRelay()
    }

    func instantiateMteRelay() async throws {
        relay = try await Relay()
        relay.relayResponseDelegate = self
    }
}
```

## Usage

### Routing Requests through MteRelay
For any request you want to secure, update your code to use the `Relay` instance:

```swift
await relay.dataTask(with: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix) { (data, response, error) in
    if let error = error {
        // Handle the error
    }
    guard let data = data else {
        // Handle the lack of data
    }
    // Use the response and data as needed
}
```
- `headersToEncrypt`: `[String]?` – List of header keys to encrypt (optional)
- `pathnamePrefix`: `String?` – Optional path prefix for the relay server

### Streamed File Upload
```swift
try relay.uploadFileStream(request: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
```

### Streamed File Download
```swift
await relay.download(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
```

### RePair with Server
```swift
try await relay.rePairwithRelayServer(your_relay_server_url, pathnamePrefix: pathnamePrefix)
```

### Adjust Relay Settings
```swift
try await relay.adjustRelaySettings(serverUrl: Settings.actualServerPath, pathnamePrefix: Settings.pathnamePrefix, newStreamChunkSize: 1048576, newPairPoolSize: 3, persistPairs: false)
```

### Logging
```swift
Relay.enableFileLogging(true) // Enable file logging (default: false)

let logContents = try Relay.readLogFile()
Relay.clearLogFile()
```

## API Reference
See the source code and inline documentation for full API details. Key classes:
- `Relay`: Main entry point for secure requests and file streaming
- `RelayResponseDelegate`: Protocol for receiving responses and errors
- `Settings`: Configuration for server URL, chunk size, etc.

## Support
**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)  
**Developer Portal:** [developers.eclypses.com/dashboard](https://developers.eclypses.com/dashboard)

---
**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
