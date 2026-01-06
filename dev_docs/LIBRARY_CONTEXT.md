# MteRelay Client - iOS Library Context

## 1. Project Overview
This project (`mte-relay-client-ios`) is a Swift package that provides a secure HTTP relay client using **MTE (MicroToken Exchange)** technology. It enables iOS applications to transparently route HTTP(S) requests through an MteRelay server, protecting sensitive data and headers with end-to-end encryption.

**Primary Goal:** To provide a secure, drop-in replacement for standard HTTP(S) networking that automatically handles MTE pairing, encryption, and decryption, ensuring data is protected in transit.

## 2. Intended Use
This library is designed for iOS developers who want to secure their app's network traffic with minimal code changes.

*   **Supported Stack:** URLSession (native iOS networking).
*   **Core Features:**
    *   Transparent MTE pairing and key management.
    *   Automatic encryption of request bodies and selected headers.
    *   Automatic decryption of responses.
    *   Secure, efficient streaming for large file uploads/downloads.
    *   Delegate-based async callbacks for integration with app logic.

## 3. Core Architecture
The library uses a **Relay** abstraction and helper classes to inject security into the standard HTTP lifecycle.

### A. `Relay` (Main Entry Point)
*   **Role**: The primary interface for the app.
*   **Responsibility**:
    *   Initializes MTE licensing and settings.
    *   Manages Host objects for each relay server.
    *   Provides methods for secure data tasks, file uploads, and downloads.
    *   Handles delegate callbacks for responses and streaming events.

### B. `Host`
*   **Role**: Manages pairing and state for a specific relay server.
*   **Responsibility**:
    *   Handles MTE pairing and state persistence.
    *   Prepares and encrypts requests, decrypts responses.
    *   Manages file streaming operations.

### C. `Pair`, `PairingHelper`, `MteHelper`
*   **Role**: Manage MTE key pairs, pairing protocol, and encode/decode operations.
*   **Responsibility**:
    *   Pair: Represents a cryptographic pairing with the server.
    *   PairingHelper: Orchestrates initial and re-pairing.
    *   MteHelper: Handles MTE encode/decode and state management.

### D. Delegates
*   **Role**: Protocols for async callbacks (RelayResponseDelegate, RelayStreamDelegate, etc.).
*   **Responsibility**:
    *   Notify the app of request/response completion, streaming progress, and errors.

### E. File Streaming
*   **Classes**: `FileStreamUpload`, `FileStreamDownload`
*   **Responsibility**:
    *   Efficient, secure upload/download of large files via streams.
    *   Integrate with Relay and Host for encryption and progress reporting.

## 4. Data Flow

### HTTP Request/Response Sequence
1. **App Call**: App calls `Relay.dataTask(with:headersToEncrypt:...)` or similar.
2. **Pairing**: Relay/Host ensures MTE pairing is established (auto-pair/re-pair as needed).
3. **Request Preparation**: Host encrypts selected headers and body, sets relay headers.
4. **Transmission**: Encrypted request is sent to the MteRelay server.
5. **Server Relay**: MteRelay server decodes, forwards to destination, encodes response.
6. **Response Handling**: Host decrypts response, passes to app via delegate/callback.

### File Streaming
1. **App Call**: App calls `Relay.uploadFileStream(...)` or `Relay.downloadFileStream(...)`.
2. **Streaming**: File is streamed in encrypted chunks, with progress reported via delegates.
3. **Completion**: Success/failure and file location are reported to the app.

## 5. Key File Structure
*   **`Relay.swift`**: Main entry point, manages requests, delegates, and settings.
*   **`Host.swift`**: Handles pairing, request/response encryption, and file streaming.
*   **`Pair.swift`**: Represents a cryptographic pair.
*   **`Helpers/`**: PairingHelper, MteHelper, KeychainHelper, HostStorageHelper, etc.
*   **`Models/`**: APIResult, EncodeResult, DecodeResult, PairingRequest/Response, etc.
*   **`FileStreamUpload.swift` / `FileStreamDownload.swift`**: Streaming file transfer logic.
*   **`Settings.swift`**: Library configuration (server URLs, chunk sizes, etc.).
*   **`Mte/`**: Native MTE C library and xcframework.

## 6. Configuration
Configuration is minimal and handled during initialization:
*   **`Settings.swift`**: License keys, server URLs, chunk sizes, and pool sizes.
*   **`Relay`**: Accepts server URL and options; delegates must be set for callbacks.

---
This document provides a concise technical context for the iOS MteRelay client library. For API usage, see the README.md.
