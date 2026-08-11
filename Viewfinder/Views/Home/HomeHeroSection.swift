//
//  HomeHeroSection.swift
//  ViewFinder — Phase 2A (3차 수정)
//
//  [1차] containerRelativeFrame 로 폭을 맞추려다 카드가 화면 절반 폭으로 렌더됨
//  [2차] GeometryReader 로 크기를 명시했지만, ScrollView + .paging 스냅이
//        불안정해서 두 사진이 걸친 상태로 멈추는 경우가 있었음
//  [3차] 페이징을 TabView 에 맡깁니다. 한 번에 한 장만 보이는 것을 시스템이 보장합니다.
//
//  또한 검색 버튼을 Hero 안으로 들여왔습니다.
//  화면에 고정된 플로팅 검색 버튼은 스크롤할 때 카드의 북마크 버튼과
//  필연적으로 겹칩니다. Hero 와 함께 스크롤되면 충돌이 원천적으로 사라집니다.
//

import CoreLocation
import SwiftUI

struct HomeHeroSection: View {
    let recommendations: [GPTRecommendedSpot]
    let userLocation: CLLocationCoordinate2D?

    /// 카드 1장의 정확한 크기. 부모가 GeometryReader 로 측정해서 넘깁니다.
    let cardSize: CGSize
    /// 상태바 높이. 사진은 여기까지 올라가고 컨트롤만 아래로 내립니다.
    var topInset: CGFloat = 0

    /// Hero 좌상단 glass pill 문자열. (예: "일몰까지 2시간 10분 · 24°")
    var contextText: String? = nil
    /// pill 아이콘. 일몰 전이면 sunset.fill, 일몰 후면 sunrise.fill.
    var contextSymbolName: String = "sun.max"
    var onShowContext: (() -> Void)? = nil

    let onSelect: (PhotoSpot) -> Void
    let onSearch: () -> Void

    @State private var selection = 0

    private let maxCount = 5

    private var visible: [GPTRecommendedSpot] {
        Array(recommendations.prefix(maxCount))
    }

    var body: some View {
        if visible.isEmpty {
            NearbyRecommendationEmptyView(message: "주변 출사지 데이터가 부족해요")
                .vfScreenMargin()
                .padding(.top, topInset + VFSpace.lg)
        } else {
            pager
                .frame(height: cardSize.height)
                .clipped()
                .overlay(alignment: .top) { topControls }
        }
    }

