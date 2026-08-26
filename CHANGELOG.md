# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
-

### Changed
-

### Fixed
-


## [5.2.1] - 2026-08-26

### Fixed
- The keychain hint for `errSecMissingEntitlement` led with "missing the Keychain
  Sharing entitlement". Ad-hoc code signing is the actual fix and no entitlements
  file is required, so the message sent developers to add an entitlement they do
  not need. It now leads with the unsigned-build cause and keeps the entitlement
  as the fallback for an app that is already signed.

### Added
-

### Changed
-

### Fixed
-


## [5.2.0] - 2026-08-26

### Added
- `RelayMultipartWriter` — an **opt-in** `multipart/form-data` body writer for
  streamed uploads. `uploadFileStream` hands your delegate an `OutputStream` and
  encrypts whatever you write to it; the body format is yours to choose, and the
  relay imposes none. This exists for callers uploading to an endpoint that wants
  multipart and who don't already have a writer. It owns the boundary, framing
  and `contentLength` together, because `uploadFileStream` requires a
  `Content-Length` matching the total unencrypted body — framing included — and
  computing that separately from the framing is the usual way it goes wrong. The
  file is read in chunks and never held in memory in full.

### Changed
- Keychain failures now report their `OSStatus` and land on the documented
  `RelayClientError.statePersistenceFailed` instead of a generic string error.
  Previously `KeychainError` had no `LocalizedError` conformance, so
  `localizedDescription` rendered as `(Relay.KeychainError error 0.)` — the case
  index, with the status the enum was already carrying discarded. The three
  statuses worth explaining are now spelled out: a missing entitlement or unsigned
  build, a locked device, and a cancelled request.

### Removed
- The V4 keychain migration path. V4 and V5 are wire-incompatible and are not run
  against each other, so a V5 client never encounters a V4 record.
  `LegacyStoredHost`, `migrateLegacyStoredHostIfNeeded`, the `StoredPair` model
  and the already-dead `MteHelper.getPairDictionaryStates()` are all gone. No
  public API is affected.

## [5.1.0] - 2026-08-11

> Backfilled from commit history.

### Changed
- **Module and public types renamed (breaking).** SPM package/product/target
  `MteRelay` -> `Relay`; consumers change `import MteRelay` to `import Relay` and
  the product reference from `MteRelay` to `Relay`. The package *identity* is
  URL-derived and unchanged, so `.product(package: "mte-relay-client-ios")` stays
  as-is. Public type names are unaffected.


## [5.0.1] - 2026-08-05

> Backfilled from commit history.

### Fixed
- `Package.swift` resolved `mte-client-ios` through a local-sibling path, which
  only worked on a machine with the sibling checked out. It now resolves by URL,
  so the package is consumable from a clean clone.
- The clean-orphan publish step is re-runnable rather than failing on a second
  attempt.

### Note
- `autoRetryAfterDecodeFailure` never shipped. It was added to
  `RelayHostSettings` during 5.0.0 development and retired on 2026-07-16, before
  5.0.0 was released on 2026-07-28 — it is present in no tagged version. The
  5.0.0 entry above previously listed it under Added; those lines have been
  removed so the entry describes what actually shipped. Code written against a
  pre-release 5.0.0 snapshot may reference it; drop the setting, and treat a
  token-mismatch decode failure on upload/download as a retryable error the app
  re-issues.


## [5.0.0] - 2026-07-28

