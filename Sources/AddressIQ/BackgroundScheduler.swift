import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Schedules deferred telemetry sync via `BGTaskScheduler` (iOS 13+).
///
/// Partners declare the background mode + task identifier in Info.plist:
///   - UIBackgroundModes:    `processing`, `fetch`, `location`
///   - BGTaskSchedulerPermittedIdentifiers: `["com.addressiq.sdk.telemetry-sync"]`
///
/// The SDK then calls `AddressIQBackgroundScheduler.shared.register()` during
/// `AddressIQ.shared.initialize(config:)`. iOS opportunistically wakes the
/// app and calls back into `handleSync(task:)`, which flushes the SQLite
/// queue and re-schedules.
public final class AddressIQBackgroundScheduler {
    public static let shared = AddressIQBackgroundScheduler()
    public static let telemetrySyncIdentifier = "com.addressiq.sdk.telemetry-sync"

    private init() {}

    public func register(syncHandler: @escaping () async -> Void) {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.telemetrySyncIdentifier,
                using: nil
            ) { task in
                guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
                self.handleSync(task: task, run: syncHandler)
            }
        }
        #endif
    }

    public func schedule(after seconds: TimeInterval = 15 * 60) {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: Self.telemetrySyncIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
            try? BGTaskScheduler.shared.submit(request)
        }
        #endif
    }

    #if canImport(BackgroundTasks)
    @available(iOS 13.0, *)
    private func handleSync(task: BGProcessingTask, run: @escaping () async -> Void) {
        let timeout = DispatchWorkItem { task.setTaskCompleted(success: false) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)

        task.expirationHandler = { timeout.cancel(); task.setTaskCompleted(success: false) }

        Task {
            await run()
            timeout.cancel()
            task.setTaskCompleted(success: true)
            self.schedule()
        }
    }
    #endif
}
