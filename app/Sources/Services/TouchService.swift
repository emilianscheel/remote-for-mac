import Foundation
import CoreGraphics

private func touchFrameCallback(
    device: MTDevice?, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int,
    timestamp: Double, frame: Int, refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<TouchService>.fromOpaque(refcon).takeUnretainedValue()
        .handle(device: device, touches: touches, count: numTouches, timestamp: timestamp)
}

final class TouchService {
    var onInput: ((RemoteInput) -> Void)?

    private var devices: [UInt64: MTDevice] = [:]
    private var startPoint: CGPoint?
    private var lastPoint: CGPoint?
    private var startTime = 0.0
    private var lastAngle: Double?
    private var accumulatedRotation = 0.0
    private var emittedRotation = 0.0

    func start() {
        stop()
        guard let list = MTDeviceCreateList()?.takeRetainedValue() as? [MTDevice] else { return }
        for device in list where isRemote(device) {
            var id: UInt64 = 0
            MTDeviceGetDeviceID(device, &id)
            MTRegisterContactFrameCallbackWithRefcon(
                device, touchFrameCallback, Unmanaged.passUnretained(self).toOpaque()
            )
            MTDeviceStart(device, 0)
            devices[id] = device
        }
    }

    func stop() {
        for device in devices.values {
            MTUnregisterContactFrameCallback(device, touchFrameCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
        resetGesture()
    }

    fileprivate func handle(
        device: MTDevice?, touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double
    ) {
        guard count > 0, let touch = touches?.pointee else {
            finishGesture(at: timestamp)
            return
        }

        let point = CGPoint(
            x: CGFloat(touch.normalizedVector.position.x),
            y: CGFloat(touch.normalizedVector.position.y)
        )
        if startPoint == nil {
            startPoint = point
            lastPoint = point
            startTime = timestamp
            lastAngle = angle(of: point)
            return
        }

        lastPoint = point
        guard radius(of: startPoint!) > 0.32 else { return }
        let currentAngle = angle(of: point)
        if let lastAngle {
            var delta = currentAngle - lastAngle
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            accumulatedRotation += delta
            emitRotationSteps()
        }
        lastAngle = currentAngle
    }

    private func finishGesture(at timestamp: Double) {
        defer { resetGesture() }
        guard let startPoint, let lastPoint else { return }
        guard abs(accumulatedRotation) < 0.45 else { return }
        let dx = lastPoint.x - startPoint.x
        let dy = lastPoint.y - startPoint.y
        guard timestamp - startTime < 0.45, max(abs(dx), abs(dy)) > 0.22 else { return }
        let direction: Direction
        if abs(dx) > abs(dy) { direction = dx > 0 ? .right : .left }
        else { direction = dy > 0 ? .up : .down }
        onInput?(.swipe(direction))
    }

    private func emitRotationSteps() {
        let step = 0.45
        while accumulatedRotation - emittedRotation >= step {
            emittedRotation += step
            onInput?(.circularCounterclockwise)
        }
        while accumulatedRotation - emittedRotation <= -step {
            emittedRotation -= step
            onInput?(.circularClockwise)
        }
    }

    private func isRemote(_ device: MTDevice) -> Bool {
        guard !MTDeviceIsBuiltIn(device) else { return false }
        var width: Int32 = 0
        var height: Int32 = 0
        MTDeviceGetSensorSurfaceDimensions(device, &width, &height)
        let largest = max(width, height)
        return largest > 0 && largest < 6000
    }

    private func radius(of point: CGPoint) -> Double {
        hypot(Double(point.x - 0.5), Double(point.y - 0.5))
    }

    private func angle(of point: CGPoint) -> Double {
        atan2(Double(point.y - 0.5), Double(point.x - 0.5))
    }

    private func resetGesture() {
        startPoint = nil
        lastPoint = nil
        startTime = 0
        lastAngle = nil
        accumulatedRotation = 0
        emittedRotation = 0
    }
}