### Added
- Added `RelayClientError.pairCapacityExhausted(Int)` — thrown when all pairs are checked out and no pair becomes available within `acquisitionWaitTime`; the associated value is `maxPairs`.
- Added `RelayClientError.pairReplaced(Int)`, `pairReplaceFailed(Int)`, `fullRepairSuccess(Int)`, `fullRepairCatastrophic(Int)` — typed recovery-result cases surfaced from per-pair and full-repair paths; associated value is the relay HTTP status code that triggered the repair.
- Added `RelayClientError.relayStatus(Int, String?)` — surfaces unhandled relay server status codes with an optional message.
- Added `openServerSentEventStream(with:headersToEncrypt:pathnamePrefix:timeout:) async throws -> RelayServerSentEventOpenResult` to `Relay` — opens a relay-backed SSE stream; multiple streams may be active concurrently per host.
- Added `cancelServerSentEventStream(relayServerUrlString:streamId:pathnamePrefix:) async throws` — cancels one active SSE stream by `streamId`; no-ops if the stream is unknown.
- Added `cancelStreamingOperations(relayServerUrlString:pathnamePrefix:) async throws` — cancels all active upload/download streaming operations for a relay origin.
- Added `relaySettings(serverUrl:pathnamePrefix:) async throws -> RelayHostSettings` — retrieves the current per-host settings.
- Added `RelayServerSentEventDelegate` protocol with `relayServerSentEventDidReceiveResponse`, `relayServerSentEventDidReceiveData`, and `relayServerSentEventDidComplete` callbacks, all keyed by `streamId: UUID`. Default no-op extension provided.
- Added `RelayServerSentEventOpenResult` struct (`streamId: UUID`, `response: URLResponse`) — return value from `openServerSentEventStream`.
- Added `RelayHostSettings` struct — per-host configuration value type replacing individual settings parameters. Fields: `streamChunkSize`, `minPairs`, `basePairs`, `maxPairs`, `keepAliveInterval`, `acquisitionWaitTime`.
- Added `RelayHostSettingsStore` actor — manages per-host `RelayHostSettings` instances internally.
- Added `keepAliveInterval` to `RelayHostSettings` (default 300 s, range 60–600 s) — controls relay keep-alive ping cadence per host.
- Added `acquisitionWaitTime` to `RelayHostSettings` (default 1.0 s) — maximum time to wait for a free pair when the pool is fully in-use.
- Added `minPairs` and `basePairs` to `RelayHostSettings` (defaults 5 and 8) — dynamic pool lower bounds; pool repairs to `basePairs` when available count drops below `minPairs`.
- Added `maxPairs` to `RelayHostSettings` (default 15) — hard upper limit on the concurrent pair count per host.
- Added typed current error surface `RelayClientError` for non-streaming API and pairing/request error mapping.
- Added `RelayRequestBuilder` to centralize relay request/frame preparation.
- Added `HostSessionRegistry` actor to isolate per-origin host/session resolution.
- Added `RelayResponseDecoder` to centralize non-streaming relay response decode orchestration.
- Added `HostPairingCoordinator` to centralize host pairing setup and restoration orchestration.
- Added `HostRepairCoordinator` to centralize pair-repair retry decision/state logic.
- Added `HostStreamRetryState` to centralize streaming retry task state and progression rules.
- Added `HostSession` to represent explicit per-origin relay session state.
- Added async APIs on `Relay` for simplified app-side streaming download usage.
- Added optional timeout controls to async streaming download and SSE APIs.
- Added explicit cancellation controls for async streaming operations, including relay-level cancel-all by server origin.
- Added `StreamingRelayStatusHandler` for unified relay-status classification across streaming and SSE recovery paths.
- Added `PackageLogger.traceEnabled` flag and `trace(from:message:)` convenience method for opt-in `[TRACE]`-prefixed debug-level log lines.
- Added `Pair.traceStateSnapshot()` returning encoder/decoder state fingerprints for diagnostics without holding the state lock.

