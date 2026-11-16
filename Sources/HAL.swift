import CoreAudio
import Foundation

/// A usable audio interface: at least 2 inputs AND 2 outputs.
struct AudioInterface {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputs: Int
    let outputs: Int
}

/// Small CoreAudio helpers (interface enumeration, buffer size, sample rate, latency).
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as _: T.Type) -> T? {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, p) == noErr else { return nil }
        return p.pointee
    }

    static func set<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, value: T,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var addr = address(selector, scope)
        withUnsafePointer(to: value) {
            _ = AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        get(object, selector, as: Unmanaged<CFString>.self)?.takeRetainedValue() as String?
    }

    static func channels(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: Interfaces

    static func interfaces() -> [AudioInterface] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            let ins = channels(id, scope: kAudioDevicePropertyScopeInput)
            let outs = channels(id, scope: kAudioDevicePropertyScopeOutput)
            guard ins >= 2, outs >= 2,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInterface(id: id, uid: uid, name: name, inputs: ins, outputs: outs)
        }
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        get(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioDeviceID.self)
    }

    /// Calls `handler` (main thread) when an interface appears or disappears.
    static func observeDeviceList(_ handler: @escaping () -> Void) {
        var addr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { _, _ in handler() }
    }

    // MARK: Buffer

    static let standardBuffers: [UInt32] = [16, 32, 64, 128, 256, 512, 1024, 2048, 4096]

    static func availableBuffers(_ device: AudioDeviceID) -> [UInt32] {
        guard let r = get(device, kAudioDevicePropertyBufferFrameSizeRange, as: AudioValueRange.self) else {
            return standardBuffers
        }
        return standardBuffers.filter { Double($0) >= r.mMinimum && Double($0) <= r.mMaximum }
    }

    static func bufferFrames(_ device: AudioDeviceID) -> UInt32? {
        get(device, kAudioDevicePropertyBufferFrameSize, as: UInt32.self)
    }

    static func setBufferFrames(_ device: AudioDeviceID, _ frames: UInt32) {
        set(device, kAudioDevicePropertyBufferFrameSize, value: frames)
    }

    // MARK: Sample rate

    static let standardRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]

    static func availableRates(_ device: AudioDeviceID) -> [Double] {
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return standardRates }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else { return standardRates }
        return standardRates.filter { rate in ranges.contains { rate >= $0.mMinimum && rate <= $0.mMaximum } }
    }

    static func sampleRate(_ device: AudioDeviceID) -> Double? {
        get(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
    }

    /// Changes the sample rate and waits (up to 1 s) for the interface to actually apply it.
    static func setSampleRate(_ device: AudioDeviceID, _ rate: Double) {
        guard sampleRate(device) != rate else { return }
        set(device, kAudioDevicePropertyNominalSampleRate, value: Float64(rate))
        for _ in 0..<50 {
            if sampleRate(device) == rate { return }
            usleep(20_000)
        }
    }

    // MARK: Latency

    /// Approximate round-trip latency in milliseconds (input + output + 2 buffers).
    static func roundTripMilliseconds(_ device: AudioDeviceID) -> Double? {
        guard let rate = sampleRate(device), rate > 0, let buffer = bufferFrames(device) else { return nil }
        func fixed(_ scope: AudioObjectPropertyScope) -> UInt32 {
            (get(device, kAudioDevicePropertyLatency, scope: scope, as: UInt32.self) ?? 0)
                + (get(device, kAudioDevicePropertySafetyOffset, scope: scope, as: UInt32.self) ?? 0)
        }
        let frames = fixed(kAudioDevicePropertyScopeInput) + fixed(kAudioDevicePropertyScopeOutput) + 2 * buffer
        return Double(frames) / rate * 1000
    }
}
