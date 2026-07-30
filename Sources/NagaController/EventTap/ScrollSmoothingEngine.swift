import Cocoa
import ApplicationServices

/// Mos-inspired smoothing poster. All mutable state stays on the main queue so
/// settings changes, tap callbacks and shutdown cannot race one another.
final class ScrollSmoothingEngine {
    static let shared = ScrollSmoothingEngine()

    private var timer: DispatchSourceTimer?
    private var buffer = (y: 0.0, x: 0.0)
    private var current = (y: 0.0, x: 0.0)
    private var direction = (y: 0.0, x: 0.0)
    private var filterY = [0.0, 0.0]
    private var filterX = [0.0, 0.0]
    private var settings = ScrollSettings.defaults
    private var shiftAxis = false
    private var lastInputTime: CFTimeInterval = 0
    private var trackingStarted = false
    private var momentumStarted = false

    private init() {}

    func update(settings: ScrollSettings, y: Double, x: Double, amplification: Double, shiftAxis: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.settings = settings.validated()
        self.shiftAxis = shiftAxis
        append(axis: &buffer.y, current: &current.y, direction: &direction.y, value: y * settings.speed * amplification)
        append(axis: &buffer.x, current: &current.x, direction: &direction.x, value: x * settings.speed * amplification)
        lastInputTime = CFAbsoluteTimeGetCurrent()
        startTimerIfNeeded()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        finish(postEndingPhase: settings.simulateTrackpad)
    }

    func setShiftAxis(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        shiftAxis = enabled
    }

    private func append(axis: inout Double, current: inout Double, direction: inout Double, value: Double) {
        guard value != 0 else { return }
        if value * direction > 0 {
            axis += value
        } else {
            axis = value
            current = 0
        }
        direction = value
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func tick() {
        let transition = settings.durationTransition
        let rawY = (buffer.y - current.y) * transition
        let rawX = (buffer.x - current.x) * transition
        current.y += rawY
        current.x += rawX

        let y = polish(&filterY, next: rawY)
        let x = polish(&filterX, next: rawX)
        var output = (y: y, x: x)
        if shiftAxis, output.y != 0, output.x == 0 {
            output = (y: 0, x: output.y)
        }

        let now = CFAbsoluteTimeGetCurrent()
        let receivingInput = now - lastInputTime <= 0.18
        let residual = max(abs(buffer.y - current.y), abs(buffer.x - current.x))
        if settings.simulateTrackpad {
            if receivingInput {
                post(y: output.y, x: output.x, scrollPhase: trackingStarted ? 2 : 1, momentumPhase: 0)
                trackingStarted = true
            } else if residual > settings.deadZone {
                if trackingStarted {
                    post(y: 0, x: 0, scrollPhase: 4, momentumPhase: 0)
                    trackingStarted = false
                }
                post(y: output.y, x: output.x, scrollPhase: 0, momentumPhase: momentumStarted ? 2 : 1)
                momentumStarted = true
            }
        } else if max(abs(output.y), abs(output.x)) > settings.deadZone {
            post(y: output.y, x: output.x, scrollPhase: 0, momentumPhase: 0)
        }

        if !receivingInput, residual <= settings.deadZone,
           max(abs(output.y), abs(output.x)) <= settings.deadZone {
            finish(postEndingPhase: settings.simulateTrackpad)
        }
    }

    // Ported from Mos' interpolation filter. The window only ever reads
    // index 1 (previous smoothed value) and returns index 0, so the initial
    // 2-element reset and the 5-element steady state are both valid.
    private func polish(_ window: inout [Double], next: Double) -> Double {
        let first = window[1]
        let difference = next - first
        window = [first, first + 0.23 * difference, first + 0.5 * difference,
                  first + 0.77 * difference, next]
        return window[0]
    }

    private func finish(postEndingPhase: Bool) {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        if postEndingPhase {
            if trackingStarted { post(y: 0, x: 0, scrollPhase: 4, momentumPhase: 0) }
            if momentumStarted { post(y: 0, x: 0, scrollPhase: 0, momentumPhase: 3) }
        }
        buffer = (0, 0)
        current = (0, 0)
        direction = (0, 0)
        filterY = [0, 0]
        filterX = [0, 0]
        trackingStarted = false
        momentumStarted = false
        lastInputTime = 0
    }

    private func post(y: Double, x: Double, scrollPhase: Double, momentumPhase: Double) {
        guard y != 0 || x != 0 || scrollPhase != 0 || momentumPhase != 0,
              let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2, wheel1: Int32(y.rounded()),
                                  wheel2: Int32(x.rounded()), wheel3: 0) else { return }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: x)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: settings.simulateTrackpad ? 1 : 0)
        event.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        SyntheticEventMarker.mark(event)
        event.post(tap: .cghidEventTap)
    }
}
