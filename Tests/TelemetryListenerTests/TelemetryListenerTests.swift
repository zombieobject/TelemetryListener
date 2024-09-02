import XCTest
import TelemetryListener

final class TelemetryListenerTests: XCTestCase {
    func testExample() throws {
        let listener = TelemetryListener()
        listener.start()
        Thread.sleep(forTimeInterval: 60)
        listener.stop()
    }
}
