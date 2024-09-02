import XCTest
import TelemetryListener

final class TelemetryListenerTests: XCTestCase {
    func testExample() throws {
        // Usage
        let listener = TelemetryListener()
        listener.start()

        // Sleep for 2 minutes (120 seconds) for debugging
        Thread.sleep(forTimeInterval: 120)
    }
}
