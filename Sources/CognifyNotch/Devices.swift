import Carbon.HIToolbox
import CoreAudio
import Foundation
import IOKit.ps

/// Kabar singkat dari perangkat Mac yang tampil di sayap notch.
enum DeviceNotice: Equatable {
    case charging(percent: Int, full: Bool)
    case unplugged(percent: Int)
    case lowBattery(percent: Int)
    case audioConnected(name: String, battery: String?)
    case audioDisconnected(name: String)
}

// MARK: - Baterai & charger

/// Charger dicolok/dicabut dan baterai lemah (20% dan 10%, sekali per pemakaian baterai).
/// Mac tanpa baterai (iMac, Mac mini) tidak pernah mengirim kabar.
@MainActor
final class PowerMonitor {
    var onNotice: ((DeviceNotice) -> Void)?

    private struct Reading: Equatable {
        let percent: Int
        let onAC: Bool
        let full: Bool
    }

    private var source: CFRunLoopSource?
    private var last: Reading?
    private var warned = Set<Int>()

    func setEnabled(_ enabled: Bool) {
        if enabled, source == nil {
            last = Self.read()
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let created = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.changed() }
            }, context)?.takeRetainedValue() else { return }
            source = created
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        } else if !enabled, let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = nil
        }
    }

    private func changed() {
        guard let now = Self.read() else { return }
        defer { last = now }
        guard let last else { return }
        if now.onAC != last.onAC {
            onNotice?(now.onAC ? .charging(percent: now.percent, full: now.full) : .unplugged(percent: now.percent))
            if now.onAC { warned.removeAll() }
            return
        }
        if !now.onAC, now.percent < last.percent {
            for threshold in [20, 10] where now.percent <= threshold && !warned.contains(threshold) {
                warned.insert(threshold)
                onNotice?(.lowBattery(percent: now.percent))
                break
            }
        }
    }

    private static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = Int((Double(current) / Double(max) * 100).rounded())
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let full = description[kIOPSIsChargedKey] as? Bool ?? (percent >= 100)
            return Reading(percent: percent, onAC: onAC, full: full)
        }
        return nil
    }
}

// MARK: - AirPods & headphone

/// Output suara berpindah ke perangkat Bluetooth (AirPods, headphone, speaker) → nama perangkat,
/// lalu baterainya menyusul dari `system_profiler`. Tidak perlu izin Bluetooth: yang dibaca hanya
/// perangkat output suara (Core Audio).
@MainActor
final class AudioDeviceMonitor {
    var onNotice: ((DeviceNotice) -> Void)?

    private var enabled = false
    private var current: (id: AudioObjectID, name: String, bluetooth: Bool)?
    private var batteryTask: Task<Void, Never>?
    private let listener: AudioObjectPropertyListenerBlock
    private static var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)

    init() {
        var weakSelf: AudioDeviceMonitor?
        listener = { _, _ in Task { @MainActor in weakSelf?.changed() } }
        weakSelf = self
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value {
            current = Self.defaultDevice()
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.address, .main, listener)
        } else {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.address, .main, listener)
            batteryTask?.cancel()
        }
    }

    private func changed() {
        guard let next = Self.defaultDevice(), next.id != current?.id else { return }
        let previous = current
        current = next
        batteryTask?.cancel()
        if next.bluetooth {
            onNotice?(.audioConnected(name: next.name, battery: nil))
            let name = next.name
            batteryTask = Task { [weak self] in
                // AirPods baru melaporkan baterai sesaat setelah tersambung.
                for delay: UInt64 in [1, 3] {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    if let battery = await Self.battery(of: name) {
                        guard !Task.isCancelled, self?.current?.name == name else { return }
                        self?.onNotice?(.audioConnected(name: name, battery: battery))
                        return
                    }
                }
            }
        } else if let previous, previous.bluetooth {
            onNotice?(.audioDisconnected(name: previous.name))
        }
    }

    private static func defaultDevice() -> (id: AudioObjectID, name: String, bluetooth: Bool)? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &transport)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        a.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr, let name else { return nil }
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        return (id, name.takeRetainedValue() as String, bluetooth)
    }

    /// "L 80% R 75%" (AirPods) atau "60%" (headphone biasa); nil kalau perangkat tidak melaporkan.
    nonisolated private static func battery(of name: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: parseBattery(data, name: name))
            }
        }
    }

    nonisolated static func parseBattery(_ data: Data, name: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                guard let info = entry[name] as? [String: Any] else { continue }
                let left = info["device_batteryLevelLeft"] as? String
                let right = info["device_batteryLevelRight"] as? String
                if let left, let right { return "L \(left) R \(right)" }
                if let single = left ?? right ?? info["device_batteryLevelMain"] as? String { return single }
            }
        }
        return nil
    }
}

// MARK: - Shortcut keyboard

/// Shortcut global ⌃⌥N (Carbon hot key: tidak perlu izin Aksesibilitas).
@MainActor
final class HotKey {
    static let label = "⌃⌥N"

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        if enabled, ref == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.onPress?() }
                return noErr
            }, 1, &spec, context, &handler)
            let id = EventHotKeyID(signature: OSType(0x434E_4F54), id: 1) // "CNOT"
            RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        } else if !enabled {
            if let ref { UnregisterEventHotKey(ref) }
            if let handler { RemoveEventHandler(handler) }
            ref = nil
            handler = nil
        }
    }
}
