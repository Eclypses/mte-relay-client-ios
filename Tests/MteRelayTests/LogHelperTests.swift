import XCTest
@testable import MteRelay

final class LogHelperTests: XCTestCase {

    // Capture and restore static state so tests are isolated from each other
    // and from any other test class that may toggle these.
    private var savedMinimumLevel: RelayLogLevel = .info
    private var savedLoggingEnabled = false

    override func setUp() {
        super.setUp()
        savedMinimumLevel = PackageLogger.minimumLevel
        savedLoggingEnabled = PackageLogger.loggingEnabled
    }

    override func tearDown() {
        PackageLogger.minimumLevel = savedMinimumLevel
        PackageLogger.loggingEnabled = savedLoggingEnabled
        super.tearDown()
    }

    // MARK: - Level ordering and gating

    func testLevelOrdering() {
        XCTAssertTrue(RelayLogLevel.trace < .debug)
        XCTAssertTrue(RelayLogLevel.debug < .info)
        XCTAssertTrue(RelayLogLevel.info < .warning)
        XCTAssertTrue(RelayLogLevel.warning < .error)
        XCTAssertTrue(RelayLogLevel.error < .fault)
    }

    func testIsEnabledRespectsMinimumLevel() {
        PackageLogger.minimumLevel = .info
        XCTAssertFalse(PackageLogger.isEnabled(.trace))
        XCTAssertFalse(PackageLogger.isEnabled(.debug))
        XCTAssertTrue(PackageLogger.isEnabled(.info))
        XCTAssertTrue(PackageLogger.isEnabled(.error))
        XCTAssertFalse(PackageLogger.isEnabled(.off))
    }

    // MARK: - Lazy message building

    func testDisabledLevelNeverBuildsMessage() {
        PackageLogger.minimumLevel = .warning
        let logger = PackageLogger.makeLogger(for: LogHelperTests.self)

        var built = 0
        func message() -> String { built += 1; return "expensive" }

        logger.trace(message())
        logger.debug(message())
        logger.info(message())

        XCTAssertEqual(built, 0, "messages below the minimum level must not be built")
    }

    func testEnabledLevelBuildsMessage() {
        PackageLogger.minimumLevel = .trace
        let logger = PackageLogger.makeLogger(for: LogHelperTests.self)

        var built = 0
        func message() -> String { built += 1; return "e" }

        logger.error(message())

        XCTAssertEqual(built, 1)
    }

    // MARK: - LoggerWrapper severities

    func testAllSeveritiesCompleteWithoutCrashing() {
        PackageLogger.minimumLevel = .trace
        let logger = PackageLogger.makeLogger(for: LogHelperTests.self)
        logger.trace("t")
        logger.debug("d")
        logger.info("i")
        logger.warning("w")
        logger.error("e")
        logger.fault("f")
    }

    func testEmptyAndWhitespaceMessagesAreSkipped() {
        // write() trims whitespace and skips blank messages.
        let logger = PackageLogger.makeLogger(for: LogHelperTests.self)
        logger.info("")
        logger.info("   ")
        logger.debug("\n")
        logger.error("\t  \n")
        // Reaching here without crashing means the empty-message guard held.
    }

    // MARK: - File logging

    func testLoggingEnabledDefaultIsFalse() {
        XCTAssertFalse(savedLoggingEnabled,
                       "PackageLogger.loggingEnabled should default to false")
    }

    func testLogFileURLIsConstructed() {
        XCTAssertNotNil(PackageLogger.logFileURL)
    }

    func testFileLoggingWritesTheMessageToTheLogFile() throws {
        guard let url = PackageLogger.logFileURL else {
            XCTFail("logFileURL should be available")
            return
        }
        try? FileManager.default.removeItem(at: url) // start from a clean file

        PackageLogger.minimumLevel = .info
        PackageLogger.loggingEnabled = true

        let logger = PackageLogger.makeLogger(for: LogHelperTests.self)
        let marker = "file-logging-marker-\(UUID().uuidString)"
        logger.info(marker)

        let contents = (try? String(contentsOf: url)) ?? ""
        XCTAssertTrue(contents.contains(marker),
                      "the enabled file log should contain the logged message")

        try? FileManager.default.removeItem(at: url) // clean up the shared cache file
    }
}
