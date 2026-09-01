import XCTest
import CoreLocation
@testable import AddressIQ

/**
 The periodic background check is the only thing that evidences an address
 overnight.

 Region monitoring is edge-triggered, so a resident asleep at home crosses
 nothing between dusk and morning. If the background check has no current fix to
 report, the overnight hours carry no readings at all — and those are the hours
 that actually evidence residency, so the backend's night-cycle floor can never
 be met and the verification runs its whole window out as undecided.

 `manager.location` alone cannot carry this: it holds whatever CoreLocation last
 happened to produce, which for a stationary device is the fix from the evening
 arrival, hours stale by the time a background window is granted.
 */
final class BackgroundFixTests: XCTestCase {

    func testReturnsNilWithoutAlwaysAuthorization() async {
        // The simulator starts at `notDetermined`. A one-shot request there
        // wakes the radio for a callback that never comes, so the guard has to
        // decline up front rather than sit on the background window.
        let manager = AddressIQLocationManager()
        let fix = await manager.requestFreshLocation(timeout: 1)
        XCTAssertNil(fix)
    }

    func testDecliningIsCheapEnoughForABackgroundWindow() async {
        // A background task gets roughly 30 seconds, shared with the queue
        // flush. Declining must be immediate, not a wait for the full timeout.
        let manager = AddressIQLocationManager()
        let started = Date()
        _ = await manager.requestFreshLocation(timeout: 30)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testConcurrentRequestsAllResolveExactlyOnce() async {
        // Every waiter shares one in-flight request. Resuming a continuation
        // twice traps, so this would crash the process rather than fail politely
        // if the waiter list were drained carelessly.
        let manager = AddressIQLocationManager()
        let results = await withTaskGroup(of: CLLocation?.self) { group -> [CLLocation?] in
            for _ in 0..<8 {
                group.addTask { await manager.requestFreshLocation(timeout: 1) }
            }
            var collected: [CLLocation?] = []
            for await result in group { collected.append(result) }
            return collected
        }
        XCTAssertEqual(results.count, 8)
    }

    func testDelegateCallbackResolvesWaiters() async {
        // Authorization is refused in the simulator, so drive the delegate
        // directly: a delivered fix must resolve whoever is waiting on it.
        let manager = AddressIQLocationManager()
        let expected = CLLocation(latitude: 6.5244, longitude: 3.3792)

        let waiter = Task { await manager.awaitFix(timeout: 30) }
        // Give the waiter a moment to enqueue before the callback fires.
        try? await Task.sleep(nanoseconds: 200_000_000)
        manager.locationManager(CLLocationManager(), didUpdateLocations: [expected])

        let received = await waiter.value
        XCTAssertEqual(received?.coordinate.latitude, expected.coordinate.latitude)
    }

    func testFailedFixResolvesRatherThanHanging() async {
        // A failed fix and a slow one are the same thing here: nothing current
        // to report. What matters is that the waiter is released either way.
        let manager = AddressIQLocationManager()

        let waiter = Task { await manager.awaitFix(timeout: 30) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        manager.locationManager(
            CLLocationManager(),
            didFailWithError: CLError(.locationUnknown)
        )

        let received = await waiter.value
        XCTAssertNil(received)
    }
}
