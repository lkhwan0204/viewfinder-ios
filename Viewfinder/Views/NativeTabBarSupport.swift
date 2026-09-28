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
//  iOS 26 에서도 이 컨트롤러로 탭바를 숨기고 보입니다. (개선안 38)
//  시스템 줄이기(.tabBarMinimizeBehavior)는 끄고, 아래 VFTabBarScrollObserver 가
//  스크롤 방향을 보고 setHidden(_:animated:) 을 부릅니다. 경위는 그쪽 주석에 있습니다.
//  iOS 26 탭바는 탭을 누를 때 시스템 햅틱이 있으므로, 여기서 주는 햅틱은 iOS 17~18 에만 붙입니다.
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
        // iOS 26 탭바는 탭을 누를 때 시스템 햅틱이 이미 있습니다. 여기서 또 주면 두 번 울립니다.
        if #unavailable(iOS 26.0) {
            attachSelectionFeedback(to: tabBar)
        }

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
//  iOS 26: 스크롤 방향에 맞춰 탭바를 숨기고 다시 보입니다. (개선안 38)
//
//  [지나온 길]
//  1) .tabBarMinimizeBehavior(.onScrollDown)
//     내리면 탭바가 줄어들지만, 천천히 올려도 펼쳐지지 않고 맨 위에서만 펼쳐졌습니다.
//     (실기기 iOS 26 확인. 개발자 포럼 · Stack Overflow 에도 같은 증상이 보고되어 있습니다)
//  2) 스크롤 방향에 따라 .never ↔ .onScrollDown 을 바꿔 끼우기
//     실기기에서 동작하지 않았습니다. 이미 줄어든 탭바를 모드만 바꿔서 다시
//     펼쳐 준다는 보장이 없습니다. 문서에 없는 시스템 동작에 기댄 방법이었습니다.
//
//  [지금]
//  시스템 줄이기는 끄고(.never), 앱이 탭바를 직접 숨기고 보입니다.
//  숨기는 방법은 위의 NativeTabBarVisibilityController (탭바를 화면 아래로 밀기) 입니다.
//   - 탭바를 레이아웃에서 빼지 않고 밀기만 해서 화면 아래 여백이 바뀌지 않습니다.
//     SwiftUI 의 toolbar(.hidden, for: .tabBar) 는 여백이 바뀌어서, 홈처럼 화면 높이로
//     사진 크기를 정하는 화면이 스크롤 도중 출렁입니다.
//   - 아래로 16pt 내리면 숨고, 위로 8pt 올리면 보입니다. 속도가 아니라 누적 거리라서
//     천천히 올려도 보입니다. 맨 위 24pt 안에서는 늘 보입니다.
//   - 맨 위 · 맨 아래에서 튕기는 구간은 방향 판단에 쓰지 않습니다.
//   - 화면이 나타날 때 · 탭을 바꿀 때는 보이는 상태로 시작합니다.
//   - 보이스오버 · 스위치 제어를 쓰는 중에는 숨기지 않습니다. 숨은 탭바로는 갈 수 없습니다.
//
//  iOS 17~18 은 스크롤을 보고하지 않으므로 전과 같습니다. (탭바가 늘 보임)
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

/// 스크롤 한 번마다 탭바를 숨길지 정하는 규칙입니다.
///
/// 화면 · 시간 · UIKit 에 기대지 않는 값 타입이라, 이 코드를 그대로 떼어
/// 여러 스크롤 상황(천천히 올리기, 흔들림, 튕김, 짧은 화면 등)으로 검증할 수 있습니다.
struct VFTabBarAutoHideRule: Equatable, Sendable {
    /// 이만큼 아래로 내리면 숨깁니다.
    static let hideDistance: CGFloat = 16
    /// 이만큼 위로 올리면 보입니다. 숨기는 거리보다 짧게 두어 다시 부르기 쉽게 합니다.
    static let revealDistance: CGFloat = 8
    /// 맨 위에서 이 거리 안이면 늘 보입니다.
    static let topZone: CGFloat = 24

    private(set) var isHidden = false
    private var upwardDistance: CGFloat = 0
    private var downwardDistance: CGFloat = 0

    /// 스크롤 한 번을 반영합니다. 숨김 여부가 바뀌었으면 true.
    mutating func scrollChanged(from old: VFTabBarScrollSample, to new: VFTabBarScrollSample) -> Bool {
        // 맨 위 근처(당겨서 튕기는 구간 포함)와 화면보다 짧은 내용에서는 늘 보입니다.
        guard new.offset > Self.topZone, new.maxOffset > Self.topZone else {
            return reveal()
        }
        // 맨 아래에서 튕기는 구간은 방향 판단에 쓰지 않습니다.
        guard old.isWithinContent, new.isWithinContent else { return false }

        let delta = new.offset - old.offset
        if delta < 0 {
            upwardDistance += -delta
            downwardDistance = 0
            if upwardDistance >= Self.revealDistance {
                return setHidden(false)
            }
        } else if delta > 0 {
            downwardDistance += delta
            upwardDistance = 0
            if downwardDistance >= Self.hideDistance {
                return setHidden(true)
            }
        }
        return false
    }

