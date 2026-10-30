import Foundation
import CoreFoundation
import Darwin

struct ThreeFingerContact: Equatable {
    let id: Int32
    let state: Int32
    let x: Double
    let y: Double
    var isTouching: Bool { state == 3 || state == 4 }
}

struct ThreeFingerFrame {
    let timestamp: TimeInterval
    let contacts: [ThreeFingerContact]
}

struct ThreeFingerTapRecognizer {
    var maximumDuration: TimeInterval = 0.30
    var maximumMovement: Double = 0.035
    var maximumLandingSpread: TimeInterval = 0.12
    var maximumReleaseSpread: TimeInterval = 0.12
    private var session: Session?
    private var previousTime: TimeInterval?
    private var lastTap: TimeInterval?
    private var blockedUntilRelease = false

    private struct Session {
        let start: TimeInterval
        var positions: [Int32: ThreeFingerContact]
        var sawThree = false
        var invalid = false
        var firstRelease: TimeInterval?
    }

    mutating func consume(_ frame: ThreeFingerFrame) -> Bool {
        guard frame.timestamp.isFinite, frame.contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            invalidateCurrentGesture(); return false
        }
        let active = frame.contacts.filter(\.isTouching)
        let ids = Set(active.map(\.id))
        defer { previousTime = frame.timestamp }
        if let previousTime, frame.timestamp < previousTime || (session != nil && frame.timestamp - previousTime > 0.20) {
            session = nil; blockedUntilRelease = !active.isEmpty; return false
        }
        if active.isEmpty, blockedUntilRelease {
            session = nil; blockedUntilRelease = false; return false
        }
        guard !blockedUntilRelease else { return false }
        if session == nil {
            guard !active.isEmpty else { return false }
            session = Session(start: frame.timestamp, positions: Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                              sawThree: active.count == 3, invalid: active.count > 3 || ids.count != active.count)
        }
        guard var current = session else { return false }
        if ids.count != active.count || active.count > 3 { current.invalid = true }
        for contact in frame.contacts where contact.isTouching || contact.state == 5 {
            if let initial = current.positions[contact.id] {
                if hypot(contact.x - initial.x, contact.y - initial.y) > maximumMovement { current.invalid = true }
            } else if contact.isTouching {
                if frame.timestamp - current.start > maximumLandingSpread || current.firstRelease != nil { current.invalid = true }
                current.positions[contact.id] = contact
            }
        }
        if current.positions.count > 3 { current.invalid = true }
        if active.count == 3 { current.sawThree = true }
        if current.sawThree, active.count < 3, current.firstRelease == nil { current.firstRelease = frame.timestamp }
        if let firstRelease = current.firstRelease, frame.timestamp - firstRelease > maximumReleaseSpread { current.invalid = true }
        let elapsed = frame.timestamp - current.start
        if elapsed > maximumDuration { current.invalid = true }
        if active.isEmpty {
            session = nil
            guard current.sawThree, current.positions.count == 3, !current.invalid,
                  elapsed >= 0.025, elapsed <= maximumDuration,
                  lastTap.map({ frame.timestamp - $0 >= 0.28 }) ?? true else { return false }
            lastTap = frame.timestamp; return true
        }
        session = current
        return false
    }

    mutating func invalidateCurrentGesture() {
        if session != nil { session?.invalid = true; blockedUntilRelease = true }
    }
}

enum ThreeFingerFrameDecoder {
    static let contactStride = 96
    static func decode(_ buffer: UnsafeRawBufferPointer, count: Int, timestamp: Double) -> ThreeFingerFrame? {
        guard MemoryLayout<Int>.size == 8, (0...32).contains(count), timestamp.isFinite, timestamp >= 0,
              buffer.count >= count * contactStride else { return nil }
        var contacts: [ThreeFingerContact] = []
        for index in 0..<count {
            let offset = index * contactStride
            let id = buffer.loadUnaligned(fromByteOffset: offset + 16, as: Int32.self)
            let state = buffer.loadUnaligned(fromByteOffset: offset + 20, as: Int32.self)
            let x = Double(buffer.loadUnaligned(fromByteOffset: offset + 32, as: Float.self))
            let y = Double(buffer.loadUnaligned(fromByteOffset: offset + 36, as: Float.self))
            guard (0...7).contains(state), x.isFinite, y.isFinite, (-0.02...1.02).contains(x), (-0.02...1.02).contains(y) else { return nil }
            contacts.append(ThreeFingerContact(id: id, state: state, x: x, y: y))
        }
        return ThreeFingerFrame(timestamp: timestamp, contacts: contacts)
    }
}

