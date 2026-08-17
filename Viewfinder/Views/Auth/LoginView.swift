import AuthenticationServices
import SwiftUI

enum AuthenticationDestination: String, Identifiable {
    case signIn

    var id: String { rawValue }
}

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    loginHero
                    guestReassurance
                    signInActions
                    legalNotice
                }
                .padding(.horizontal, 24)
                .padding(.top, 90)
                .padding(.bottom, 34)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                    .background(AppColors.mutedSurface, in: Circle())
                    .overlay(Circle().stroke(AppColors.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isSigningIn)
            .opacity(authViewModel.isSigningIn ? 0.45 : 1)
            .padding(.top, 12)
            .padding(.trailing, 18)
            .accessibilityLabel("로그인 닫기")
        }
        .interactiveDismissDisabled(authViewModel.isSigningIn)
        .onAppear {
            dismissIfSignedInAndIdle()
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            dismissIfSignedInAndIdle()
        }
        .onChange(of: authViewModel.isSigningIn) { _, _ in
            dismissIfSignedInAndIdle()
        }
    }

    private func dismissIfSignedInAndIdle() {
        guard authViewModel.isAuthenticated, !authViewModel.isSigningIn else { return }
        dismiss()
    }

    private var loginHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 앱의 정체를 보여주는 자리입니다.
            // 흰 사각형 + 검정 조리개였는데, 브랜드 색이 있는 앱에서
            // 로고 자리를 무채색으로 둘 이유가 없습니다.
            Image(systemName: "camera.aperture")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppColors.onAccent)
                .frame(width: 64, height: 64)
                .background(
                    AppColors.accent,
                    in: RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 9) {
                Text("좋은 장면을\n놓치지 않도록")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColors.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("출사지와 현장 정보를 계정에 연결해, 다음 촬영에서도 빠르게 이어가세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guestReassurance: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 34, height: 34)
                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("저장한 장소는 그대로 있어요")
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.primary)
                Text("둘러보기와 저장은 게스트로 계속 이용할 수 있어요.")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
    }

    private var signInActions: some View {
        VStack(spacing: 12) {
            if isAppleSignInEnabled {
                AppleAuthorizationButton {
                    authViewModel.startAppleSignIn()
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.controlCornerRadius, style: .continuous))
                .disabled(authViewModel.isSigningIn)
            }

            Button {
                authViewModel.startGoogleSignIn()
            } label: {
                HStack(spacing: 12) {
                    Text("G")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(width: 28, height: 28)

                    Text("Google로 계속하기")
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)

                    Spacer(minLength: 0)

                    if authViewModel.isSigningIn {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                            .scaleEffect(0.85)
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    colorScheme == .dark ? Color.white : Color.black,
                    in: RoundedRectangle(cornerRadius: AppLayout.controlCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isSigningIn)
            .opacity(authViewModel.isSigningIn ? 0.72 : 1)

            if let errorMessage = authViewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: AppLayout.controlCornerRadius, style: .continuous))
            }
        }
    }

    private var legalNotice: some View {
        Text("계속하면 서비스 이용에 필요한 인증 정보를 처리하는 데 동의하게 됩니다.")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
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
