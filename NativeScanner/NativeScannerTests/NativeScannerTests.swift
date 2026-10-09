import XCTest
@testable import NativeScanner

final class NativeScannerTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(ContentView() as ContentView?)
    }
}
