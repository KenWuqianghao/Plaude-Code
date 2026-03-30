import AppKit
import CoreGraphics
import Foundation

/// Synthesizes pointer, click, and scroll events (Accessibility + `CGEvent`, same trust as key injection).
final class PointerEmitter {
    /// Absolute screen position for HID touch mapping (not `mouseLocation` + Δ — that reread fights `CGWarp` and snaps back on release).
    func warpTo(x: CGFloat, y: CGFloat) -> Bool {
        CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
        return true
    }

    func moveBy(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard deltaX != 0 || deltaY != 0 else { return true }
        let hw = NSEvent.mouseLocation
        var loc = hw
        loc.x += deltaX
        loc.y += deltaY
        // `CGEvent` mouseMoved + absolute position fought Quartz on vertical axis (bounce around a horizontal band).
        // Warp matches how “teleport here” works and matches horizontal/vertical handling — same `loc` math for both.
        CGWarpMouseCursorPosition(CGPoint(x: loc.x, y: loc.y))
        return true
    }

    func scrollBy(deltaY: CGFloat) -> Bool {
        guard deltaY != 0 else { return true }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let ev = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        ) else { return false }
        ev.post(tap: .cghidEventTap)
        return true
    }

    func leftMouseDown() -> Bool {
        postMouse(type: .leftMouseDown, button: .left)
    }

    func leftMouseUp() -> Bool {
        postMouse(type: .leftMouseUp, button: .left)
    }

    private func postMouse(type: CGEventType, button: CGMouseButton) -> Bool {
        let loc = NSEvent.mouseLocation
        guard let source = CGEventSource(stateID: .hidSystemState),
              let ev = CGEvent(
                  mouseEventSource: source,
                  mouseType: type,
                  mouseCursorPosition: loc,
                  mouseButton: button
              ) else { return false }
        ev.post(tap: .cghidEventTap)
        return true
    }
}
