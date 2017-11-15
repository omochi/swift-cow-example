import XCTest
@testable import swift_cow_example

class swift_cow_exampleTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(swift_cow_example().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
