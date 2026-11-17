import AppKit
import ApplicationServices

final class FinderFolderOpening {
    enum Status {
        case off, needsAccessibility, unavailable, active
    }

    private static let finderID = "com.apple.finder"
    private static let settingsKey = "openFinderFoldersInQingFiles"
    private let openFolder: (URL) -> Void
    private let canOpen: () -> Bool
    private let system = AXUIElementCreateSystemWide()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var finderPID: pid_t?
    private var pending: (url: URL, point: CGPoint)?
    private var observers: [NSObjectProtocol] = []
    private(set) var status = Status.off

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.settingsKey) }

    init(canOpen: @escaping () -> Bool, openFolder: @escaping (URL) -> Void) {
        self.canOpen = canOpen
        self.openFolder = openFolder
        AXUIElementSetMessagingTimeout(system, 0.12)
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.finderID else { return }
                self?.refresh()
            })
        }
        refresh()
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        disconnect()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.settingsKey)
        if enabled, !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        refresh()
    }

    func refresh() {
        guard isEnabled else { disconnect(); status = .off; return }
        guard AXIsProcessTrusted() else { disconnect(); status = .needsAccessibility; return }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderID)
            .first(where: { !$0.isTerminated })?.processIdentifier else {
            disconnect()
            status = .unavailable
            return
        }
        if finderPID == pid, let tap, CGEvent.tapIsEnabled(tap: tap) {
            status = .active
            return
        }
        disconnect()
        let mask = [CGEventType.leftMouseDown, .leftMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let opening = Unmanaged<FinderFolderOpening>.fromOpaque(pointer).takeUnretainedValue()
            return opening.filter(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            status = .unavailable
            return
        }
        self.tap = tap
        self.source = source
        finderPID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        status = .active
    }

    private func disconnect() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        finderPID = nil
        pending = nil
    }

    private func filter(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            pending = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .leftMouseUp, let pending {
            self.pending = nil
            let point = event.location
            if abs(point.x - pending.point.x) <= 4, abs(point.y - pending.point.y) <= 4 {
                DispatchQueue.main.async { [weak self] in self?.openFolder(pending.url) }
            }
            return true
        }
        guard type == .leftMouseDown else { return false }
        pending = nil
        let modifiers: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]
        guard event.getIntegerValueField(.mouseEventClickState) == 2,
              event.flags.intersection(modifiers).isEmpty, canOpen(),
              let url = folder(at: event.location) else { return false }
        pending = (url, event.location)
        // Consume the matching mouse-up before activating QingFiles.
        return true
    }

    private func folder(at point: CGPoint) -> URL? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid == finderPID else { return nil }
        let role: String? = attribute(hit, kAXRoleAttribute)
        var url: URL? = attribute(hit, kAXURLAttribute)
        if url == nil, role == kAXImageRole, let parent: AXUIElement = attribute(hit, kAXParentAttribute),
           attribute(parent, kAXRoleAttribute) as String? == kAXCellRole {
            let children: [AXUIElement] = attribute(parent, kAXChildrenAttribute) ?? []
            url = children.lazy.compactMap { self.attribute($0, kAXURLAttribute) as URL? }.first
        }
        guard let url, url.isFileURL, url.hasDirectoryPath,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isVolumeKey]),
              values.isDirectory == true, values.isPackage != true, values.isVolume != true else { return nil }
        return url
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
