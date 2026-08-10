import SwiftUI
import UIKit

final class NativeTabBarVisibilityController: NSObject {
    static let shared = NativeTabBarVisibilityController()

    private weak var tabBar: UITabBar?
    private var currentHiddenState = false
    private var horizontalOffset: CGFloat = 0
    private var animator: UIViewPropertyAnimator?
    private var isInteracting = false
    private let interactionDistance: CGFloat = 96
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    private override init() {
        super.init()
    }

    func attach(_ tabBar: UITabBar) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak tabBar] in
                guard let tabBar else { return }
                self?.attach(tabBar)
            }
            return
        }

        self.tabBar = tabBar
        tabBar.isHidden = false
        tabBar.transform = tabBarTransform
        attachSelectionFeedback(to: tabBar)
        if animator == nil, !isInteracting {
            applyTabBarState(tabBar, isHidden: currentHiddenState)
        }
        tabBar.isUserInteractionEnabled = !currentHiddenState
    }

    private func attachSelectionFeedback(to tabBar: UITabBar) {
        tabBar.descendantControls.forEach { control in
            control.removeTarget(self, action: #selector(tabBarItemTouched), for: .touchDown)
            control.addTarget(self, action: #selector(tabBarItemTouched), for: .touchDown)
        }
    }

    @objc
    private func tabBarItemTouched() {
        selectionFeedbackGenerator.prepare()
        selectionFeedbackGenerator.selectionChanged()
    }

    func setHorizontalOffset(_ offset: CGFloat, animated: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setHorizontalOffset(offset, animated: animated)
            }
            return
        }

        horizontalOffset = offset
        guard let tabBar else { return }

        let changes = { [weak self, weak tabBar] in
            guard let self, let tabBar else { return }
            tabBar.transform = self.tabBarTransform
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    func updateInteraction(by verticalDelta: CGFloat) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateInteraction(by: verticalDelta)
            }
            return
        }

        guard abs(verticalDelta) > 0.05, let tabBar else { return }

        if !isInteracting {
            let startingAlpha = (tabBar.layer.presentation()?.opacity).map { CGFloat($0) } ?? tabBar.alpha
            animator?.stopAnimation(true)
            animator = nil
            tabBar.layer.removeAllAnimations()
            tabBar.alpha = startingAlpha
            isInteracting = true
        }

        let alphaDelta = verticalDelta / interactionDistance
        tabBar.alpha = min(max(tabBar.alpha + alphaDelta, 0), 1)
        tabBar.isUserInteractionEnabled = tabBar.alpha > 0.25
    }

    func finishInteraction(projectedDelta: CGFloat) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.finishInteraction(projectedDelta: projectedDelta)
            }
            return
        }

        guard isInteracting, let tabBar else { return }
        isInteracting = false

        let shouldHide: Bool
        if projectedDelta < -12 {
            shouldHide = true
        } else if projectedDelta > 12 {
            shouldHide = false
        } else {
            shouldHide = tabBar.alpha < 0.5
        }

        setHidden(shouldHide, animated: true)
    }

    func setHidden(_ isHidden: Bool, animated: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setHidden(isHidden, animated: animated)
            }
            return
        }

        let targetAlpha: CGFloat = isHidden ? 0 : 1
        let visibleAlpha = tabBar.map {
            CGFloat($0.layer.presentation()?.opacity ?? Float($0.alpha))
        } ?? targetAlpha
        guard currentHiddenState != isHidden || abs(visibleAlpha - targetAlpha) > 0.01 else {
            return
        }

        currentHiddenState = isHidden
        isInteracting = false

        guard let tabBar else { return }
        tabBar.isHidden = false
        tabBar.transform = tabBarTransform

        if !isHidden {
            tabBar.isUserInteractionEnabled = true
        }

        let startingAlpha = (tabBar.layer.presentation()?.opacity).map { CGFloat($0) } ?? tabBar.alpha
        animator?.stopAnimation(true)
        tabBar.layer.removeAllAnimations()
        tabBar.alpha = startingAlpha

        guard animated, abs(startingAlpha - targetAlpha) > 0.01 else {
            applyTabBarState(tabBar, isHidden: isHidden)
            tabBar.isUserInteractionEnabled = !isHidden
            return
        }

        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.22, y: 0.61),
            controlPoint2: CGPoint(x: 0.36, y: 1.0)
        )
        let remainingDistance = abs(targetAlpha - startingAlpha)
        let tabBarAnimator = UIViewPropertyAnimator(
            duration: max(0.16, (isHidden ? 0.28 : 0.32) * remainingDistance),
            timingParameters: timing
        )
        tabBarAnimator.addAnimations { [weak self, weak tabBar] in
            guard let self, let tabBar else { return }
            self.applyTabBarState(tabBar, isHidden: isHidden)
        }
        tabBarAnimator.addCompletion { [weak self, weak tabBar, weak tabBarAnimator] _ in
            guard let self,
                  let tabBar,
                  let tabBarAnimator,
                  self.animator === tabBarAnimator,
                  self.currentHiddenState == isHidden else { return }
            self.applyTabBarState(tabBar, isHidden: isHidden)
            tabBar.isUserInteractionEnabled = !isHidden
            self.animator = nil
        }
        animator = tabBarAnimator
        tabBarAnimator.startAnimation()
    }

    private func applyTabBarState(_ tabBar: UITabBar, isHidden: Bool) {
        tabBar.transform = tabBarTransform
        tabBar.alpha = isHidden ? 0 : 1
    }

    private var tabBarTransform: CGAffineTransform {
        CGAffineTransform(translationX: horizontalOffset, y: 0)
    }
}

struct NativeTabBarAnimator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        viewController.view.isUserInteractionEnabled = false
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let tabBarController = uiViewController.nearestTabBarController {
            NativeTabBarVisibilityController.shared.attach(tabBarController.tabBar)
        } else {
            DispatchQueue.main.async {
                guard let tabBarController = uiViewController.nearestTabBarController else { return }
                NativeTabBarVisibilityController.shared.attach(tabBarController.tabBar)
            }
        }
    }
}

private extension UIViewController {
    var nearestTabBarController: UITabBarController? {
        if let tabBarController {
            return tabBarController
        }

        var parentViewController = parent
        while let viewController = parentViewController {
            if let tabBarController = viewController as? UITabBarController {
                return tabBarController
            }
            parentViewController = viewController.parent
        }

        return view.window?.rootViewController?.findTabBarController()
    }

    func findTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }

        for child in children {
            if let tabBarController = child.findTabBarController() {
                return tabBarController
            }
        }

        return presentedViewController?.findTabBarController()
    }
}

private extension UIView {
    var descendantControls: [UIControl] {
        subviews.reduce(into: []) { controls, subview in
            if let control = subview as? UIControl {
                controls.append(control)
            }
            controls.append(contentsOf: subview.descendantControls)
        }
    }
}
