import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 24, height: 24)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("오늘의 출사지는?")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.58))
                }

                TextField("", text: $text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(onSubmit)
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}
