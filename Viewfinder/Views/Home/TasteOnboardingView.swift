import SwiftUI

struct TasteOnboardingView: View {
    let onComplete: (TastePreference) -> Bool
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPhotoIDs: [String]
    @State private var saveFailed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    init(
        initialSelection: [String] = [],
        onComplete: @escaping (TastePreference) -> Bool,
        onSkip: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onSkip = onSkip
        let validIDs = Set(TasteOnboardingCatalog.photos.map(\.id))
        _selectedPhotoIDs = State(initialValue: Array(initialSelection.filter { validIDs.contains($0) }.prefix(3)))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                brand
                    .padding(.top, 20)

                Text("끌리는 장면을\n골라주세요")
                    .vfText(.display)
                    .foregroundStyle(AppColors.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 38)
                    .accessibilityAddTraits(.isHeader)

                Text("장르를 고르는 대신 사진으로 취향을 알려주세요.\n고른 사진이 첫 피드의 출발점이 돼요.")
                    .vfText(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(TasteOnboardingCatalog.photos) { photo in
                        photoCell(photo)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, AppLayout.pageHorizontalPadding)
        }
        .background(AppColors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
        .alert("취향을 저장하지 못했어요", isPresented: $saveFailed) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("잠시 후 다시 시도해 주세요.")
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 28)
                .accessibilityHidden(true)

            Text("뷰파인더")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func photoCell(_ photo: TasteOnboardingPhoto) -> some View {
        let selectionIndex = selectedPhotoIDs.firstIndex(of: photo.id)

        return Button {
            toggle(photo.id)
        } label: {
            GeometryReader { geometry in
                Image(photo.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        if selectionIndex != nil {
                            Color.black.opacity(0.12)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let selectionIndex {
                            Text("\(selectionIndex + 1)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.onAccent)
                                .frame(width: 30, height: 30)
                                .background(AppColors.accent, in: Circle())
                                .padding(7)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                            .strokeBorder(selectionIndex == nil ? .clear : AppColors.accent, lineWidth: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                    .scaleEffect(selectionIndex == nil ? 1 : 0.97)
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.accessibilityDescription)
        .accessibilityValue(selectionIndex.map { "\($0 + 1)순위로 선택됨" } ?? "선택되지 않음")
        .accessibilityHint(selectionIndex == nil && selectedPhotoIDs.count == 3
                           ? "다른 사진을 선택하려면 먼저 선택한 사진 하나를 해제하세요"
                           : "두 번 탭하여 선택 상태 변경")
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Text(selectedPhotoIDs.isEmpty
                 ? "마음에 드는 사진 3장을 골라주세요"
                 : "\(selectedPhotoIDs.count)장 선택됨 · 이 느낌으로 시작할게요")
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)
                .frame(maxWidth: .infinity)

            Button {
                guard let preference = TastePreference(selectedPhotoIDs: selectedPhotoIDs) else { return }
                if !onComplete(preference) { saveFailed = true }
            } label: {
                Text("탐색 시작")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedPhotoIDs.count == 3 ? AppColors.onAccent : AppColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        selectedPhotoIDs.count == 3 ? AppColors.accent : AppColors.mutedSurface,
                        in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotoIDs.count != 3)

            Button("건너뛰기", action: onSkip)
                .vfText(.callout)
                .foregroundStyle(AppColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, AppLayout.pageHorizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(AppColors.background)
    }

    private func toggle(_ id: String) {
        let change = {
            if let index = selectedPhotoIDs.firstIndex(of: id) {
                selectedPhotoIDs.remove(at: index)
            } else if selectedPhotoIDs.count < 3 {
                selectedPhotoIDs.append(id)
            }
        }

        if reduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.18), change)
        }
    }
}
