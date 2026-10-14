import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One bounded transfer owns its ephemeral session. Delegate callbacks are serialized
/// by the session, while the lock protects cancellation from Swift task executors.
final class BoundedTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var response: URLResponse?
    private var buffer = Data()
    private var cancelled = false
    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }
    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in start(request, configuration: configuration, continuation: continuation) }
        }, onCancel: { self.cancel() })
    }
    private func start(_ request: URLRequest, configuration: URLSessionConfiguration, continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.lock()
        guard !cancelled else { lock.unlock(); continuation.resume(throwing: URLError(.cancelled)); return }
        self.continuation = continuation
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        self.session = session; self.task = task
        lock.unlock(); task.resume()
    }
    private func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(URLError(.cancelled)))
    }
    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        let continuation = self.continuation; self.continuation = nil
        let session = self.session; self.session = nil; task = nil
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
        continuation?.resume(with: result)
        session?.invalidateAndCancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard response is HTTPURLResponse, response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel); finish(.failure(NetworkFailure.invalidResponse)); return
        }
        lock.lock(); self.response = response; let active = continuation != nil; lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard data.count <= maximumBytes - buffer.count else {
            lock.unlock(); finish(.failure(NetworkFailure.invalidResponse)); return
        }
        buffer.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let response = self.response; let data = buffer; lock.unlock()
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((data, response))) }
        else { finish(.failure(NetworkFailure.invalidResponse)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