    /// 보이는 상태로 되돌리고, 방향 판단을 처음부터 다시 합니다. 바뀌었으면 true.
    mutating func reveal() -> Bool {
        upwardDistance = 0
        downwardDistance = 0
        return setHidden(false)
    }

    private mutating func setHidden(_ hidden: Bool) -> Bool {
        guard isHidden != hidden else { return false }
        isHidden = hidden
        upwardDistance = 0
        downwardDistance = 0
        return true
    }
}

/// 스크롤 화면들이 보고한 스크롤로 탭바를 숨기고 보입니다. (iOS 26)
///
/// 탭바 상태는 앱 전체에 하나이므로 관찰자도 하나입니다.
/// 탭바를 보이게 하는 호출은 모두 여기(reveal)를 거쳐야 규칙과 실제 탭바가 어긋나지 않습니다.
@MainActor
final class VFTabBarScrollObserver {
    static let shared = VFTabBarScrollObserver()

    private var rule = VFTabBarAutoHideRule()

    private init() {}

    /// 세로 스크롤 위치가 바뀔 때마다 부릅니다. (vfReportsTabBarScroll)
    func scrollChanged(from old: VFTabBarScrollSample, to new: VFTabBarScrollSample) {
        // 보이스오버 · 스위치 제어로는 숨은 탭바로 갈 수 없으므로 숨기지 않습니다.
        guard !Self.isAssistiveNavigationRunning else {
            reveal()
            return
        }
        guard rule.scrollChanged(from: old, to: new) else { return }
        NativeTabBarVisibilityController.shared.setHidden(rule.isHidden, animated: Self.animatesChanges)
    }

    /// 탭바를 보이게 하고 방향 판단을 처음부터 다시 합니다.
    /// 화면이 나타날 때, 탭을 바꿀 때, 작성 화면을 열 때 부릅니다.
    func reveal() {
        _ = rule.reveal()
        // 규칙이 이미 "보임" 이어도 부릅니다. 다른 경로로 숨어 있던 탭바도 되돌립니다.
        // 이미 보이는 상태면 컨트롤러가 아무 것도 하지 않습니다.
        NativeTabBarVisibilityController.shared.setHidden(false, animated: Self.animatesChanges)
    }

    private static var isAssistiveNavigationRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    /// 동작 줄이기를 켠 사용자에게는 미끄러지는 움직임 없이 바로 바꿉니다.
    private static var animatesChanges: Bool {
        !UIAccessibility.isReduceMotionEnabled
    }
}

/// TabView 에 붙습니다. iOS 26 시스템 탭바 줄이기를 끕니다.
private struct VFTabBarSystemMinimizeDisabled: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 시스템 줄이기와 앱의 숨기기가 같은 탭바를 동시에 움직이지 않게 합니다.
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

private struct VFTabBarScrollReporter: ViewModifier {
    /// false 면 이 화면에서는 탭바를 숨기지 않습니다.
    let hidesTabBar: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .onScrollGeometryChange(for: VFTabBarScrollSample.self) { geometry in
                    VFTabBarScrollSample(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        maxOffset: geometry.contentSize.height
                            + geometry.contentInsets.top
                            + geometry.contentInsets.bottom
                            - geometry.containerSize.height
                    )
                } action: { oldValue, newValue in
                    guard hidesTabBar else { return }
                    VFTabBarScrollObserver.shared.scrollChanged(from: oldValue, to: newValue)
                }
                // 화면은 탭바가 보이는 상태로 시작합니다. 숨긴 채로 들어오면 탭을 바꿀 수 없습니다.
                .onAppear {
                    VFTabBarScrollObserver.shared.reveal()
                }
        } else {
            content
        }
    }
}

extension View {
    /// TabView 에 붙입니다. iOS 26 시스템 탭바 줄이기를 끕니다.
    /// 스크롤할 때 숨기고 보이는 것은 앱이 직접 합니다. (VFTabBarScrollObserver)
    func vfTabBarHidesOnScroll() -> some View {
        modifier(VFTabBarSystemMinimizeDisabled())
    }

    /// 탭 화면의 세로 ScrollView · List 에 붙입니다. (iOS 26)
    /// 아래로 내리면 탭바가 숨고, 위로 조금만 올려도 다시 보입니다.
    ///
    /// 붙인 화면은 탭바가 보이는 상태로 시작합니다. 탭 안에서 새로 밀어 넣는(push)
    /// 스크롤 화면에는 꼭 붙이세요. 붙이지 않으면 앞 화면에서 숨긴 탭바가 그대로 숨어 있습니다.
    ///
    /// - Parameter hidesTabBar: false 면 이 화면에서는 숨기지 않습니다.
    ///   아래에 입력창이 붙어 있어 탭바 자리가 비면 어색한 화면에 씁니다. (글 상세)
    func vfReportsTabBarScroll(hidesTabBar: Bool = true) -> some View {
        modifier(VFTabBarScrollReporter(hidesTabBar: hidesTabBar))
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
