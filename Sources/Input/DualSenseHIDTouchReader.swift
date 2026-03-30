import Foundation
import IOKit
import IOKit.hid

// MARK: - C callbacks (top-level `func` so they convert to C function pointers)

fileprivate func dualSenseHidDeviceMatched(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context, result == kIOReturnSuccess else { return }
    let reader = Unmanaged<DualSenseHIDTouchReader>.fromOpaque(context).takeUnretainedValue()
    guard let buf = reader.reportBufferForHid else { return }
    reader.attach(device: device, buffer: buf)
}

fileprivate func dualSenseHidDeviceRemoved(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context, result == kIOReturnSuccess else { return }
    let reader = Unmanaged<DualSenseHIDTouchReader>.fromOpaque(context).takeUnretainedValue()
    reader.onDeviceRemoved(device)
}

fileprivate func dualSenseHidInputReport(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ type: IOHIDReportType,
    _ reportID: UInt32,
    _ report: UnsafeMutablePointer<UInt8>,
    _ reportLength: CFIndex
) {
    guard result == kIOReturnSuccess, let context, reportLength > 0 else { return }
    let reader = Unmanaged<DualSenseHIDTouchReader>.fromOpaque(context).takeUnretainedValue()
    reader.handleReport(UnsafePointer(report), length: reportLength, ioReportID: reportID)
}

/// Reads DualSense touchpad positions from raw HID input reports. Layout matches Linux
/// `drivers/hid/hid-playstation.c` (`dualsense_input_report` / `dualsense_parse_report`).
/// macOS often surfaces stuck `GameController` touch axes; this path reads vendor reports directly.
final class DualSenseHIDTouchReader {
    private static let sonyVID = 0x054C
    /// DualSense, Edge, and common regional/model PIDs seen over USB and Bluetooth.
    private static let productIDs: [Int] = [
        0x0CE6, 0x0CE7, 0x0DF2, 0x0D5A, 0x0DF3, 0x05E0,
    ]

    /// Linux `dualsense` touch bytes need ~33+8 of main input; short HID interfaces (e.g. 10-byte) omit touch.
    private static let minHidInputReportBytesForTouch = 40
    /// BT: `hid-playstation` retrieves feature `0x05` so the pad emits full `0x31` (78 B) instead of minimal `0x01` (10 B).
    private static let featureReportCalibration: UInt8 = 0x05
    private static let featureReportCalibrationSize = 41
    private static let inputReportBluetoothFull: UInt8 = 0x31
    private static let inputReportBluetoothFullSize = 78
    /// `dualsense_input_report` begins at `data[2]` for BT full report; touch field offset inside that struct is 32.
    private static let bluetoothTouchBase = 2 + 32

    private static let touchInactiveMask: UInt8 = 0x80
    private static let normX: Float = 1920
    private static let normY: Float = 1080

    private var hidManager: IOHIDManager?
    fileprivate var reportBufferForHid: UnsafeMutablePointer<UInt8>?
    private let reportCapacity = 128
    private var activeDevice: IOHIDDevice?

    private(set) var primaryNorm: (x: Float, y: Float) = (0, 0)
    private(set) var secondaryNorm: (x: Float, y: Float) = (0, 0)
    private(set) var hasPrimary: Bool = false
    private(set) var hasSecondary: Bool = false
    /// Increments on each parsed HID report — use to apply pointer deltas once per device sample, not per gamepad poll.
    private(set) var touchReportSequence: UInt64 = 0

    var isHIDSessionActive: Bool { activeDevice != nil }

    init() {
        reportBufferForHid = UnsafeMutablePointer<UInt8>.allocate(capacity: reportCapacity)
        reportBufferForHid?.initialize(repeating: 0, count: reportCapacity)
    }

    deinit {
        stop()
        reportBufferForHid?.deallocate()
        reportBufferForHid = nil
    }

    func start() {
        stop()
        guard let buf = reportBufferForHid else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let specs = NSMutableArray()
        for pid in Self.productIDs {
            specs.add([
                kIOHIDVendorIDKey as String: Self.sonyVID,
                kIOHIDProductIDKey as String: pid,
            ] as NSDictionary)
        }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, specs)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, dualSenseHidDeviceRemoved, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openRes = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openRes == kIOReturnSuccess else { return }

        hidManager = mgr