    /// 페이징을 시스템에 맡깁니다.
    /// ScrollView + scrollTargetBehavior(.paging) 조합에서 두 카드가 걸친 상태로
    /// 멈추는 문제가 있었습니다. TabView 는 한 번에 한 페이지를 보장합니다.
    private var pager: some View {
        TabView(selection: $selection) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, recommendation in
                HomeHeroCard(
                    recommendation: recommendation,
                    distanceText: VFSpotDistance.text(
                        from: userLocation,
                        to: recommendation.spot
                    ),
                    size: cardSize,
                    onSelect: { onSelect(recommendation.spot) }
                )
                .tag(index)
            }
        }
        // 직접 만든 캡슐 인디케이터를 네이티브로 되돌립니다.
        // 커스텀 점은 손으로 만든 티가 나고, 시스템 것이 더 정돈돼 보입니다.
        // 위치는 텍스트 블록 우하단이 아니라 카드 하단 중앙(네이티브 기본)입니다.
        // backgroundDisplayMode: .always 로 어떤 사진 위에서도 보이게 합니다.
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - 사진 위 컨트롤
    //
    // 저장 버튼을 홈에서 전부 제거했습니다.
    //
    // 홈은 "둘러보는" 화면입니다. 카드마다 저장 버튼이 붙어 있으면
    // 사진 위에 버튼이 계속 떠 있어서 사진에 집중하기 어렵고,
    // 아직 어떤 곳인지 모르는 상태에서 저장을 요구하는 셈이 됩니다.
    // 저장은 상세 화면에서 장소를 확인한 뒤에 하는 동작으로 옮겼습니다.

    private var topControls: some View {
        HStack(alignment: .top, spacing: VFSpace.sm) {
            contextPill

            Spacer(minLength: VFSpace.sm)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("출사지 검색")
        }
        .padding(.horizontal, VFSpace.lg - VFSpace.xs)
        .padding(.top, topInset + VFSpace.sm)
    }

    @ViewBuilder
    private var contextPill: some View {
        if let contextText, !contextText.isEmpty {
            Button {
                onShowContext?()
            } label: {
                HStack(spacing: VFSpace.xs + 2) {
                    Image(systemName: contextSymbolName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(contextText)
                        .vfText(.mono)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, VFSpace.md)
                .frame(height: 38)
                .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(onShowContext == nil)
        }
    }

}

// MARK: - Hero Card

private struct HomeHeroCard: View {
    let recommendation: GPTRecommendedSpot
    let distanceText: String?
    /// 카드의 정확한 크기.
    ///
    /// 이전에는 ZStack(alignment: .bottomLeading) 안에 사진과 텍스트를 형제로 두었습니다.
    /// scaledToFill 한 사진이 ZStack 을 화면보다 넓게 만들었고, .bottomLeading 정렬이
    /// 그 "화면 밖 왼쪽 경계" 를 기준으로 잡혀서 장소명이 왼쪽으로 잘렸습니다.
    /// 사진 크기를 먼저 고정하고 텍스트를 overlay 로 올려서 해결합니다.
    let size: CGSize
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    private var crowdLevel: VFCrowdLevel {
        VFCrowdLevel.from(spot.crowdLevel)
    }

    private var metaItems: [String] {
        var items: [String] = []
        if let distanceText {
            items.append(distanceText)
        }
        items.append(region)
        return items
    }

    var body: some View {
        VFPhotoTile(
            spot: spot,
            aspectRatio: nil,
            height: size.height,
            cornerRadius: 0,
            showsScrim: true,
            // 밝은 사진(하늘, 잔디)에서 흰 텍스트가 읽히지 않는 문제가 있었습니다.
            scrimHeightRatio: 0.72,
            scrimStrength: 1.25,
            showsTopControlScrim: true,
            // Hero 는 상태바(흰 시계/배터리)까지 보호해야 합니다.
            topScrimStrength: 0.62,
            topScrimHeight: 130,
            imageDetail: .hero
        )
        // 사진 크기를 먼저 확정합니다. 이 순서가 중요합니다.
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottomLeading) { textLayer }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(region), \(crowdLevel.label)")
        .accessibilityAction(named: "상세 보기", onSelect)
    }

    private var textLayer: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            // "오늘의 출사지" 오버라인을 제거했습니다.
            // 12pt 앰버 텍스트를 사진 위에 올리니 밝은 사진에서 묻혔습니다.
            // 홈 최상단의 큰 사진이 추천이라는 것은 맥락상 자명하므로
            // 라벨 없이 장소명부터 시작하는 것이 더 강합니다.
            Text(spot.name)
                .vfText(.display)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: VFSpace.md) {
                VFMetaLineOnPhoto(items: metaItems)
                VFCrowdBadge(level: crowdLevel)
            }

        }
        .padding(.horizontal, VFSpace.lg)
        // 네이티브 페이지 인디케이터가 하단 중앙에 놓이므로
        // 텍스트가 그 위로 오도록 여백을 확보합니다.
        .padding(.bottom, VFSpace.xxl + VFSpace.sm)
        // 긴 장소명이 카드 밖으로 넘치지 않게 폭을 고정합니다.
        .frame(width: size.width, alignment: .leading)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - HomePhotoCard
//
//  섹션 카드. 모든 섹션이 이 카드 하나만 씁니다.
//
//  [이전 시도]
//  섹션마다 레이아웃을 다르게 해서(3:2 카로셀 / 2:1+1:1 모자이크) 리듬을 만들려 했으나
//  실제 화면에서는 "리듬"이 아니라 "규격이 안 맞는 것"으로 읽혔고,
//  캡션 없는 정사각 타일은 어디인지 알 수 없다는 문제가 있었습니다.
//  통일이 분화보다 낫다는 판단으로 전 섹션 동일 규격(3:2 + 캡션)으로 돌아갑니다.
// ═══════════════════════════════════════════════════════════════════

