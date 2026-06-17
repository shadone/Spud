import XCTest
@testable import SpudDataKit

final class ImagePipelineFactoryTests: XCTestCase {
    func test_urlSessionConfiguration_carriesAppUserAgent() {
        let config = ImagePipelineFactory.makeURLSessionConfiguration()
        let ua = config.httpAdditionalHeaders?["User-Agent"] as? String
        XCTAssertEqual(ua, AppUserAgent.value)
    }
}