        // Device may already be connected; `matching` callback does not always fire for pre-existing devices.
        if let cf = IOHIDManagerCopyDevices(mgr), let set = cf as NSSet? {
            var devs: [IOHIDDevice] = []
            devs.reserveCapacity(set.count)
            for case let dev as IOHIDDevice in set {
                devs.append(dev)
            }
            devs.sort { Self.maxInputReportSizeBytes($0) > Self.maxInputReportSizeBytes($1) }
            for dev in devs {
                guard activeDevice == nil else { break }
                attach(device: dev, buffer: buf)
            }
        }

        // Register after initial sorted attach so a short-report interface cannot "win" first via callback.
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, dualSenseHidDeviceMatched, ctx)
    }

    private static func maxInputReportSizeBytes(_ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// After open: same as Linux `ps_get_report(..., DS_FEATURE_REPORT_CALIBRATION, ..., HID_FEATURE_REPORT, HID_REQ_GET_REPORT)`.
    private func enableDualSenseBluetoothFullReportingIfNeeded(
        device: IOHIDDevice,
        mirs: Int,
        transportHint: String
    ) {
        let transport = transportHint
        let saysBT = transport.range(of: "Bluetooth", options: .caseInsensitive) != nil
            || transport.range(of: "BLE", options: .caseInsensitive) != nil
        /// USB full report is 64 B; BT extended max is 78 B per `hid-playstation`. If transport is empty, infer from size.
        let inferredBT = !saysBT && mirs >= Self.inputReportBluetoothFullSize
        guard saysBT || inferredBT else { return }

        var buf = [UInt8](repeating: 0, count: Self.featureReportCalibrationSize)
        var outLen = CFIndex(buf.count)
        _ = buf.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnNoMemory }
            return IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(Self.featureReportCalibration),
                base,
                &outLen
            )
        }
    }

    func stop() {
        if let dev = activeDevice {
            if let buf = reportBufferForHid {
                IOHIDDeviceRegisterInputReportCallback(dev, buf, 0, nil, nil)
            }
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            activeDevice = nil
        }
        if let mgr = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        hasPrimary = false
        hasSecondary = false
        primaryNorm = (0, 0)
        secondaryNorm = (0, 0)
        touchReportSequence = 0
    }

    fileprivate func attach(device: IOHIDDevice, buffer: UnsafeMutablePointer<UInt8>) {
        if activeDevice != nil { return }
        let mirs = Self.maxInputReportSizeBytes(device)
        let transportHint = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
        if mirs > 0, mirs < Self.minHidInputReportBytesForTouch {
            return
        }
        var open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if open != kIOReturnSuccess {
            open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        guard open == kIOReturnSuccess else { return }
        enableDualSenseBluetoothFullReportingIfNeeded(device: device, mirs: mirs, transportHint: transportHint)
        activeDevice = device
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            reportCapacity,
            dualSenseHidInputReport,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    fileprivate func onDeviceRemoved(_ device: IOHIDDevice) {
        guard activeDevice == device else { return }
        if let buf = reportBufferForHid {
            IOHIDDeviceRegisterInputReportCallback(device, buf, 0, nil, nil)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        activeDevice = nil
        hasPrimary = false
        hasSecondary = false
        touchReportSequence = 0
    }

    fileprivate func handleReport(_ report: UnsafePointer<UInt8>, length: CFIndex, ioReportID: UInt32) {
        let n = min(Int(length), reportCapacity)
        let data = UnsafeBufferPointer(start: report, count: n).map { $0 }

        guard let parsed = Self.parseDualSenseTouch(from: data, ioReportID: ioReportID) else { return }
        applyParsed(parsed)
    }

    private func applyParsed(_ parsed: (
        reportId: Int,
        touchBase: Int,
        p0Active: Bool,
        p0X: Int,
        p0Y: Int,
        p1Active: Bool,
        p1X: Int,
        p1Y: Int
    )) {
        touchReportSequence &+= 1
        hasPrimary = parsed.p0Active
        hasSecondary = parsed.p1Active
        if parsed.p0Active {
            primaryNorm = (Self.normalizeAxis(parsed.p0X, max: Self.normX), Self.normalizeAxis(parsed.p0Y, max: Self.normY))
        } else {
            primaryNorm = (0, 0)
        }
        if parsed.p1Active {
            secondaryNorm = (Self.normalizeAxis(parsed.p1X, max: Self.normX), Self.normalizeAxis(parsed.p1Y, max: Self.normY))
        } else {
            secondaryNorm = (0, 0)
        }
    }

    private static func normalizeAxis(_ v: Int, max axisMax: Float) -> Float {
        let f = Float(v) / axisMax * 2 - 1
        return Swift.min(Swift.max(f, -1), 1)
    }

    /// `IOHIDDeviceRegisterInputReportCallback` often supplies **payload without** leading report-id;
    /// the id arrives separately as `ioReportID`. USB payload: touch at 32. Full USB buffer: touch at 33.
    /// BT id 0x31 (49): `ds_report` at `[2]` in a full 78-byte report → touch at 34.
    private static func parseDualSenseTouch(from data: [UInt8], ioReportID: UInt32) -> (
        reportId: Int,
        touchBase: Int,
        p0Active: Bool,
        p0X: Int,
        p0Y: Int,
        p1Active: Bool,
        p1X: Int,
        p1Y: Int
    )? {
        guard !data.isEmpty else { return nil }

        let b0 = Int(data[0])
        if data.count >= Self.inputReportBluetoothFullSize,
           b0 == Int(Self.inputReportBluetoothFull) || ioReportID == 49
        {
            let touchBase = Self.bluetoothTouchBase
            if touchBase + 7 < data.count,
               let t0 = decodeTouchPoint(data, base: touchBase),
               let t1 = decodeTouchPoint(data, base: touchBase + 4)
            {
                return (
                    Int(Self.inputReportBluetoothFull),
                    touchBase,
                    t0.active,
                    t0.x,
                    t0.y,
                    t1.active,
                    t1.x,
                    t1.y
                )
            }
        }

        var candidates: [(rid: Int, base: Int)] = []

        if b0 == 0x01, data.count >= 41 { candidates.append((1, 33)) }
        if b0 == 0x31, data.count >= 42 { candidates.append((0x31, 34)) }

        if ioReportID == 1, data.count >= 40 { candidates.append((1, 32)) }
        // Bluetooth main input report (decimal 49 = 0x31).
        if ioReportID == 49 {
            if data.count >= 41 { candidates.append((0x31, 30)) }
            if data.count >= 42 { candidates.append((0x31, 31)) }
            if data.count >= 43 { candidates.append((0x31, 32)) }
            if data.count >= 44 { candidates.append((0x31, 33)) }
            if data.count >= 45 { candidates.append((0x31, 34)) }
            if data.count >= 46 { candidates.append((0x31, 35)) }
        }

        // Some stack snapshots include the report id only via `ioReportID` with generic payloads.
        if ioReportID != 0, b0 != 0x01, b0 != 0x31, data.count >= 40 {
            if ioReportID == 1 { candidates.append((1, 32)) }
            if ioReportID == 49 { candidates.append((0x31, 32)) }
        }

        var seen = Set<String>()
        var best: (
            reportId: Int,
            touchBase: Int,
            p0Active: Bool,
            p0X: Int,
            p0Y: Int,
            p1Active: Bool,
            p1X: Int,
            p1Y: Int
        )?
        var bestScore = -1
        for cand in candidates {
            let key = "\(cand.rid)_\(cand.base)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let base = cand.base
            guard base + 7 < data.count,
                  let t0 = decodeTouchPoint(data, base: base),
                  let t1 = decodeTouchPoint(data, base: base + 4)
            else {
                continue
            }
            let c0 = data[base]
            let c1 = data[base + 4]
            var sc = 0
            if t0.active { sc += 5 }
            if t1.active { sc += 5 }
            if t0.x > 0, t0.x < 4000, t0.y < 4000 { sc += 1 }
            if t1.x > 0, t1.x < 4000, t1.y < 4000 { sc += 1 }
            if !t0.active, (c0 & touchInactiveMask) != 0 { sc += 2 }
            if !t1.active, (c1 & touchInactiveMask) != 0 { sc += 2 }
            if sc > bestScore {
                bestScore = sc
                best = (cand.rid, base, t0.active, t0.x, t0.y, t1.active, t1.x, t1.y)
            }
        }
        guard bestScore >= 0, let b = best else { return nil }
        return (b.reportId, b.touchBase, b.p0Active, b.p0X, b.p0Y, b.p1Active, b.p1X, b.p1Y)
    }

    private static func decodeTouchPoint(_ data: [UInt8], base: Int) -> (active: Bool, x: Int, y: Int)? {
        guard base + 3 < data.count else { return nil }
        let contact = data[base]
        let active = (contact & touchInactiveMask) == 0
        let x_lo = Int(data[base + 1])
        let pack = Int(data[base + 2])
        let y_hi = Int(data[base + 3])
        let x_hi = pack & 0x0F
        let y_lo = (pack >> 4) & 0x0F
        let x = (x_hi << 8) | x_lo
        let y = (y_hi << 4) | y_lo
        return (active, x, y)
    }
}
