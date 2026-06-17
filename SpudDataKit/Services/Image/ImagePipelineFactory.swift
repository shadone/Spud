//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import OSLog

private let logger = Logger.imageService

/// Builds the Nuke `ImagePipeline` that backs `ImageService`: a custom-User-Agent
/// data loader, a per-process disk cache, and a memory cache that evicts under
/// pressure. One pipeline per process (no shared App-Group cache).
enum ImagePipelineFactory {
    /// Session config matching the old `ImageService` session: a plain
    /// `Spud/<version>` User-Agent so instances whose nginx denylists the default
    /// `CFNetwork/...` token still serve images. See `AppUserAgent`.
    static func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = AppUserAgent.value
        configuration.httpAdditionalHeaders = headers
        return configuration
    }

    /// Logs the status and the headers that reveal who rejected an image request
    /// (Cloudflare edge vs Lemmy vs pict-rs). The response body snippet the old
    /// `logFailedResponse` printed is intentionally dropped: Nuke's data loader
    /// validates the response before the body is buffered, and keeping the body
    /// would require a bespoke `URLSessionDataDelegate` loader that also defeats
    /// the incremental delivery Phase 2's progressive decode relies on.
    static func logUnacceptableResponse(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              !(200...299).contains(http.statusCode)
        else { return }
        func header(_ name: String) -> String {
            (http.value(forHTTPHeaderField: name)) ?? "-"
        }
        logger.error(
            """
            Image load failed status=\(http.statusCode, privacy: .public) \
            url=\(http.url?.absoluteString ?? "-", privacy: .public)
            server=\(header("Server"), privacy: .public) \
            cf-ray=\(header("CF-Ray"), privacy: .public) \
            cf-mitigated=\(header("cf-mitigated"), privacy: .public) \
            content-type=\(header("Content-Type"), privacy: .public) \
            retry-after=\(header("Retry-After"), privacy: .public)
            """
        )
    }

    static func makePipeline(cacheName: String) -> ImagePipeline {
        let dataLoader = DataLoader(
            configuration: makeURLSessionConfiguration(),
            validate: { response in
                if let error = DataLoader.validate(response: response) {
                    logUnacceptableResponse(response)
                    return error
                }
                return nil
            }
        )

        // Per-process disk cache. If the cache dir can't be created, run without
        // a disk cache rather than crashing image loading.
        let dataCache = try? DataCache(name: cacheName)
        dataCache?.sizeLimit = 200 * 1024 * 1024

        return ImagePipeline { config in
            config.dataLoader = dataLoader
            config.dataCache = dataCache
            // Store both the processed (downsampled) thumbnail and the original,
            // so a warm relaunch reads the small thumbnail straight off disk.
            config.dataCachePolicy = .storeAll
            // Native decompression on the decode thread (replaces the old manual
            // `byPreparingForDisplay()`), keeping scroll hitch-free.
            config.isUsingPrepareForDisplay = true
        }
    }
}
