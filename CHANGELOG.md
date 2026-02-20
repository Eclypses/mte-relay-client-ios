# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added deterministic XCTest suite with layered fixtures/fakes, protocol contract coverage, callback boundary coverage, and throughput edge scenarios.
- Added `scripts/generate_coverage.sh` to generate coverage artifacts and reports under `artifacts/coverage/`.
- Added `scripts/verify_coverage.sh` with configurable `MIN_LINE_COVERAGE` threshold enforcement.
- Added `dev_docs/TESTING.md` with test architecture, reusable patterns, commands, coverage behavior, and CI branch rules.

### Changed
- Updated `azure-pipelines.yml` indentation/structure and hardened CI execution with YAML linting, dynamic iOS simulator selection, PR trigger handling, and develop-only coverage verification.
- Extracted relay header codec helpers into `Classes/MteRelay/Helpers/RelayHeaderCodec.swift` for cleaner testability without runtime behavior changes.
- Updated `Package.swift` to include explicit macOS platform metadata for local toolchain compatibility and added SPM test target wiring.
- Updated `release.sh` with stricter release preflight checks (develop-only, clean tree, origin freshness) plus local/remote tag collision guards.
- Updated library context docs with concise testing architecture/tooling notes.

### Fixed
- Fixed local/CI coverage workflow for iOS-binary-linked package by using xcodebuild simulator test execution plus xccov reporting.


## [4.4.10] - 2026-01-14

### Added
-

### Changed
- Updated README to be comprehensive implementation guide.

### Fixed
-


## [4.4.9] - 2026-01-07

### Added
-

### Changed
-

### Fixed
- Changed release.sh to provide correct guidance to tag and push release.sh commit to remote.


## [4.4.8] - 2026-01-07

### Added
- Added dev_docs directory with library context and release steps
- Added release.sh script to automate version bumping and changelog rotation

### Changed
- Changed azure-pipelines.yml to remove dev_docs directory and release.sh upon push to public GitHub
    
### Fixed
- 


## [4.4.7] - 2025-11-01

### Added
- Copied code from eclypses-aws-mte-relay-client-ios

### Changed
- Something wrong with tag 4.4.6. Bumped version to 4.4.7
### Fixed
- Client can be utilized as a Swift Package or a CocoaPod now.


## [4.4.6] - 2025-11-01

### Added
    - Copied code from eclypses-aws-mte-relay-client-ios

### Changed
    - Put files in commonly-used structure, i.e. Classes, etc
    - Edited podspec and package.swift to conform to new stucture 
### Fixed
    - Client can be utilized as a Swift Package or a CocoaPod now.


## [4.4.3] - 2025-10-28

### Added

### Changed
    - Updated MteRelay.podspec to produce a single MteRelay module
### Fixed


## [4.4.2] - 2025-09-04

### Added

### Changed
    - Updated MteRelay.podspec to produce multiple modules
### Fixed


## [4.4.1] - 2025-09-03

### Added

### Changed
    - Updated MteRelay.podspec to remove commented code
### Fixed


## [4.4.0] - 2025-09-03

### Added
- MteRelay.podspec

### Changed

### Fixed


## [4.3.4] - 2025-05-12

### Added

### Changed
- Downgraded iOS Target to v14.

### Fixed


## [4.3.3] - 2025-05-12

### Added
- Check for Trial Version with warning

### Changed
- Set default pairPoolSize to 5.

### Fixed
- Fixed null exception where we tried to remove non-existant storedHost.
- Removed debug comments
-  


## [4.3.2] - 2025-05-01

### Added


### Changed


### Fixed
- Fixed issue where we were prematurely discarding extra pairs before we were finishedd with them. 


## [4.3.1] - 2025-05-01

### Added
- Improved thread safety in FileStream operations.
- Added logging Apple Unified Logging functionality with public static functions to toggle Relay.writeLogToFile, Relay.readFile, and Relay.clearFile.
- Added Relay Version to Settings

### Changed


### Fixed
- Out-of-sequence errors in FileStream operations


## [4.3.0] - 2025-04-29

### Added
- Improved thread safety in FileStream operations.
- Added logging Apple Unified Logging functionality with public static functions to toggle Relay.writeLogToFile, Relay.readFile, and Relay.clearFile.
- Added Relay Version to Settings

### Changed


### Fixed
- Out-of-sequence errors in FileStream operations


## [4.2.0] - 2025-04-02

### Added
- `downloadFileStream` now provides progress data via `fileStreamCompletionDelegate` when a `Content-Length` header is found in the response.

### Changed
- The `setSettings` functions are now private, replaced with new public `adjustRelaySettings` functions for modifying relay settings.
- The `getRequestBodyStream` delegate no longer returns an `Int` (`bytesReadFromApp`).
- The `rePairWithRelayServer` function now returns response data via `RelayResponseDelegate`.

### Fixed
- Ensured `pathnamePrefix` is fully functional across all applicable requests.



[4.2.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.2.0
[4.3.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.0
[4.3.1]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.1
[4.3.2]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.2
[4.3.3]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.3
[4.3.4]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.4
[4.4.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.0
[4.4.1]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.1
[4.4.2]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.2
[4.4.3]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.3
[4.4.6]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.6
[4.4.7]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.7


[4.4.8]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/v4.4.8

[4.4.9]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/v4.4.9

[4.4.10]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/v4.4.10