### Changed (Breaking)
- **BREAKING:** Minimum iOS deployment target raised from **14.0 to 16.0**.
- **BREAKING:** `dataTask(with:headersToEncrypt:pathnamePrefix:)` now returns `(Data, URLResponse)` via `async throws` — the old completion-handler closure overload is removed.
- **BREAKING:** `uploadFileStream(request:headersToEncrypt:pathnamePrefix:)` is now `async throws -> (Data, URLResponse)` — the old synchronous-throws variant is removed.
- **BREAKING:** `downloadFileStream(request:downloadUrl:headersToEncrypt:pathnamePrefix:)` is **removed** — replace with `downloadFile(with:to:headersToEncrypt:pathnamePrefix:timeout:) async throws -> URLResponse`.
- **BREAKING:** `adjustRelaySettings(serverUrl:pathnamePrefix:newStreamChunkSize:newPairPoolSize:persistPairs:)` is **removed** — replace with `adjustRelaySettings(serverUrl:settings:)` or `adjustRelaySettings(serverUrl:pathnamePrefix:settings:)`.
- **BREAKING:** `RelayResponseDelegate` protocol (`relayResponse(success:responseStr:errorMessage:)`) is **removed** — non-streaming results are delivered via async/throws return values.
- **BREAKING:** `persistPairs` setting is **removed** from `RelayHostSettings` and from all `adjustRelaySettings` overloads — pair state is no longer persisted to the keychain.
- **BREAKING:** `rePairwithRelayServer` first-argument label is now `relayServerUrlString:` — bare positional call sites must add the label.
- Updated `adjustRelaySettings` to validate `keepAliveInterval` (must be 60–600 s) and all `minPairs`/`basePairs`/`maxPairs` ordering constraints.
- Updated `Relay` and `Host` non-streaming flows to remove status-callback coupling and surface failures via async throws.
- Updated relay response-header parsing to throw typed relay errors instead of string errors.
- Refactored `Host` to consume extracted request/frame preparation, response decode, pairing setup, and repair-decision components.
- Refactored `HostSessionRegistry` to store and resolve explicit `HostSession` models with access metadata.
- Updated `FileStreamUpload.processResponse` to delegate to `RelayResponseDecoder` for unified frame/header/body decryption.
- **BREAKING:** MTE core is no longer embedded in this repository — it is now provided by the standalone [`mte-client-ios`](https://github.com/Eclypses/mte-client-ios) Swift package (MTE **4.2.1**), consumed as the `MteClient` product. `Package.swift` resolves it via a dual pattern: the checked-out sibling package during local development, otherwise the published GitHub package (`from: "4.2.1"`); relay is now publicly resolvable via SPM. The MTE core was upgraded from 4.1.0 to 4.2.1 (reduced `MTE_TOKBYTES` from 16 to 8; ECDH key exchange superseded by Kyber).
- Made `MteKyber` size/info query methods `static` — these wrap stateless C functions and do not require an instance.
- Updated host persistence to retain host-scoped client identity only; persisted pair-state restoration has been removed.
- Updated `release.sh` configuration to target current project structure.

### Removed
- Removed CocoaPods support (`MteRelay.podspec`); the package is distributed via Swift Package Manager only. Existing `v4.x` CocoaPods pins are unaffected — they continue to resolve against their original tags.

### Fixed
- Removed unused `RelayResponseDelegate` protocol after decoupling non-streaming status notifications.
- Fixed encoder/decoder state being saved before status check in `Pair` — `saveState()` is now called only after `checkMteStatus()` succeeds, preventing corrupt state from being persisted on encode/decode failure.
- Fixed `RelayResponseDecoder` response-header parsing to decode from raw bytes instead of a UTF-8 string, preventing round-trip corruption on binary-encoded header payloads.
- `Host` now automatically re-pairs and retries once on `mte_status_token_does_not_exist` decode errors instead of surfacing a hard `decodingFailed` error.
- `PairingHelper` now masks `encNonce` and `decNonce` with `0x7FFFFFFFFFFFFFFF` to clamp values to the signed-63-bit range, preventing overflow on server implementations that treat nonces as signed integers.
- `PairingHelper` now resets `Settings.clientId` on 559–569 server responses so the next pairing cycle is treated as a fresh client registration.
- `PairPool.moveToAvailable` now deduplicates before appending, preventing duplicate pair entries in the available pool.
- Fixed streaming download cleanup to release the correct pair ID on early response/parse failures, preventing leaked pair reservations.
- Fixed streaming download response handling to parse relay frame metadata incrementally, decode framed headers before starting body decrypt, and feed only framed body bytes into chunked decrypt/write.
- Fixed manual re-pair to refresh stale relay client sessions by re-verifying the relay before retrying pair creation.
- Fixed download completion to report an invalid relay response instead of crashing if framed metadata or decrypt state was never established.
- Fixed relay SSE cancellation/session cleanup so cancelled streams finalize their reserved pair exactly once and completed sessions are always removed from active SSE bookkeeping.
- Removed an unreachable `catch` branch in `FileStreamDownload` to reduce build warning noise.
- Replaced package-local retroactive conformance (`String: Error`) with a dedicated wrapper error type, removing build warnings.


## [4.6.0] - 2026-03-10

### Added
- Added `preventStreaming` flag (5th field) to `RelayOptions` and the MTE-Relay header codec (`RelayHeaderCodec.swift`). When `true`, signals the relay server to disable streaming and redirect the request for non-standard processing.
- Added `preventStreaming: Bool = false` optional parameter to `Relay.dataTask` (both overloads). Defaults to `false` if omitted; always implicitly `false` for streaming upload/download calls.

### Fixed
- Fixed inverted wire encoding of `preventStreaming` in `RelayHeaderCodec.swift` so `true` serialises as `"1"` and `"1"` parses back as `true`, consistent with all other flag fields and server expectations.


## [4.5.3] - 2026-02-20

### Fixed
- Removed unsupported `@retroactive` attribute usage in `Classes/MteRelay/Helpers/Extensions.swift` to restore compatibility with Azure-hosted Xcode/Swift toolchains.


## [4.5.2] - 2026-02-20

### Fixed
-


## [4.5.1] - 2026-02-20

### Changed
- Updated `azure-pipelines.yml` preflight toolchain detection to resolve Xcode via `xcode-select` first, then fallback to installed `/Applications/Xcode*.app` paths for better Azure agent compatibility.

### Fixed
- Added clearer preflight diagnostics when no valid Xcode toolchain is discovered.


## [4.5.0] - 2026-02-20

### Added
- Added deterministic XCTest suite with layered fixtures/fakes, protocol contract coverage, callback boundary coverage, and throughput edge scenarios.
- Added `scripts/generate_coverage.sh` and `scripts/verify_coverage.sh` with configurable `MIN_LINE_COVERAGE` threshold enforcement.
- Added `dev_docs/TESTING.md` with test architecture, reusable patterns, commands, coverage behavior, and CI branch rules.

### Changed
- Updated `azure-pipelines.yml` indentation/structure and hardened CI execution with YAML linting, dynamic iOS simulator selection, PR trigger handling, and develop-only coverage verification.
- Extracted relay header codec helpers into `RelayHeaderCodec.swift` for cleaner testability.
- Updated `Package.swift` to include explicit macOS platform metadata and added SPM test target wiring.
- Updated `release.sh` with stricter release preflight checks plus local/remote tag collision guards.

### Fixed
- Fixed local/CI coverage workflow for iOS-binary-linked package by using xcodebuild simulator test execution plus xccov reporting.


## [4.4.10] - 2026-01-14

### Changed
- Updated README to be comprehensive implementation guide.


## [4.4.9] - 2026-01-07

### Fixed
- Changed release.sh to provide correct guidance to tag and push release.sh commit to remote.


## [4.4.8] - 2026-01-07

### Added
- Added dev_docs directory with library context and release steps.
- Added release.sh script to automate version bumping and changelog rotation.

### Changed
- Changed azure-pipelines.yml to remove dev_docs directory and release.sh upon push to public GitHub.


## [4.4.7] - 2025-11-01

### Added
- Copied code from eclypses-aws-mte-relay-client-ios.

### Changed
- Something wrong with tag 4.4.6. Bumped version to 4.4.7.

### Fixed
- Client can be utilized as a Swift Package or a CocoaPod now.


## [4.4.6] - 2025-11-01

### Added
- Copied code from eclypses-aws-mte-relay-client-ios.

### Changed
- Put files in commonly-used structure (Classes, etc.).
- Edited podspec and Package.swift to conform to new structure.

### Fixed
- Client can be utilized as a Swift Package or a CocoaPod now.


## [4.4.3] - 2025-10-28

### Changed
- Updated MteRelay.podspec to produce a single MteRelay module.


## [4.4.2] - 2025-09-04

### Changed
- Updated MteRelay.podspec to produce multiple modules.


## [4.4.1] - 2025-09-03

### Changed
- Updated MteRelay.podspec to remove commented code.


## [4.4.0] - 2025-09-03

### Added
- MteRelay.podspec.


## [4.3.4] - 2025-05-12

### Changed
- Downgraded iOS Target to v14.


## [4.3.3] - 2025-05-12

### Added
- Check for Trial Version with warning.

### Changed
- Set default pairPoolSize to 5.

### Fixed
- Fixed null exception where we tried to remove non-existent storedHost.
- Removed debug comments.


## [4.3.2] - 2025-05-01

### Fixed
- Fixed issue where we were prematurely discarding extra pairs before we were finished with them.


## [4.3.1] - 2025-05-01

### Added
- Improved thread safety in FileStream operations.
- Added Apple Unified Logging functionality with public static functions to toggle `Relay.writeLogToFile`, `Relay.readFile`, and `Relay.clearFile`.
- Added Relay Version to Settings.

### Fixed
- Out-of-sequence errors in FileStream operations.


## [4.3.0] - 2025-04-29

### Added
- Improved thread safety in FileStream operations.
- Added Apple Unified Logging functionality.
- Added Relay Version to Settings.

### Fixed
- Out-of-sequence errors in FileStream operations.


## [4.2.0] - 2025-04-02

### Added
- `downloadFileStream` now provides progress data via `fileStreamCompletionDelegate` when a `Content-Length` header is found in the response.

### Changed
- The `setSettings` functions are now private, replaced with new public `adjustRelaySettings` functions for modifying relay settings.
- The `getRequestBodyStream` delegate no longer returns an `Int` (`bytesReadFromApp`).
- The `rePairWithRelayServer` function now returns response data via `RelayResponseDelegate`.

### Fixed
- Ensured `pathnamePrefix` is fully functional across all applicable requests.


[5.0.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v5.0.0
[4.6.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.6.0
[4.5.3]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.5.3
[4.5.2]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.5.2
[4.5.1]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.5.1
[4.5.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.5.0
[4.4.10]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.10
[4.4.9]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.9
[4.4.8]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.8
[4.4.7]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.7
[4.4.6]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.6
[4.4.3]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.3
[4.4.2]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.2
[4.4.1]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.1
[4.4.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.4.0
[4.3.4]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.3.4
[4.3.3]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.3.3
[4.3.2]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.3.2
[4.3.1]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.3.1
[4.3.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.3.0
[4.2.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v4.2.0

[5.2.0]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v5.2.0

[5.2.1]: https://github.com/Eclypses/mte-relay-client-ios/releases/tag/v5.2.1
