import AVFoundation
import AudioToolbox
import CoreAudio

struct HostError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Moteur audio : une seule unité HAL (interface choisie, 2 in / 2 out) qui fait passer
/// l'entrée dans le plugin AU puis vers la sortie. Pas de AVAudioEngine → buffer maîtrisé.
final class HostEngine {
    static let maxFrames: UInt32 = 8192

    private(set) var plugin: AVAudioUnit?
    private(set) var isRunning = false

    private var hal: AudioUnit?
    private var renderBlock: AURenderBlock?
    private var pullBlock: AURenderPullInputBlock?
    private var inputList: UnsafeMutableAudioBufferListPointer?

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
            if let bus = au.inputBusses.count > 0 ? au.inputBusses[0] : nil { try bus.setFormat(format) }
            if let bus = au.outputBusses.count > 0 ? au.outputBusses[0] : nil { try bus.setFormat(format) }
            au.maximumFramesToRender = Self.maxFrames
            try au.allocateRenderResources()
        } catch {
            throw HostError("Ce plugin n'accepte pas 2 entrées / 2 sorties à \(Int(rate)) Hz (\(error.localizedDescription))")
        }
        renderBlock = au.renderBlock
    }

    // MARK: Démarrage / arrêt

    func start(device: AudioDeviceID, bufferFrames: UInt32, sampleRate: Double) throws {
        stop()
        HAL.setSampleRate(device, sampleRate)
        HAL.setBufferFrames(device, bufferFrames)
        let rate = HAL.sampleRate(device) ?? sampleRate
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
        guard status == noErr else { throw HostError("\(what) (erreur CoreAudio \(status))") }
    }

    private func startHAL(device: AudioDeviceID, rate: Double) throws {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw HostError("Unité HAL introuvable") }
        var unitOpt: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unitOpt), "Création de l'unité audio")
        guard let unit = unitOpt else { throw HostError("Unité audio nulle") }
        hal = unit

        var on: UInt32 = 1
        let u32 = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, u32), "Activation de l'entrée")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, u32), "Activation de la sortie")

        var dev = device
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)), "Sélection de l'interface")

        // Format côté client : 2 canaux float non entrelacés (les 2 premiers canaux de l'interface).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, asbdSize), "Format d'entrée")
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, asbdSize), "Format de sortie")

        var maxFrames = Self.maxFrames
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, u32), "Taille max de buffer")

        // Tampon d'entrée pré-alloué (hors temps réel).
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        for i in 0..<2 {
            let bytes = Int(Self.maxFrames) * MemoryLayout<Float>.size
            let mem = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
            memset(mem, 0, bytes)
            list[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes), mData: mem)
        }
        inputList = list

        // Bloc qui fournit l'entrée au plugin (créé une fois, aucune allocation dans le callback).
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
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "Callback audio")

        try check(AudioUnitInitialize(unit), "Initialisation de l'interface")
        try check(AudioOutputUnitStart(unit), "Démarrage de l'interface")
    }

    // MARK: Temps réel

    fileprivate func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            time: UnsafePointer<AudioTimeStamp>,
                            frames: UInt32,
                            output: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let output, let unit = hal, let input = inputList else { return noErr }
        let bytes = Int(frames) * MemoryLayout<Float>.size
        for i in 0..<input.count { input[i].mDataByteSize = UInt32(bytes) }

        let out = UnsafeMutableAudioBufferListPointer(output)
        var inFlags = AudioUnitRenderActionFlags()
        guard AudioUnitRender(unit, &inFlags, time, 1, frames, input.unsafeMutablePointer) == noErr else {
            for b in out { if let d = b.mData { memset(d, 0, bytes) } }
            return noErr
        }

        if let block = renderBlock, let pull = pullBlock,
           block(flags, time, frames, 0, output, pull) == noErr {
            return noErr
        }
        // Pas de plugin (ou erreur) : l'entrée passe telle quelle.
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