struct HomePhotoCard: View {
    let recommendation: GPTRecommendedSpot
    let aspectRatio: CGFloat
    var showsMeta: Bool = true
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    // 카드마다 "몇 km" 를 붙이면 사진 위에 숫자가 반복되어
    // 훑어볼 때 노이즈가 됩니다. 지역명만 남깁니다.
    private var metaItems: [String] {
        [region]
    }

    var body: some View {
        VFPhotoTile(
            spot: spot,
            aspectRatio: aspectRatio,
            cornerRadius: VFRadius.photo,
            showsScrim: true,
            scrimHeightRatio: 0.62,
            scrimStrength: 1.15
        )
        .overlay(alignment: .bottomLeading) { caption }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(region)")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: VFSpace.xs) {
            Text(spot.name)
                .vfText(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if showsMeta {
                VFMetaLineOnPhoto(items: metaItems)
            }
        }
        .padding(.horizontal, VFSpace.md + 2)
        .padding(.bottom, VFSpace.md)
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Preview
//
//  앱을 실행하지 않고 Canvas(⌥⌘↩)에서 바로 확인할 수 있습니다.
//  밝은 사진 / 어두운 사진 / 긴 장소명을 한 번에 볼 수 있게 구성했습니다.
//  시뮬레이터를 띄우고 탐색하는 것보다 훨씬 빠릅니다.
// ═══════════════════════════════════════════════════════════════════

#if DEBUG
enum HomePreviewData {
    static var samples: [GPTRecommendedSpot] {
        PhotoSpotSampleData.spots.prefix(5).map { spot in
            GPTRecommendedSpot(
                spot: spot,
                reason: spot.summary,
                scoreLabel: "오늘 추천",
                isGeneratedByGPT: false
            )
        }
    }

    static var first: GPTRecommendedSpot? { samples.first }
}

#Preview("Home Hero") {
    GeometryReader { proxy in
        let topInset = proxy.safeAreaInsets.top

        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.xxl) {
                HomeHeroSection(
                    recommendations: HomePreviewData.samples,
                    userLocation: nil,
                    cardSize: CGSize(
                        width: proxy.size.width,
                        height: (proxy.size.height + topInset) * VFPhoto.heroHeightRatio
                    ),
                    topInset: topInset,
                    contextText: "구로동 24°",
                    onShowContext: {},
                    onSelect: { _ in },
                    onSearch: {}
                )

                VFSectionTitle(title: "노을 명소", showsMore: true, onMore: {})
                    .vfScreenMargin()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VFSpace.md) {
                        ForEach(HomePreviewData.samples) { recommendation in
                            HomePhotoCard(
                                recommendation: recommendation,
                                aspectRatio: VFPhoto.carouselAspect,
                                onSelect: {}
                            )
                            .frame(width: proxy.size.width - VFSpace.lg * 2 - VFPhoto.carouselPeek)
                        }
                    }
                    .padding(.horizontal, VFSpace.lg)
                }
            }
            .padding(.bottom, 120)
        }
        .ignoresSafeArea(edges: .top)
    }
    .background(Color(uiColor: VFPalette.canvas))
    .preferredColorScheme(.dark)
}

#Preview("Photo Card") {
    VStack(spacing: VFSpace.lg) {
        if let sample = HomePreviewData.first {
            HomePhotoCard(
                recommendation: sample,
                aspectRatio: VFPhoto.carouselAspect,
                onSelect: {}
            )

            HomePhotoCard(
                recommendation: sample,
                aspectRatio: VFPhoto.squareAspect,
                onSelect: {}
            )
        }
    }
    .vfScreenMargin()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: VFPalette.canvas))
    .preferredColorScheme(.dark)
}
#endif
