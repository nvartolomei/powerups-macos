import Cocoa
import CoreAudio
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXActionConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXError

/// Routes system audio output to a named device.
/// CoreAudio handles whatever it can enumerate (built-in speakers, connected Bluetooth like AirPods): a silent,
/// instant switch. AirPlay endpoints (e.g. "LSX") aren't enumerable via CoreAudio until already selected, and
/// neither are disconnected AirPods, so for those we fall back to clicking through Control Center by hand.
class AudioOutput {
    private static let controlCenterBundleId = "com.apple.controlcenter"
    /// menu bar extras that open a panel listing outputs; Sound jumps straight there, Control Center needs one more step
    private static let soundNames = ["Sound"]
    private static let controlCenterNames = ["Control Center", "Control Centre"]
    /// no AppKit constant is exposed for the status-item menu bar
    private static let extrasMenuBarAttribute = "AXExtrasMenuBar"
    private static let maxDepth = 16
    private static let pollAttempts = 20
    private static let pollInterval = useconds_t(50_000)

    static func route(to deviceName: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            if setDefaultOutput(matching: deviceName) {
                Logger.info { "routed audio to \(deviceName) via CoreAudio" }
                return
            }
            do { try switchOutput(to: deviceName) }
            catch { Logger.error { "failed to route audio to \(deviceName): \(error)" } }
        }
    }

    private static func switchOutput(to deviceName: String) throws {
        guard let app = controlCenterApp() else {
            Logger.error { "ControlCenter app not running" }
            return
        }
        guard let opener = opener(in: app) else {
            Logger.error { "no Sound/Control Center menu bar extra found" }
            return
        }
        let viaSound = soundNames.contains { matches(opener, $0) }
        try opener.performAction(kAXPressAction)
        guard let device = device(named: deviceName, in: app, expandingSound: !viaSound) else {
            Logger.error { "device \"\(deviceName)\" not found in Control Center" }
            logTree(app)
            return
        }
        try press(device)
        dismiss(app, opener)
    }

    private static func device(named deviceName: String, in app: AXUIElement, expandingSound: Bool) -> AXUIElement? {
        if let device = waitForElement(in: app, named: [deviceName]) { return device }
        guard expandingSound, let sound = waitForElement(in: app, named: soundNames) else { return nil }
        try? press(sound)
        return waitForElement(in: app, named: [deviceName])
    }

    private static func controlCenterApp() -> AXUIElement? {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: controlCenterBundleId).first else { return nil }
        return AXUIElementCreateApplication(running.processIdentifier)
    }

    private static func opener(in app: AXUIElement) -> AXUIElement? {
        guard let extrasBar = app.rawElement(extrasMenuBarAttribute) else { return nil }
        let extras = extrasBar.rawElements(kAXChildrenAttribute)
        return extra(in: extras, named: soundNames) ?? extra(in: extras, named: controlCenterNames)
    }

    private static func extra(in extras: [AXUIElement], named names: [String]) -> AXUIElement? {
        extras.first { item in names.contains { matches(item, $0) } }
    }

    private static func waitForElement(in app: AXUIElement, named names: [String]) -> AXUIElement? {
        for _ in 0..<pollAttempts {
            for window in app.rawElements(kAXWindowsAttribute) {
                if let found = findDescendant(in: window, named: names, depth: maxDepth) { return found }
            }
            usleep(pollInterval)
        }
        return nil
    }

    private static func findDescendant(in element: AXUIElement, named names: [String], depth: Int) -> AXUIElement? {
        if names.contains(where: { matches(element, $0) }) { return element }
        guard depth > 0 else { return nil }
        for child in element.rawElements(kAXChildrenAttribute) {
            if let found = findDescendant(in: child, named: names, depth: depth - 1) { return found }
        }
        return nil
    }

    private static func matches(_ element: AXUIElement, _ name: String) -> Bool {
        [element.rawString(kAXTitleAttribute), element.rawString(kAXDescriptionAttribute)]
            .contains { $0?.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func press(_ element: AXUIElement) throws {
        try (pressable(element) ?? element).performAction(kAXPressAction)
    }

    /// the matched node may be a label; walk up to the nearest ancestor that actually accepts a press
    private static func pressable(_ element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            if supportsPress(candidate) { return candidate }
            current = candidate.rawElement(kAXParentAttribute)
        }
        return nil
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return false }
        return (names as? [String])?.contains(kAXPressAction) ?? false
    }

    /// selecting a device usually leaves the panel open; close it, but only if it didn't already dismiss itself
    private static func dismiss(_ app: AXUIElement, _ opener: AXUIElement) {
        usleep(pollInterval)
        guard !app.rawElements(kAXWindowsAttribute).isEmpty else { return }
        try? opener.performAction(kAXPressAction)
    }

    /// dumped to the error log when a device can't be found, so the names above can be tuned against the real tree
    private static func logTree(_ app: AXUIElement) {
        for window in app.rawElements(kAXWindowsAttribute) {
            Logger.error { "Control Center AX tree:\n" + describe(window, depth: maxDepth, indent: 0) }
        }
    }

    private static func describe(_ element: AXUIElement, depth: Int, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let role = element.rawString(kAXRoleAttribute) ?? "?"
        let title = element.rawString(kAXTitleAttribute) ?? ""
        let desc = element.rawString(kAXDescriptionAttribute) ?? ""
        var line = "\(pad)\(role) title=\"\(title)\" desc=\"\(desc)\"\n"
        guard depth > 0 else { return line }
        for child in element.rawElements(kAXChildrenAttribute) {
            line += describe(child, depth: depth - 1, indent: indent + 1)
        }
        return line
    }
}

/// CoreAudio: a silent, instant default-output switch for any device the system can already enumerate
private extension AudioOutput {
    static var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    static func setDefaultOutput(matching name: String) -> Bool {
        guard let id = outputDevice(matching: name) else { return false }
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        var deviceId = id
        return AudioObjectSetPropertyData(systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceId) == noErr
    }

    /// exact name wins; otherwise a substring, so "MacBook" reaches "MacBook Pro Speakers" and "AirPods" reaches "AirPods Pro"
    static func outputDevice(matching name: String) -> AudioDeviceID? {
        let devices = outputDevices()
        return devices.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            ?? devices.first { $0.name.range(of: name, options: .caseInsensitive) != nil }?.id
    }

    static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputChannels(id), let name = deviceName(id) else { return nil }
            return (id, name)
        }
    }

    static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let cf = name else { return nil }
        return cf.takeRetainedValue() as String
    }

    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

/// raw single-attribute reads: AudioOutput needs attributes (AXExtrasMenuBar, AXDescription, AXParent as element)
/// that the shared AXUIElement.attributes(_:) helper doesn't cover
private extension AXUIElement {
    func rawString(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func rawElement(_ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func rawElements(_ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
