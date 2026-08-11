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

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()

        // Phase 1 에서는 불투명 유지가 의도입니다.
        // 스크롤 콘텐츠가 탭바 뒤에서 반투명하게 읽히는 문제를 확실히 차단합니다.
        // Phase 3 에서 Liquid Glass + 콘텐츠 하단 inset 을 함께 도입할 때
        // 투명 재료로 전환합니다.
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.uiBackground
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