private typealias MTContactCallback = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
private let crabContactCallback: MTContactCallback = { device, contacts, count, timestamp, _ in
    guard let device, (0...32).contains(count), count == 0 || contacts != nil else { return }
    let buffer = UnsafeRawBufferPointer(start: contacts, count: Int(count) * ThreeFingerFrameDecoder.contactStride)
    MultitouchRouting.shared.receiver(for: device)?.receive(device: device, frame: ThreeFingerFrameDecoder.decode(buffer, count: Int(count), timestamp: timestamp))
}

final class ThreeFingerMonitor {
    private let handler: () -> Void
    private let queue = DispatchQueue(label: "dev.crab.three-finger-frames")
    private let lock = NSLock()
    private var run = UUID()
    private var revision: UInt64 = 0
    private var active = false
    private var recognizers: [UInt: (UInt64, ThreeFingerTapRecognizer)] = [:]
    private var framework: MultitouchFramework?
    private var list: CFArray?
    private var devices: [MultitouchFramework.Device] = []
    var deviceCount: Int { devices.count }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return active }

    init(handler: @escaping () -> Void) { self.handler = handler }
    deinit { stop() }

    func startOrRefresh() throws {
        let api: MultitouchFramework
        if let framework { api = framework } else { api = try MultitouchFramework(); framework = api }
        let snapshot = try api.enumerate()
        let identity = Set(snapshot.devices.map(\.id))
        if isRunning, identity == Set(devices.map(\.id)), devices.allSatisfy({ api.isRunning($0.pointer) }) { return }
        stop()
        list = snapshot.list
        for device in snapshot.devices {
            guard MultitouchRouting.shared.claim(device.pointer, receiver: self) else { continue }
            api.register(device.pointer, crabContactCallback)
            let code = api.start(device.pointer, 0)
            if code == 0 {
                devices.append(device)
            } else {
                MultitouchRouting.shared.remove(device.pointer, receiver: self)
                api.unregister(device.pointer, crabContactCallback); api.stop(device.pointer)
            }
        }
        guard !devices.isEmpty else { list = nil; throw MonitorError.cannotStart }
        lock.lock(); active = true; run = UUID(); lock.unlock()
    }

    func stop() {
        lock.lock(); active = false; run = UUID(); lock.unlock()
        if let framework {
            for device in devices {
                MultitouchRouting.shared.remove(device.pointer, receiver: self)
                framework.unregister(device.pointer, crabContactCallback)
                framework.stop(device.pointer)
            }
        }
        devices.removeAll(); list = nil
        queue.async { [weak self] in self?.recognizers.removeAll() }
    }

    func invalidateCurrentGesture() {
        lock.lock(); revision &+= 1; lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            for key in Array(self.recognizers.keys) { self.recognizers[key]?.1.invalidateCurrentGesture() }
        }
    }

    fileprivate func receive(device: UnsafeRawPointer, frame: ThreeFingerFrame?) {
        lock.lock(); let token = run, version = revision, enabled = active; lock.unlock()
        guard enabled else { return }
        let key = UInt(bitPattern: device)
        queue.async { [weak self] in
            guard let self, self.matches(token, version: version) else { return }
            guard let frame else { self.recognizers[key]?.1.invalidateCurrentGesture(); return }
            var value = self.recognizers[key] ?? (version, ThreeFingerTapRecognizer())
            if value.0 != version { value.1.invalidateCurrentGesture(); value.0 = version }
            let tap = value.1.consume(frame)
            self.recognizers[key] = value
            if tap {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.matches(token, version: version) else { return }
                    self.handler()
                }
            }
        }
    }

    private func matches(_ token: UUID, version: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return active && run == token && revision == version
    }

    enum MonitorError: LocalizedError {
        case unavailable, missingSymbol(String), noTrackpad, cannotStart
        var errorDescription: String? {
            switch self {
            case .unavailable: return L("此系统无法加载触控板多点触控接口。")
            case let .missingSymbol(name): return LF("此系统缺少三指轻点所需接口：%@。", name)
            case .noTrackpad: return L("未检测到可用触控板，请连接触控板后重试。")
            case .cannotStart: return L("触控板监听启动失败，请检查输入监控权限和设备连接。")
            }
        }
    }
}

