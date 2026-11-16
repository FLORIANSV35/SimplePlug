import AVFoundation
import AudioToolbox
import CoreAudio

struct HostError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Audio engine: a single HAL unit (chosen interface, 2 in / 2 out) that passes the input
/// through the AU plugin to the output. No AVAudioEngine → full control over the buffer size.
final class HostEngine {
    static let maxFrames: UInt32 = 8192

    private(set) var plugin: AVAudioUnit?
    private(set) var isRunning = false

    private var hal: AudioUnit?
    private var renderBlock: AURenderBlock?
    private var pullBlock: AURenderPullInputBlock?
    private var inputList: UnsafeMutableAudioBufferListPointer?

    /// Diagnostic counters (written by the audio thread, read for debugging).
    struct Stats { var callbacks = 0, inputErrors = 0, pluginErrors = 0
                   var lastInputError: OSStatus = 0, lastPluginError: OSStatus = 0
                   var lastFrames: UInt32 = 0 }
    private(set) var stats = Stats()

    // Load gauge: time spent in the callback / buffer duration (1.0 = 100 % = dropout).
    // Written by the audio thread, read and reset by the UI (plain values, harmless race).
    private var currentRate: Double = 48000
    private var loadSum: Double = 0, loadMax: Double = 0, loadCount = 0
    private(set) var overloads = 0
    private static let secondsPerTick: Double = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return Double(t.numer) / Double(t.denom) * 1e-9
    }()

    /// Average and peak load since the last call (nil if no buffer was processed).
    func readLoad() -> (average: Double, peak: Double)? {
        let n = loadCount, sum = loadSum, peak = loadMax
        loadCount = 0; loadSum = 0; loadMax = 0
        return n > 0 ? (sum / Double(n), peak) : nil
    }

    func resetMeter() { loadCount = 0; loadSum = 0; loadMax = 0; overloads = 0 }

    // MARK: Plugin

    func loadPlugin(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        stop()
        plugin = nil
        let unit = try await AVAudioUnit.instantiate(with: description, options: [])
        plugin = unit
        return unit
    }

    func unloadPlugin() {
        stop()
        plugin = nil
    }

    private func preparePlugin(rate: Double) throws {
        guard let unit = plugin else { renderBlock = nil; return }
        let au = unit.auAudioUnit
        do {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                throw HostError("Format audio invalide")
            }
            // AUv2 plugins come with their input bus disabled: without this they never ask for
            // input and render silence.
            if au.inputBusses.count > 0 {
                au.inputBusses[0].isEnabled = true
                try au.inputBusses[0].setFormat(format)
            }
            if let bus = au.outputBusses.count > 0 ? au.outputBusses[0] : nil { try bus.setFormat(format) }
            au.maximumFramesToRender = Self.maxFrames
            try au.allocateRenderResources()
        } catch {
            throw HostError("This plugin doesn't support 2 inputs / 2 outputs at \(Int(rate)) Hz (\(error.localizedDescription))")
        }
        renderBlock = au.renderBlock
    }

    // MARK: Start / stop

    func start(device: AudioDeviceID, bufferFrames: UInt32, sampleRate: Double) throws {
        stop()
        HAL.setSampleRate(device, sampleRate)
        HAL.setBufferFrames(device, bufferFrames)
        let rate = HAL.sampleRate(device) ?? sampleRate
        currentRate = rate
        resetMeter()
        _ = Self.secondsPerTick
        do {
            try preparePlugin(rate: rate)
            try startHAL(device: device, rate: rate)
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let unit = hal {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        hal = nil
        isRunning = false
        if renderBlock != nil { plugin?.auAudioUnit.deallocateRenderResources() }
        renderBlock = nil
        pullBlock = nil
        if let list = inputList {
            for buffer in list { buffer.mData?.deallocate() }
            list.unsafeMutablePointer.deallocate()
        }
        inputList = nil
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw HostError("\(what) (CoreAudio error \(status))") }
    }

    private func startHAL(device: AudioDeviceID, rate: Double) throws {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw HostError("HAL unit not found") }
        var unitOpt: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unitOpt), "Creating the audio unit")
        guard let unit = unitOpt else { throw HostError("Audio unit is null") }
        hal = unit

        var on: UInt32 = 1
        let u32 = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, u32), "Enabling input")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, u32), "Enabling output")

        var dev = device
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)), "Selecting the interface")

        // Client-side format: 2 non-interleaved float channels (the interface's first 2 channels).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, asbdSize), "Input format")
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, asbdSize), "Output format")

        var maxFrames = Self.maxFrames
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, u32), "Maximum buffer size")

        // Pre-allocated input buffer (outside real time).
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        for i in 0..<2 {
            let bytes = Int(Self.maxFrames) * MemoryLayout<Float>.size
            let mem = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
            memset(mem, 0, bytes)
            list[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes), mData: mem)
        }
        inputList = list

        // Block that feeds the input to the plugin (created once, no allocation in the callback).
        let src = list
        pullBlock = { _, _, frames, bus, abl in
            guard bus == 0 else { return kAudioUnitErr_NoConnection }
            let dst = UnsafeMutableAudioBufferListPointer(abl)
            let bytes = Int(frames) * MemoryLayout<Float>.size
            for i in 0..<min(dst.count, src.count) {
                if let d = dst[i].mData, let s = src[i].mData { memcpy(d, s, bytes) } else { dst[i].mData = src[i].mData }
                dst[i].mDataByteSize = UInt32(bytes)
            }
            return noErr
        }

        var callback = AURenderCallbackStruct(inputProc: halRenderCallback,
                                              inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "Audio callback")

        try check(AudioUnitInitialize(unit), "Initializing the interface")
        try check(AudioOutputUnitStart(unit), "Starting the interface")
    }

    // MARK: Real time

    fileprivate func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            time: UnsafePointer<AudioTimeStamp>,
                            frames: UInt32,
                            output: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        let start = mach_absolute_time()
        defer {
            let seconds = Double(mach_absolute_time() &- start) * Self.secondsPerTick
            let load = seconds / (Double(frames) / currentRate)
            loadSum += load
            loadCount += 1
            if load > loadMax { loadMax = load }
            if load > 1 { overloads += 1 }
        }
        guard let output, let unit = hal, let input = inputList else { return noErr }
        let bytes = Int(frames) * MemoryLayout<Float>.size
        for i in 0..<input.count { input[i].mDataByteSize = UInt32(bytes) }

        let out = UnsafeMutableAudioBufferListPointer(output)
        var inFlags = AudioUnitRenderActionFlags()
        stats.callbacks += 1
        stats.lastFrames = frames
        let err = AudioUnitRender(unit, &inFlags, time, 1, frames, input.unsafeMutablePointer)
        guard err == noErr else {
            stats.inputErrors += 1
            stats.lastInputError = err
            for b in out { if let d = b.mData { memset(d, 0, bytes) } }
            return noErr
        }

        if let block = renderBlock, let pull = pullBlock {
            let st = block(flags, time, frames, 0, output, pull)
            if st == noErr { return noErr }
            stats.pluginErrors += 1
            stats.lastPluginError = st
        }
        // No plugin (or error): the input passes through unchanged.
        for i in 0..<min(out.count, input.count) {
            if let d = out[i].mData, let s = input[i].mData { memcpy(d, s, bytes) }
        }
        return noErr
    }
}

private let halRenderCallback: AURenderCallback = { refCon, flags, time, _, frames, ioData in
    Unmanaged<HostEngine>.fromOpaque(refCon).takeUnretainedValue()
        .render(flags: flags, time: time, frames: frames, output: ioData)
}
