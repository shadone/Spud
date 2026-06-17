//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

/// A Nuke `DataLoading` stub that returns canned bytes (or an error) synchronously.
final class StubDataLoader: DataLoading, @unchecked Sendable {
    let result: Result<(Data, URLResponse), Error>
    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        switch result {
        case let .success((data, response)):
            didReceiveData(data, response)
            completion(nil)
        case let .failure(error):
            completion(error)
        }
        return StubCancellable()
    }
}

struct StubCancellable: Nuke.Cancellable { func cancel() { } }

enum ImageFixture {
    /// A 8x8 red PNG, valid for decoding.
    static func pngData() -> Data {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }

    static func httpResponse(_ url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

final class ImageServiceDownsampleTests: XCTestCase {
    private func makeService(loader: DataLoading) -> ImageService {
        let pipeline = ImagePipeline { config in
            config.dataLoader = loader
            config.imageCache = nil
        }
        return ImageService(alertService: AlertService(), pipeline: pipeline)
    }

    func test_downsample_yieldsReadyImage() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.png"))
        let loader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
        let service = makeService(loader: loader)

        var lastImage: UIImage?
        for await state in service.fetch(url, downsampleTo: CGSize(width: 64, height: 64)) {
            if case let .ready(image) = state { lastImage = image }
        }
        XCTAssertNotNil(lastImage)
    }
}