private final class MultitouchRouting {
    static let shared = MultitouchRouting()
    private final class WeakReceiver { weak var value: ThreeFingerMonitor?; init(_ value: ThreeFingerMonitor) { self.value = value } }
    private let lock = NSLock()
    private var receivers: [UInt: WeakReceiver] = [:]
    func claim(_ device: UnsafeRawPointer, receiver: ThreeFingerMonitor) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = UInt(bitPattern: device)
        if let current = receivers[key]?.value, current !== receiver { return false }
        receivers[key] = WeakReceiver(receiver); return true
    }
    func remove(_ device: UnsafeRawPointer, receiver: ThreeFingerMonitor) {
        lock.lock(); defer { lock.unlock() }
        let key = UInt(bitPattern: device)
        if receivers[key]?.value === receiver { receivers.removeValue(forKey: key) }
    }
    func receiver(for device: UnsafeRawPointer) -> ThreeFingerMonitor? {
        lock.lock(); defer { lock.unlock() }; return receivers[UInt(bitPattern: device)]?.value
    }
}

private final class MultitouchFramework {
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias Register = @convention(c) (UnsafeRawPointer, MTContactCallback) -> Void
    typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeRawPointer) -> Void
    typealias IsRunning = @convention(c) (UnsafeRawPointer) -> Bool
    typealias Dimensions = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    typealias DeviceID = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    struct Device { let pointer: UnsafeRawPointer; let id: UInt64 }
    let handle: UnsafeMutableRawPointer
    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let isRunning: IsRunning
    let dimensions: Dimensions
    let deviceID: DeviceID

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL) else { throw ThreeFingerMonitor.MonitorError.unavailable }
        self.handle = handle
        do {
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let address = dlsym(handle, name) else { throw ThreeFingerMonitor.MonitorError.missingSymbol(name) }
                return unsafeBitCast(address, to: T.self)
            }
            createList = try symbol("MTDeviceCreateList", CreateList.self)
            register = try symbol("MTRegisterContactFrameCallback", Register.self)
            unregister = try symbol("MTUnregisterContactFrameCallback", Register.self)
            start = try symbol("MTDeviceStart", Start.self)
            stop = try symbol("MTDeviceStop", Stop.self)
            isRunning = try symbol("MTDeviceIsRunning", IsRunning.self)
            dimensions = try symbol("MTDeviceGetSensorDimensions", Dimensions.self)
            deviceID = try symbol("MTDeviceGetDeviceID", DeviceID.self)
        } catch { dlclose(handle); throw error }
    }
    deinit { dlclose(handle) }

    func enumerate() throws -> (list: CFArray, devices: [Device]) {
        guard let list = createList()?.takeRetainedValue() else { throw ThreeFingerMonitor.MonitorError.noTrackpad }
        var result: [Device] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            var rows: Int32 = 0, columns: Int32 = 0, id: UInt64 = 0
            guard dimensions(pointer, &rows, &columns) == 0, rows >= 10, columns >= 10,
                  deviceID(pointer, &id) == 0 else { continue }
            result.append(Device(pointer: pointer, id: id))
        }
        guard !result.isEmpty else { throw ThreeFingerMonitor.MonitorError.noTrackpad }
        return (list, result)
    }
}
