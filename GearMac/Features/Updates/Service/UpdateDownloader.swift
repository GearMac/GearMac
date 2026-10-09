// 文件职责：下载发布归档，并通过 AsyncThrowingStream 上报进度与完成事件。
// 分层：Service（URLSession 封装）；临时文件落盘与取消时的清理都在此处完成。
import Foundation

/// `URLSession` 只向 delegate 上报字节进度，因此这里保留了一个 delegate。
enum UpdateDownloader {
    /// 下载过程中对外发出的事件。
    enum Event: Sendable {
        case progress(received: Int64, expected: Int64)
        case finished(URL)
    }

    /// 取消消费该流的任务会一并取消传输并销毁对应的 session。
    static func download(
        _ release: AvailableRelease, to destination: URL
    ) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let config = URLSessionConfiguration.ephemeral
            // 不使用缓存，且绝不使用 `URLSession.shared`，使磁盘上的文件是唯一副本。
            config.urlCache = nil
            config.timeoutIntervalForRequest = 60
            let delegate = Delegate(
                destination: destination, expected: release.assetSize, events: continuation)
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            var request = URLRequest(url: release.assetURL)
            request.setValue("GearMac", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                // session 会一直持有 delegate 直到被 invalidate，因此这里正是打破循环引用的关键。
                session.finishTasksAndInvalidate()
            }
            task.resume()
        }
    }
}

/// 所有存储属性都是不可变的且满足 `Sendable`；仅因继承 `NSObject` 才无法由编译器检查。
private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expected: Int64
    private let events: AsyncThrowingStream<UpdateDownloader.Event, any Error>.Continuation

    init(
        destination: URL, expected: Int64,
        events: AsyncThrowingStream<UpdateDownloader.Event, any Error>.Continuation
    ) {
        self.destination = destination
        self.expected = expected
        self.events = events
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        // 服务器若省略 Content-Length 会报告 -1，此时以发布资源的大小作为更可靠的估计。
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        events.yield(.progress(received: totalBytesWritten, expected: total))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            events.finish(throwing: UpdateFailure.downloadFailed("The server answered \(status)."))
            return
        }
        do {
            // 本方法返回时临时文件即被删除，所以移动必须在此处完成。
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            events.yield(.finished(destination))
            events.finish()
        } catch {
            events.finish(throwing: UpdateFailure.downloadFailed(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        events.finish(throwing: UpdateFailure.downloadFailed(error.localizedDescription))
    }
}
