import Darwin
import Foundation
import Logging

final class SignalHandler {
    private let lock = NSLock()
    private var didHandle = false
    private let logger: Logger
    private var sources: [DispatchSourceSignal] = []

    init(signals: [Int32], logger: Logger, handler: @escaping () -> Void) {
        self.logger = logger
        for signalValue in signals {
            signal(signalValue, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalValue, queue: DispatchQueue.global())
            source.setEventHandler { [weak self] in
                guard let self else {
                    return
                }
                self.lock.lock()
                if self.didHandle {
                    self.lock.unlock()
                    return
                }
                self.didHandle = true
                self.lock.unlock()

                self.logger.info("received signal \(signalValue), cleaning up")
                handler()
                let exitCode = Int32(128) + signalValue
                exit(exitCode)
            }
            source.resume()
            sources.append(source)
        }
    }
}
