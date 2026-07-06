import Foundation

// URLSession lives in FoundationNetworking on non-Apple platforms (Linux).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// Cross-platform `data(for:)`. Apple Foundation has the async method; Linux
    /// swift-corelibs-foundation (≤ 5.10) does not, so wrap the classic
    /// completion-handler `dataTask` in a continuation there. Behaviour matches
    /// the native async call (returns `(Data, URLResponse)` or throws).
    func seData(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
        #else
        return try await self.data(for: request)
        #endif
    }
}
