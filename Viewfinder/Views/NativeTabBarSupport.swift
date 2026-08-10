import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────
//  Phase 1 리디자인 노트 — 탭바 관통 버그 수정
//
//  [문제]
//  기존 구현은 스크롤에 따라 tabBar.alpha 를 0...1 로 조절했습니다.
//  탭바 배경이 불투명(configureWithOpaqueBackground)이기 때문에
//  alpha 가 중간값(예: 0.4)일 때 배경까지 반투명해져서
//  뒤의 본문 텍스트가 유령처럼 관통해 보였습니다.
//  스크린샷에서 탭바 아래에 "저장한 장소가 아직 없어요" 가 겹쳐 읽힌 원인입니다.
//
//  [수정]
//  alpha 를 건드리지 않고 수직으로 밀어냅니다. (translateY)
//  탭바는 항상 alpha = 1 이므로 반투명 중간 상태가 존재하지 않습니다.
//  숨을 때는 화면 아래로 완전히 빠지고, 나타날 때는 다시 올라옵니다.
//
//  공개 API 는 그대로 유지했습니다. (ContentView 수정 불필요)
//   - attach(_:)
//   - setHorizontalOffset(_:animated:)
//   - updateInteraction(by:)
//   - finishInteraction(projectedDelta:)
//   - setHidden(_:animated:)
//
//  Phase 3 에서 iOS 26 의 .tabBarMinimizeBehavior(.onScrollDown) 로
//  이 파일 대부분을 대체할 예정입니다.
// ─────────────────────────────────────────────────────────────────

final class NativeTabBarVisibilityController: NSObject {
    static let shared = NativeTabBarVisibilityController()

    private weak var tabBar: UITabBar?
    private var currentHiddenState = false
    private var horizontalOffset: CGFloat = 0
    /// 0 = 완전히 보임, 1 = 화면 아래로 완전히 숨음
    private var hideProgress: CGFloat = 0
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
        // alpha 는 항상 1 로 고정합니다. 이것이 관통 버그 수정의 핵심입니다.
        tabBar.alpha = 1
        attachSelectionFeedback(to: tabBar)

        if animator == nil, !isInteracting {
            hideProgress = currentHiddenState ? 1 : 0
        }
        tabBar.transform = tabBarTransform
        tabBar.isUserInteractionEnabled = hideProgress < 0.5
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
            // 진행 중인 애니메이션을 현재 위치에서 인수합니다.
            hideProgress = presentedHideProgress(for: tabBar)
            animator?.stopAnimation(true)
            animator = nil
            tabBar.layer.removeAllAnimations()
            tabBar.alpha = 1
            tabBar.transform = tabBarTransform
            isInteracting = true
        }

        // 아래로 스크롤(음수 delta) 하면 숨고, 위로 스크롤하면 나타납니다.
        let progressDelta = verticalDelta / interactionDistance
        hideProgress = min(max(hideProgress - progressDelta, 0), 1)

        tabBar.transform = tabBarTransform
        tabBar.isUserInteractionEnabled = hideProgress < 0.5
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
            shouldHide = hideProgress > 0.5
        }

        _ = tabBar
        setHidden(shouldHide, animated: true)
    }

    func setHidden(_ isHidden: Bool, animated: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setHidden(isHidden, animated: animated)
            }
            return
        }

        let targetProgress: CGFloat = isHidden ? 1 : 0
        guard let tabBar else {
            currentHiddenState = isHidden
            hideProgress = targetProgress
            return
        }

        let startingProgress = presentedHideProgress(for: tabBar)
        guard currentHiddenState != isHidden || abs(startingProgress - targetProgress) > 0.01 else {
            return
        }

        currentHiddenState = isHidden
        isInteracting = false

        tabBar.isHidden = false
        tabBar.alpha = 1

        if !isHidden {
            tabBar.isUserInteractionEnabled = true
        }

        animator?.stopAnimation(true)
        tabBar.layer.removeAllAnimations()
        hideProgress = startingProgress
        tabBar.transform = tabBarTransform

        guard animated, abs(startingProgress - targetProgress) > 0.01 else {
            hideProgress = targetProgress
            tabBar.transform = tabBarTransform
            tabBar.isUserInteractionEnabled = !isHidden
            return
        }

        let timing = UISpringTimingParameters(dampingRatio: 0.88)
        let remainingDistance = abs(targetProgress - startingProgress)
        let tabBarAnimator = UIViewPropertyAnimator(
            duration: max(0.18, 0.34 * remainingDistance),
            timingParameters: timing
        )
        tabBarAnimator.addAnimations { [weak self, weak tabBar] in
            guard let self, let tabBar else { return }
            self.hideProgress = targetProgress
            tabBar.transform = self.tabBarTransform
        }
        tabBarAnimator.addCompletion { [weak self, weak tabBar, weak tabBarAnimator] _ in
            guard let self,
                  let tabBar,
                  let tabBarAnimator,
                  self.animator === tabBarAnimator,
                  self.currentHiddenState == isHidden else { return }
            self.hideProgress = targetProgress
            tabBar.transform = self.tabBarTransform
            tabBar.isUserInteractionEnabled = !isHidden
            self.animator = nil
        }
        animator = tabBarAnimator
        tabBarAnimator.startAnimation()
    }

    // MARK: - Geometry

    private var tabBarTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: horizontalOffset,
            y: hideProgress * hiddenDistance
        )
    }

    /// 탭바가 화면 밖으로 완전히 빠지기 위한 거리.
    private var hiddenDistance: CGFloat {
        guard let tabBar else { return 96 }
        let barHeight = max(tabBar.bounds.height, 49)
        let bottomInset = tabBar.window?.safeAreaInsets.bottom ?? 0
        return barHeight + bottomInset
    }

    /// 애니메이션 중이라면 화면에 실제로 보이는 위치를 읽어 진행률로 환산합니다.
    private func presentedHideProgress(for tabBar: UITabBar) -> CGFloat {
        let distance = hiddenDistance
        guard distance > 0 else { return hideProgress }

        if let presentation = tabBar.layer.presentation() {
            let translationY = presentation.transform.m42
            return min(max(translationY / distance, 0), 1)
        }

        return hideProgress
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
