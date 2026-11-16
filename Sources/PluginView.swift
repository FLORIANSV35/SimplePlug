import AVFoundation
import AppKit
import CoreAudioKit

/// Récupère l'interface graphique d'un plugin AU :
/// 1. vue AUv3 (requestViewController), 2. vue Cocoa AUv2, 3. vue générique.
@MainActor
enum PluginView {
    static func make(for unit: AVAudioUnit) async -> NSView {
        let au = unit.auAudioUnit

        let controller: NSViewController? = await withCheckedContinuation { continuation in
            au.requestViewController { continuation.resume(returning: $0) }
        }
        if let view = controller?.view {
            if controller!.preferredContentSize != .zero {
                view.setFrameSize(controller!.preferredContentSize)
            }
            objc_setAssociatedObject(view, &controllerKey, controller, .OBJC_ASSOCIATION_RETAIN)
            return view
        }
        if let view = cocoaView(for: unit.audioUnit) { return view }

        let generic = AUGenericView(audioUnit: unit.audioUnit)
        generic.showsExpertParameters = false
        return generic
    }

    private static var controllerKey = 0

    /// Vue Cocoa fournie par un plugin AUv2 (kAudioUnitProperty_CocoaUI).
    private static func cocoaView(for unit: AudioUnit) -> NSView? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        guard AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &size, &writable) == noErr,
              size >= UInt32(MemoryLayout<AudioUnitCocoaViewInfo>.size) else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, raw, &size) == noErr else { return nil }

        let info = raw.load(as: AudioUnitCocoaViewInfo.self)
        let bundleURL = info.mCocoaAUViewBundleLocation.takeRetainedValue() as URL
        let className = info.mCocoaAUViewClass.takeRetainedValue() as String

        let selector = NSSelectorFromString("uiViewForAudioUnit:withSize:")
        guard let bundle = Bundle(url: bundleURL), bundle.load(),
              let factoryClass = bundle.classNamed(className) as? NSObject.Type,
              factoryClass.instancesRespond(to: selector) else { return nil }
        // AUCocoaUIBase n'est pas exposé en Swift : appel direct de -uiViewForAudioUnit:withSize:.
        let factory = factoryClass.init()
        typealias Factory = @convention(c) (AnyObject, Selector, AudioUnit, NSSize) -> Unmanaged<NSView>?
        let imp = unsafeBitCast(factory.method(for: selector), to: Factory.self)
        return imp(factory, selector, unit, NSSize(width: 800, height: 600))?.takeUnretainedValue()
    }
}
