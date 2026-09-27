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
//  iOS 26 에서는 이 컨트롤러를 탭바에 붙이지 않습니다. (개선안 38)
//  시스템 .tabBarMinimizeBehavior(.onScrollDown) 이 스크롤 축소를 맡고,
//  두 방식이 같은 탭바를 동시에 움직이지 않게 하기 위해서입니다.
//  아래 코드는 iOS 17~18 에서만 동작합니다.
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

// ─────────────────────────────────────────────────────────────────
//  탭바를 불투명 surface2 로 (시도 A)
//
//  AppDelegate 의 UITabBarAppearance 설정이 iOS 26 플로팅 탭바에
//  적용되지 않았습니다. toolbarBackground 는 appearance 프록시가 아니라
//  SwiftUI 가 자기 바 렌더링에 직접 거는 경로라 별개의 시도입니다.
//
//  두 가지를 짝으로 씁니다.
//   toolbarBackground           어떤 색으로 그릴지          iOS 16+
//   toolbarBackgroundVisibility 그리긴 그리라는 지시        iOS 18+
//  색만 지정하고 가시성이 자동(스크롤에 따라 숨김)이면 색이 무의미해집니다.
//
//  배포 타깃이 17.0 이라 가시성 쪽은 가용성 분기가 필요하고,
//  분기를 뷰 본문에 직접 쓰면 TabView 체인이 지저분해지므로 감쌉니다.
// ─────────────────────────────────────────────────────────────────
private struct VFOpaqueTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26 은 시스템 Liquid Glass 탭바를 그대로 씁니다. (개선안 38)
            // 불투명 배경을 강제해도 확실히 적용되지 않았고,
            // 시스템 재질과 싸우면 화면마다 탭바 색이 달라졌습니다.
            content
        } else if #available(iOS 18.0, *) {
            content
                .toolbarBackground(Color(uiColor: VFPalette.surface2), for: .tabBar)
                .toolbarBackgroundVisibility(.visible, for: .tabBar)
        } else {
            content
                .toolbarBackground(Color(uiColor: VFPalette.surface2), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

extension View {
    /// 탭바 배경을 앱 크롬 색(surface2)으로 고정합니다.
    ///
    /// TabView 컨테이너와 각 탭 루트 양쪽에 붙입니다.
    /// 툴바 배경은 내비게이션 바처럼 "지금 선택된 탭의 콘텐츠" 기준으로
    /// 해석되기 때문에, 컨테이너에만 걸면 무시되고 자식에 걸어야 반영되는
    /// 경우가 있습니다. 한 번의 빌드로 판정하기 위해 양쪽 다 겁니다.
    func vfOpaqueTabBar() -> some View {
        modifier(VFOpaqueTabBar())
    }
}

// ─────────────────────────────────────────────────────────────────
//  iOS 26: 스크롤 방향에 맞춰 탭바를 줄이고 다시 펼칩니다. (개선안 38)
//
//  [문제였던 상황]
//  .tabBarMinimizeBehavior(.onScrollDown) 만 걸었더니, 스크롤을 내리면
//  탭바가 줄어들지만 천천히 다시 올려도 펼쳐지지 않았습니다.
//  맨 위까지 올라가야만 펼쳐졌습니다. (실기기 iOS 26 확인.
//  같은 증상이 개발자 포럼·Stack Overflow 에도 보고되어 있습니다)
//
//  [해결]
//  탭 화면의 세로 스크롤을 직접 보고, 방향이 바뀌는 순간 동작을 바꿉니다.
//   - 위로 8pt 이상 올리면   .never        시스템이 탭바를 바로 펼칩니다.
//   - 아래로 16pt 이상 내리면 .onScrollDown 시스템이 다시 줄입니다.
//  속도가 아니라 누적 거리로 판단하므로 천천히 올려도 펼쳐집니다.
//  맨 위·맨 아래에서 튕기는 구간은 방향 판단에서 빼서 깜빡이지 않게 합니다.
//
//  시작 값은 .never(펼침)입니다. 실행 직후부터 .onScrollDown 이면
//  첫 탭이 잠깐 보였다가 바뀌는 문제가 보고되어 있고, .never 로 시작해
//  나중에 바꾸면 생기지 않는다고 합니다. 첫 스크롤을 내릴 때 바뀝니다.
//
//  iOS 17~18 에서는 아무 것도 하지 않습니다.
// ─────────────────────────────────────────────────────────────────

/// 세로 스크롤 위치 한 번의 기록입니다.
struct VFTabBarScrollSample: Equatable, Sendable {
    /// 맨 위가 0 입니다. (contentOffset.y + contentInsets.top)
    let offset: CGFloat
    /// 맨 아래에 닿았을 때의 offset 입니다.
    let maxOffset: CGFloat

    /// 맨 위보다 위, 맨 아래보다 아래로 튕기는 구간이 아닌지.
    var isWithinContent: Bool {
        offset >= 0 && offset <= maxOffset
    }
}

@MainActor
final class VFTabBarScrollObserver: ObservableObject {
    static let shared = VFTabBarScrollObserver()

    /// 이만큼 위로 올리면 탭바를 펼칩니다. 속도와 무관한 누적 거리입니다.
    static let expandDistance: CGFloat = 8
    /// 이만큼 아래로 내리면 시스템이 다시 탭바를 줄일 수 있게 합니다.
    /// 펼치는 거리보다 길게 두어, 손가락을 뗄 때의 작은 흔들림에 반응하지 않게 합니다.
    static let minimizeDistance: CGFloat = 16

    /// true: 탭바를 펼쳐 둡니다(.never).  false: 스크롤을 내리면 줄어듭니다(.onScrollDown).
    @Published private(set) var keepsTabBarExpanded = true

    private var upwardDistance: CGFloat = 0
    private var downwardDistance: CGFloat = 0

    private init() {}

    func scrollChanged(from old: VFTabBarScrollSample, to new: VFTabBarScrollSample) {
        // 내용이 화면보다 짧으면 줄어들 일이 없습니다. 가로 레일도 여기서 걸러집니다.
        guard new.maxOffset > 1 else { return }
        // 튕기는 구간은 방향 판단에 쓰지 않습니다.
        guard old.isWithinContent, new.isWithinContent else { return }

        let delta = new.offset - old.offset
        if delta < 0 {
            upwardDistance += -delta
            downwardDistance = 0
            if upwardDistance >= Self.expandDistance {
                setKeepsTabBarExpanded(true)
            }
        } else if delta > 0 {
            downwardDistance += delta
            upwardDistance = 0
            if downwardDistance >= Self.minimizeDistance {
                setKeepsTabBarExpanded(false)
            }
        }
    }

    private func setKeepsTabBarExpanded(_ value: Bool) {
        // 방향이 바뀔 때만 알립니다. 스크롤할 때마다 화면을 다시 그리지 않습니다.
        guard keepsTabBarExpanded != value else { return }
        keepsTabBarExpanded = value
    }
}

private struct VFTabBarMinimizeOnScroll: ViewModifier {
    @ObservedObject private var scrollObserver = VFTabBarScrollObserver.shared

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(
                scrollObserver.keepsTabBarExpanded ? .never : .onScrollDown
            )
        } else {
            content
        }
    }
}

private struct VFTabBarScrollReporter: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.onScrollGeometryChange(for: VFTabBarScrollSample.self) { geometry in
                VFTabBarScrollSample(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    maxOffset: geometry.contentSize.height
                        + geometry.contentInsets.top
                        + geometry.contentInsets.bottom
                        - geometry.containerSize.height
                )
            } action: { oldValue, newValue in
                VFTabBarScrollObserver.shared.scrollChanged(from: oldValue, to: newValue)
            }
        } else {
            content
        }
    }
}

extension View {
    /// TabView 에 붙입니다. iOS 26 에서만 스크롤 방향에 맞춰 탭바를 줄이고 펼칩니다.
    func vfTabBarMinimizeOnScroll() -> some View {
        modifier(VFTabBarMinimizeOnScroll())
    }

    /// 탭 화면의 세로 ScrollView 에 붙입니다. 위로 올리는 순간 탭바가 다시 펼쳐집니다.
    /// 붙이지 않은 화면은 시스템 기본 동작(맨 위에서만 펼침)을 따릅니다.
    func vfReportsTabBarScroll() -> some View {
        modifier(VFTabBarScrollReporter())
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
