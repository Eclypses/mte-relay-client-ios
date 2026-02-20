# Testing Summary

## Scope
This package now has a baseline deterministic XCTest architecture focused on unit-testable relay components.

## Test Architecture Layers
1. **Infrastructure fakes/stubs**
   - `RecordingRelayResponseDelegate`
   - `RecordingRelayStreamDelegate`
   - `RecordingRelayStreamCompletionDelegate`
   - `RecordingStreamDelegateTarget`
   - `RelayCallbackBridge`

   Supported fake capabilities:
   - failure toggles
   - call counters
   - argument capture
   - ordered call history
   - event simulation
   - reset/dispose lifecycle helpers

2. **Centralized fixtures**
   - endpoints/routes
   - header/metadata fixtures
   - empty/small/large text payloads
   - empty/small/large binary payloads
   - error fixtures

3. **Model/error behavior tests**
   - Codable round-trip checks for pairing/header/internal models
   - encode/decode result behavior checks

4. **Protocol/contract tests**
   - response and stream completion delegate contracts
   - stream delegate proxy forwarding contract

5. **Bridge/callback boundary tests**
   - delegate callback forwarding and ordering via `RelayCallbackBridge`
   - deterministic async callback emission via structured concurrency (`Task.yield()` loop)

6. **Throughput/edge scenarios**
   - rapid loops (500 iterations)
   - burst callback simulation (50 events)
   - mixed text/binary payload processing
   - empty and large payload coverage

## Test Files
- `Tests/MteRelayTests/ModelAndFixtureTests.swift`
- `Tests/MteRelayTests/HeaderExtensionsAndThroughputTests.swift`
- `Tests/MteRelayTests/DelegateContractAndBridgeTests.swift`
- `Tests/MteRelayTests/StreamDelegateProxyTests.swift`
- `Tests/MteRelayTests/Support/TestFixtures.swift`
- `Tests/MteRelayTests/Support/TestFakes.swift`

## Coverage Workflow
Coverage is generated from iOS simulator test execution (xcodebuild + xccov) because this package links an iOS xcframework binary.

### Generate coverage
```bash
IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.5' bash scripts/generate_coverage.sh
```

### Verify default threshold (40%)
```bash
MIN_LINE_COVERAGE=0.40 bash scripts/verify_coverage.sh
```

### Verify override threshold (example: 45%)
```bash
MIN_LINE_COVERAGE=0.45 bash scripts/verify_coverage.sh
```

## Coverage Outputs
- `artifacts/coverage/MteRelayTests.xcresult`
- `artifacts/coverage/coverage-summary.txt`
- `artifacts/coverage/coverage-summary.json`

Note: `artifacts/coverage/` is git-ignored because these files are generated per run.

## Threshold Behavior
- Default threshold: `MIN_LINE_COVERAGE=0.40`
- Override via environment variable
- Gate currently evaluates deterministic unit-testable source scope:
  - `Classes/MteRelay/Models/`
  - `Classes/MteRelay/Delegates/StreamDelegateProxy.swift`
  - `Classes/MteRelay/Helpers/Extensions.swift`
  - `Classes/MteRelay/Helpers/RelayHeaderCodec.swift`

## CI Branch Behavior
Pipeline behavior in `azure-pipelines.yml`:
- Always run:
  - toolchain preflight checks
  - lint/format checks (if configured)
  - targeted deterministic suites
  - full unit suite
- `develop` only:
  - coverage generation
  - coverage threshold verification
- `master`:
  - coverage intentionally skipped
  - existing publish-to-public-remote flow retained

## Latest Validation Results
- Targeted suites: **19 passed, 0 failed**
- Full unit suite: **19 passed, 0 failed**
- Coverage verification:
  - `MIN_LINE_COVERAGE=0.40` → **passed**
  - `MIN_LINE_COVERAGE=0.45` → **passed**
