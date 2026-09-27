import FirebaseCore
import GoogleSignIn
import SwiftUI
import UIKit

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

        if #available(iOS 26.0, *) {
            // iOS 26: 시스템 Liquid Glass 탭바를 그대로 씁니다. (개선안 38)
            //
            // 아래 불투명 설정은 iOS 26 플로팅 탭바에서 확실히 적용되지 않았고
            // (ContentView 의 "시도 A" 주석), 시스템 재질을 억지로 막으면
            // 같은 탭바가 화면마다 다른 색으로 보였습니다.
            // 배경은 시스템에 맡기고 선택·비선택 색만 지정합니다.
            // 스크롤 시 축소는 ContentView 의 vfTabBarMinimizeOnScroll() 이 담당합니다.
            appearance.configureWithDefaultBackground()
        } else {
            // iOS 17~18 은 기존대로 불투명 surface2 를 유지합니다.
            //
            // Phase 1 에서는 불투명 유지가 의도입니다.
            // 스크롤 콘텐츠가 탭바 뒤에서 반투명하게 읽히는 문제를 확실히 차단합니다.
            appearance.configureWithOpaqueBackground()

            // backgroundEffect 를 명시적으로 지웁니다.
            //
            // configureWithOpaqueBackground() 는 시스템 블러를 넣습니다.
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
        }

        let itemAppearance = UITabBarItemAppearance()

        let unselectedColor = AppColors.uiSecondaryText.withAlphaComponent(0.70)
        itemAppearance.normal.iconColor = unselectedColor
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: unselectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        // 선택 상태 = 잉크(다크 흰색 / 라이트 #111). (개선안 38)
        //
        // 전에는 브랜드 주황이었습니다. 가운데 + 아이콘도 늘 주황이라
        // 탭바에 주황이 항상 두 개였고, 둘 다 선택된 것처럼 보였습니다.
        // 주황은 "지금 하면 좋은 일"(제보)인 + 에만 남깁니다.
        // 선택 구분은 색(흰색) + 형태(채운 아이콘, ContentView.AppTab)로 합니다.
        let selectedColor = AppColors.uiPrimary
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
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

        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().unselectedItemTintColor = unselectedColor
    }
}

@main
struct ViewfinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppColors.accent)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
    }
}
