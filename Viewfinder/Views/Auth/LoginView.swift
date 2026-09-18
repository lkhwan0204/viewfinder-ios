import AuthenticationServices
import SwiftUI

enum AuthenticationDestination: String, Identifiable {
    case signIn

    var id: String { rawValue }
}

/// 로그인 화면을 어떤 사용자 의도로 열었는지 나타냅니다.
///
/// 로그인 자체는 공통 화면을 쓰되, 시작한 작업이 명확한 경우에는
/// 사용자가 인증 후 어디로 이어지는지 알 수 있게 합니다.
enum LoginPresentationContext {
    case general
    case addSpot
    case contributePhotos
    case communityPost
}

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    var presentationContext: LoginPresentationContext = .general

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
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: contentTopInset(for: proxy.size.height))

                    brandLockup

                    Text(loginHeroTitle)
                        .vfText(.title1)
                        .foregroundStyle(AppColors.primary)
                        .padding(.top, VFSpace.xl)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(loginHeroDescription)
                        .vfText(.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.top, VFSpace.sm)
                        .fixedSize(horizontal: false, vertical: true)

                    signInActions
                        .padding(.top, VFSpace.xl)

                    Spacer(minLength: VFSpace.xxl)
                }
                .frame(minHeight: max(proxy.size.height - 8, 0), alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VFSpace.screenMargin)
                .padding(.bottom, VFSpace.xxl)
            }
            .background(AppColors.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNotes
        }
        .overlay(alignment: .topTrailing) {
            closeButton
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

    private func contentTopInset(for screenHeight: CGFloat) -> CGFloat {
        min(max(screenHeight * 0.16, 96), 136)
    }

    private var brandLockup: some View {
        HStack(spacing: VFSpace.md) {
            Image("ViewFinderAppIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(VFRadius.shape(VFRadius.inner))
                .overlay {
                    VFRadius.shape(VFRadius.inner)
                        .stroke(AppColors.primary.opacity(0.14), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("ViewFinder")
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)

                Text("사진 출사지 플랫폼")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ViewFinder, 사진 출사지 플랫폼")
    }

    private var loginHeroTitle: String {
        switch presentationContext {
        case .general:
            return "좋은 출사지를\n다시 찾기 쉽게"
        case .addSpot:
            return "발견한 출사지를\n함께 나눠주세요"
        case .contributePhotos:
            return "이 장소의 사진을\n함께 나눠주세요"
        case .communityPost:
            return "사진과 이야기를\n함께 나눠주세요"
        }
    }

    private var loginHeroDescription: String {
        switch presentationContext {
        case .general:
            return "저장한 장소와 활동을 계정에 연결해요."
        case .addSpot:
            return "로그인 후 장소를 등록하고 제보를 관리할 수 있어요."
        case .contributePhotos:
            return "로그인하면 선택한 장소에 사진을 등록할 수 있어요."
        case .communityPost:
            return "로그인하면 바로 글쓰기로 이어져요."
        }
    }

    private var guestReassuranceText: String {
        switch presentationContext {
        case .general:
            return "저장한 장소는 그대로 남아 있어요."
        case .addSpot, .contributePhotos, .communityPost:
            return "둘러보기와 저장은 로그인 없이도 가능해요."
        }
    }

    private var signInActions: some View {
        VStack(spacing: VFSpace.md) {
            if isAppleSignInEnabled {
                AppleAuthorizationButton(
                    style: colorScheme == .dark ? .white : .black
                ) {
                    authViewModel.startAppleSignIn()
                }
                .frame(height: 52)
                .clipShape(VFRadius.shape(VFRadius.inner))
                .disabled(authViewModel.isSigningIn)
                .id(colorScheme)
                .accessibilityLabel("Apple로 계속하기")
            }

            Button {
                authViewModel.startGoogleSignIn()
            } label: {
                HStack(spacing: VFSpace.md) {
                    Text("G")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(googleButtonForeground)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text("Google로 계속하기")
                        .vfText(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(googleButtonForeground)

                    Spacer(minLength: 0)

                    if authViewModel.isSigningIn {
                        ProgressView()
                            .tint(googleButtonForeground)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, VFSpace.lg - 2)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    googleButtonBackground,
                    in: VFRadius.shape(AppLayout.controlCornerRadius)
                )
                .contentShape(VFRadius.shape(AppLayout.controlCornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isSigningIn)
            .opacity(authViewModel.isSigningIn ? 0.72 : 1)
            .accessibilityLabel("Google로 계속하기")

            if let errorMessage = authViewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .vfText(.subhead)
                    .foregroundStyle(Color(uiColor: VFPalette.crowdBusy))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var googleButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var googleButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var bottomNotes: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text(guestReassuranceText)
                .vfText(.subhead)
                .foregroundStyle(AppColors.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("계속하면 서비스 이용에 필요한 인증 정보를 처리하는 데 동의하게 됩니다.")
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VFSpace.screenMargin)
        .padding(.top, VFSpace.md)
        .padding(.bottom, VFSpace.sm)
        .background(AppColors.background)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .background(AppColors.mutedSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(AppColors.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isSigningIn)
        .opacity(authViewModel.isSigningIn ? 0.45 : 1)
        .padding(.top, VFSpace.md)
        .padding(.trailing, VFSpace.screenMargin)
        .accessibilityLabel("로그인 닫기")
    }
}

struct AppleAuthorizationButton: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: style)
        button.cornerRadius = VFRadius.inner
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
