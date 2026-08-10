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
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = AppColors.uiCardBackground
        appearance.shadowColor = AppColors.uiDivider

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = AppColors.uiSecondaryText.withAlphaComponent(0.72)
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: AppColors.uiSecondaryText.withAlphaComponent(0.72)
        ]
        itemAppearance.selected.iconColor = AppColors.uiPrimary
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: AppColors.uiPrimary
        ]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = AppColors.uiPrimary
        UITabBar.appearance().unselectedItemTintColor = AppColors.uiSecondaryText.withAlphaComponent(0.62)
    }
}

@main
struct ViewfinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
