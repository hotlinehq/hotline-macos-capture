import CaptureCore
import Foundation
import Network

/// Checks every 2 seconds that Hotline's socket file still answers, so that calls of
/// listed apps go out as usual when Hotline has died without switching
/// capture off. macOS wants the answer "capture or not" at once, so the
/// extension cannot wait for Hotline when a call starts: it uses the result
/// of the last check instead.
final class HotlineWatch {
    private static let interval = DispatchTimeInterval.seconds(2)
    private static let timeout = DispatchTimeInterval.seconds(1)

    private let path: CapturePath
    private let queue = DispatchQueue(label: "io.github.petercipov.hotlinecapture.watch")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var up = true

    init(path: CapturePath) {
        self.path = path
    }

    /// Whether Hotline answered the last check.
    var answers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return up
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + HotlineWatch.interval, repeating: HotlineWatch.interval)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Opens a connection to Hotline and closes it at once, sending nothing.
    /// Everything here runs on the watch's own queue, one step at a time.
    private func check() {
        let connection = TransparentProxyProvider.connection(to: path)
        var finished = false
        let finish = { [weak self] (answered: Bool) in
            guard !finished else { return }
            finished = true
            connection.cancel()
            self?.record(answered)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .waiting, .failed:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + HotlineWatch.timeout) { finish(false) }
    }

    private func record(_ answered: Bool) {
        lock.lock()
        let changed = up != answered
        up = answered
        lock.unlock()
        guard changed else { return }
        if answered {
            log.info("Hotline answers again: capturing")
        } else {
            log.info("Hotline does not answer: not capturing until it does")
        }
    }
}
