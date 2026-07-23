import UIKit
import ObjectiveC

/// Global pointer-lock preference. SwiftUI's hosting controller ignores nested
/// `prefersPointerLocked` children, so we swizzle `UIViewController` so the
/// active hierarchy reports the game's preference.
enum PointerLockBridge {
    static var wantsLock = false {
        didSet {
            guard wantsLock != oldValue else { return }
            refresh()
        }
    }

    private static var didInstall = false

    static func installIfNeeded() {
        guard !didInstall else { return }
        didInstall = true

        let originalSelector = #selector(getter: UIViewController.prefersPointerLocked)
        let swizzledSelector = #selector(UIViewController.desert_prefersPointerLocked)

        guard
            let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    static func refresh() {
        installIfNeeded()
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.rootViewController?.desert_propagatePointerLockUpdate()
                }
                // Force the scene to re-evaluate lock requirements (fullscreen, click, etc.).
                windowScene.setNeedsUpdateOfPrefersPointerLocked()
            }
        }
    }

    static var isSystemLocked: Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.pointerLockState?.isLocked == true {
                return true
            }
        }
        return false
    }
}

extension UIViewController {
    @objc func desert_prefersPointerLocked() -> Bool {
        if PointerLockBridge.wantsLock {
            return true
        }
        // After exchange, this invokes the original UIKit implementation.
        return desert_prefersPointerLocked()
    }

    fileprivate func desert_propagatePointerLockUpdate() {
        setNeedsUpdateOfPrefersPointerLocked()
        children.forEach { $0.desert_propagatePointerLockUpdate() }
        presentedViewController?.desert_propagatePointerLockUpdate()
    }
}

extension UIWindowScene {
    fileprivate func setNeedsUpdateOfPrefersPointerLocked() {
        windows.forEach { $0.rootViewController?.desert_propagatePointerLockUpdate() }
    }
}
