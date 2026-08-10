import CoreLocation
import SwiftUI

struct SearchView: View {
    @Binding var selectedSpot: PhotoSpot
    @Binding var selectedSpotRevision: Int

    let recommendedSpots: [PhotoSpot]
    let preloadedRecommendations: [GPTRecommendedSpot]
    let isPreloadingRecommendations: Bool
    let onAddAISpot: (PhotoSpot) -> Void
    let onShowSpotOnMap: (PhotoSpot?) -> Void

    @State private var isSearchPresented = false

    var body: some View {
        Button {
            isSearchPresented = true
        } label: {
            SearchButtonContent(title: "오늘의 출사지는?")
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isSearchPresented) {
            SearchFullScreenView(
                selectedSpot: $selectedSpot,
                selectedSpotRevision: $selectedSpotRevision,
                recommendedSpots: recommendedSpots,
                preloadedRecommendations: preloadedRecommendations,
                isPreloadingRecommendations: isPreloadingRecommendations,
                onAddAISpot: onAddAISpot,
                onShowSpotOnMap: onShowSpotOnMap
            )
        }
    }
}

private struct SearchFullScreenView: View {
    @Binding var selectedSpot: PhotoSpot
    @Binding var selectedSpotRevision: Int

    let recommendedSpots: [PhotoSpot]
    let preloadedRecommendations: [GPTRecommendedSpot]
    let isPreloadingRecommendations: Bool
    let onAddAISpot: (PhotoSpot) -> Void
    let onShowSpotOnMap: (PhotoSpot?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var regionRecommendations: [GPTRecommendedSpot] = []
    @State private var regionRecommendationTitle: String?
    @State private var regionRecommendationMessage: String?
    @State private var isSearching = false
    @StateObject private var locationReader = RecommendationLocationReader()
    @FocusState private var isSearchFieldFocused: Bool

    private var displayedRecommendations: [GPTRecommendedSpot] {
        if !preloadedRecommendations.isEmpty {
            return preloadedRecommendations
        }

        return recommendedSpots.prefix(8).map {
            GPTRecommendedSpot(
                spot: $0,
                reason: $0.eventPeriod,
                scoreLabel: "오늘 추천",
                isGeneratedByGPT: false
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        searchBar

                        if isSearching || regionRecommendationMessage != nil {
                            statusRow
                        }

                        if !regionRecommendations.isEmpty {
                            regionRecommendationsSection
                        }

                        todayRecommendations
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 34, height: 34)
                            .background(AppColors.primarySoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색 닫기")
                }
            }
            .onAppear {
                locationReader.requestLocation()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isSearchFieldFocused = true
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 24, height: 24)

            TextField("서울, 부산, 경기도...", text: $searchText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(searchPlace)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    regionRecommendations = []
                    regionRecommendationTitle = nil
                    regionRecommendationMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }

            Button("검색") {
                searchPlace()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.secondaryText.opacity(0.38) : AppColors.primary)
            .frame(width: 42, height: 30)
            .buttonStyle(.plain)
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Text(isSearching ? "기본 출사지 데이터에서 찾는 중" : (regionRecommendationMessage ?? ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private var regionRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(regionRecommendationTitle ?? "검색 결과", systemImage: "mappin.and.ellipse")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.primary)

            VStack(spacing: 9) {
                ForEach(regionRecommendations) { recommendation in
                    Button {
                        selectRecommendation(recommendation.spot)
                    } label: {
                        RegionRecommendationRow(recommendation: recommendation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private var todayRecommendations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("오늘 추천", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                if isPreloadingRecommendations {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(displayedRecommendations) { recommendation in
                        Button {
                            selectRecommendation(recommendation.spot)
                        } label: {
                            RecommendationSlideCard(recommendation: recommendation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 14)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .padding(.horizontal, -14)
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private func searchPlace() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearchFieldFocused = false
        isSearching = true
        regionRecommendations = []
        regionRecommendationTitle = nil
        regionRecommendationMessage = nil

        Task {
            let userLocation = await locationReader.coordinateForRecommendation()
            let spots = LocalSeedDataService().photoSpots(matching: query, limit: 10)
            let regionScope = SearchRegionPolicy.scope(for: query)
            let fallbackSpots = spots.isEmpty && regionScope == nil
                ? LocalSeedDataService().homePhotoSpots(near: userLocation, limit: 8)
                : spots

            await MainActor.run {
                regionRecommendations = fallbackSpots.map {
                    GPTRecommendedSpot(
                        spot: $0,
                        reason: $0.eventPeriod,
                        scoreLabel: spots.isEmpty ? "주변 추천" : "기본 데이터",
                        isGeneratedByGPT: false
                    )
                }
                if spots.isEmpty, let regionScope {
                    regionRecommendationTitle = "\(regionScope.displayName) 검색 결과"
                    regionRecommendationMessage = "\(regionScope.displayName) 출사지 데이터가 아직 부족해요."
                } else {
                    regionRecommendationTitle = spots.isEmpty ? "\(query) 대신 주변 추천" : "\(query) 추천 출사지"
                    regionRecommendationMessage = spots.isEmpty ? "앱 안의 기본 데이터에 아직 정확한 지역 결과가 없어서 주변 추천을 먼저 보여줘요." : nil
                }
                isSearching = false
            }
        }
    }

    private func selectRecommendation(_ spot: PhotoSpot) {
        onAddAISpot(spot)
        selectedSpot = spot
        selectedSpotRevision += 1
        onShowSpotOnMap(spot)
        dismiss()
    }
}

private struct RecommendationSlideCard: View {
    let recommendation: GPTRecommendedSpot

    private var spot: PhotoSpot {
        recommendation.spot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SpotSearchVisualTile(spot: spot, width: 140, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.scoreLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(spot.theme.primary)
                    .lineLimit(1)

                Text(spot.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(spot.region)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Text(recommendation.reason)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 142, height: 168, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct RegionRecommendationRow: View {
    let recommendation: GPTRecommendedSpot

    private var spot: PhotoSpot {
        recommendation.spot
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            SpotSearchVisualTile(spot: spot, width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(recommendation.scoreLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(spot.theme.primary)
                    .lineLimit(1)

                Text(spot.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(spot.region)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(recommendation.reason)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                .padding(.top, 13)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct SpotSearchVisualTile: View {
    let spot: PhotoSpot
    var width: CGFloat? = nil
    var height: CGFloat = 58

    private var resolvedWidth: CGFloat {
        width ?? 140
    }

    var body: some View {
        PhotoSpotImageView(spot: spot, symbolSize: 21)
            .frame(width: resolvedWidth, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SearchButtonContent: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.secondaryText.opacity(0.72))

            Spacer(minLength: 0)
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
