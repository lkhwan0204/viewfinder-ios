import FirebaseCore
import GoogleSignIn
import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────
//  Phase 1 리디자인 노트
//
//  1. 다크 모드를 기본으로 확정했습니다.
//     사진 앱에서 다크는 취향이 아니라 광학입니다.
//     흰 배경은 사진의 밝은 영역과 경쟁해서 다이내믹 레인지를 눌러버립니다.
//     야경(반포대교, 성수구름다리)과 무채색 필름 사진이 라이브러리의 절반인
//     이 앱에서는 검정 배경에서 사진이 확연히 살아납니다.
//     또한 Liquid Glass 는 배경 콘텐츠가 아름다울 때 아름다워지므로
//     다크 전환은 Phase 3 의 전제 조건입니다.
//
//  2. 탭바 선택 상태에 브랜드 앰버를 적용했습니다.
//     기존에는 선택색이 흰색/검정이라 "지금 어디인지" 순간 판별이 어려웠습니다.
//
//  3. 탭바 배경을 canvas 와 같은 색으로 두고 hairline 을 제거했습니다.
//     크롬을 줄이고 아이콘만 떠 있게 만드는 것이 콘텐츠 중심 디자인입니다.
//
//  라이트 모드를 검증하려면 preferredColorScheme 줄을 잠시 주석 처리하세요.
//  (AppColors / VFPalette 는 라이트 값도 모두 정의되어 있습니다)
// ─────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        configureImageCache()

        configureTabBarAppearance()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// AsyncImage 는 URLSession.shared 를 쓰고, 그 캐시는 URLCache.shared 입니다.
    /// 기본 용량이 작아서 스크롤을 위아래로 되돌릴 때마다 사진을 다시 내려받습니다.
    /// 사진이 주인공인 앱이므로 캐시를 넉넉히 잡습니다.
    private func configureImageCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()

        // Phase 1 에서는 불투명 유지가 의도입니다.
        // 스크롤 콘텐츠가 탭바 뒤에서 반투명하게 읽히는 문제를 확실히 차단합니다.
        // Phase 3 에서 Liquid Glass + 콘텐츠 하단 inset 을 함께 도입할 때
        // 투명 재료로 전환합니다.
        appearance.configureWithOpaqueBackground()

        // backgroundEffect 를 명시적으로 지웁니다.
        //
        // configureWithOpaqueBackground() 는 시스템 블러를 넣습니다.
        // iOS 26 플로팅 탭바는 그 블러를 자체 유리 재질로 처리하면서
        // backgroundColor 를 사실상 무시했습니다. 그래서 밝은 지도 위에서
        // 탭바가 밝은 회색이 되고, 검정 배경 화면에서는 어두워졌습니다.
        // 같은 탭바가 화면마다 다른 색이었습니다.
        //
        // effect 를 nil 로 두면 backgroundColor 가 그대로 칠해집니다.
        appearance.backgroundEffect = nil

        // 캔버스(#000000) 대신 surface2(#1C1C1F).
        //
        // 캔버스 색으로 두면 검정 배경 화면에서 탭바가 배경과 같은 색이
        // 되어 경계가 사라집니다. 탭바는 컨트롤이므로 한 단계 올라온
        // 표면을 씁니다. 마이 탭에서 정한 규칙과 같습니다.
        // 지도 위 컨트롤(MapChrome.surface)도 같은 값이라 두 크롬이
        // 같은 색으로 보입니다.
        appearance.backgroundColor = VFPalette.surface2
        // hairline 제거. 크롬을 줄입니다.
        appearance.shadowColor = .clear

        let itemAppearance = UITabBarItemAppearance()

        let unselectedColor = AppColors.uiSecondaryText.withAlphaComponent(0.70)
        itemAppearance.normal.iconColor = unselectedColor
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: unselectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        // 선택 상태 = 브랜드 앰버.
        itemAppearance.selected.iconColor = AppColors.uiAccent
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: AppColors.uiAccent,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        // Hero 페이지 인디케이터. 사진 위에 놓이므로 흰색 기준입니다.
        UIPageControl.appearance().currentPageIndicatorTintColor = .white
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.34)

        UITabBar.appearance().tintColor = AppColors.uiAccent
        UITabBar.appearance().unselectedItemTintColor = unselectedColor
    }
}

@main
struct ViewfinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppColors.accent)
                .preferredColorScheme(.dark)
        }
    }
}
