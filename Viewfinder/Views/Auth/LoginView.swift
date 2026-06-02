import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel

    private var isAppleSignInEnabled: Bool {
        #if APPLE_SIGN_IN_ENABLED
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 62, height: 62)
                    .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColors.primary.opacity(0.08), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text("뷰파인더")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    Text("사진 찍기 좋은 순간과 장소를 조용히 찾아주는 출사 큐레이션.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 86)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 12) {
                if isAppleSignInEnabled {
                    AppleAuthorizationButton {
                        authViewModel.startAppleSignIn()
                    }
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(authViewModel.isSigningIn)
                } else {
                    DisabledAppleSignInButton()

                        Text("Apple 로그인은 유료 Apple Developer 계정에서 켤 수 있어요.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    authViewModel.startGoogleSignIn()
                } label: {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28, height: 28)
                            .background(AppColors.cardBackground, in: Circle())

                        Text("Google로 로그인")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppColors.primary)

                        if authViewModel.isSigningIn {
                            ProgressView()
                                .tint(AppColors.primary)
                                .scaleEffect(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(authViewModel.isSigningIn)

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.crowdCrowded)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct DisabledAppleSignInButton: View {
    var body: some View {
        Label("Apple로 로그인", systemImage: "apple.logo")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            )
            .opacity(0.72)
    }
}

struct AppleAuthorizationButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 14
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func didTap() {
            action()
        }
    }
}
