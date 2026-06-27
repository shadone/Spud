import Testing
@testable import SpudDataKit

struct ImagePipelineFactoryTests {
    @Test
    func urlSessionConfiguration_carriesAppUserAgent() {
        let config = ImagePipelineFactory.makeURLSessionConfiguration()
        let ua = config.httpAdditionalHeaders?["User-Agent"] as? String
        #expect(ua == AppUserAgent.value)
    }
}
