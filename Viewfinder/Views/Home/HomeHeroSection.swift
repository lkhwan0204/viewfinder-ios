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
    let recommendations: [RecommendedSpot]
    let userLocation: CLLocationCoordinate2D?
    /// 혼잡도를 커뮤니티 제보로 계산하기 위해 필요합니다.
    /// 이전에는 spot.crowdLevel(시드 고정값)만 써서 상세 화면과 값이 어긋났습니다.
    var communityPosts: [CommunityPost] = []

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

    private var visible: [RecommendedSpot] {
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
                    controlStripHeight: controlStripHeight,
                    communityPosts: communityPosts,
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

    /// 사진 위 컨트롤 한 줄의 높이.
    ///
    /// 이 값을 상수로 뽑은 이유는 Hero 카드가 같은 값을 봐야 하기 때문입니다.
    /// 카드는 이 줄만큼을 자기 탭 영역에서 제외합니다. 둘이 다른 숫자를
    /// 쓰면 컨트롤 아래쪽이나 위쪽에 어긋난 띠가 생깁니다.
    private static let controlHeight: CGFloat = 38

    /// 카드 상단에서 컨트롤 줄이 끝나는 지점.
    private var controlStripHeight: CGFloat {
        topInset + VFSpace.sm + Self.controlHeight
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: VFSpace.sm) {
            contextPill

            Spacer(minLength: VFSpace.sm)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: Self.controlHeight, height: Self.controlHeight)
                    .contentShape(Rectangle())
                    .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("출사지 검색")
        }
        .padding(.horizontal, VFSpace.lg - VFSpace.xs)
        .padding(.top, topInset + VFSpace.sm)
        // ═══════════════════════════════════════════════════════════
        //  ★ 이 background 가 상단 겹침 버그를 막는 유일한 장치입니다.
        //    지우면 날씨 칩·검색 버튼을 눌렀을 때 뒤의 Hero 카드까지
        //    같이 눌립니다.
        //
        //  [문제였던 상황]
        //  날씨 칩이나 검색 버튼을 누르면 그 동작과 함께 장소 상세까지
        //  열렸습니다. 컨트롤은 Hero 카드 위에 overlay 로 얹혀 있고,
        //  카드는 카드 전체를 탭 영역으로 잡고 있어서 상단에서 두 탭
        //  영역이 겹칩니다.
        //
        //  보통은 앞에 있는 버튼이 터치를 먹고 끝납니다. 그런데 카드는
        //  TabView 의 page 스타일 안에 있고 그것은 UIPageViewController
        //  로 구현됩니다. 카드의 탭 제스처는 UIKit 이 관리하는 페이지
        //  안에 있고 버튼은 그 바깥 SwiftUI 레이어에 있어서, 서로의
        //  제스처를 취소시키지 못합니다. 그래서 양쪽이 다 실행됩니다.
        //
        //  [1차 시도는 실패했습니다]
        //  카드의 contentShape 에서 이 줄 높이만큼을 뺐습니다.
        //  계산은 맞았습니다. 컨트롤은 topInset+8 부터 topInset+46 까지고
        //  카드에서 뺀 높이도 topInset+46, 좌표계도 같습니다.
        //  그래도 실기에서 카드가 계속 눌렸습니다.
        //  contentShape 은 "이 도형 안에서만 반응해라" 는 요청이고,
        //  UIPageViewController 경계를 넘으면 지켜지지 않습니다.
        //
        //  [2차: 도형이 아니라 실제 뷰]
        //  컨트롤 줄 뒤에 터치를 받는 레이어를 깔았습니다.
        //  뷰가 있으면 UIKit 히트 테스트 단계에서 터치가 여기서 멈추고
        //  아래로 내려가지 않습니다. 요청이 아니라 구조입니다.
        //  실기 로그로 확인했습니다. 칩을 누르면 칩만 실행되고 카드
        //  핸들러는 호출되지 않습니다.
        //
        //  background 로 넣은 것이 핵심입니다. 이 레이어는 버튼보다 뒤에
        //  있으므로 버튼이 먼저 터치를 받고, 버튼 사이 빈 자리에 떨어진
        //  터치만 이 레이어가 삼킵니다. 줄 전체를 감싸는 방식으로 만들면
        //  부모 탭 제스처가 자식 버튼의 터치를 가로챌 위험이 있습니다.
        //
        //  Color.clear 는 SwiftUI 에서 히트 테스트에 참여합니다.
        //  (UIKit 의 clearColor 와 다릅니다.)
        //  빈 클로저인 것이 의도입니다. 하는 일은 터치를 소비하는 것뿐입니다.
        //
        //  대가: 이 줄에서는 좌우 스와이프로 Hero 페이지를 넘길 수
        //  없습니다. 컨트롤이 놓인 줄이므로 받아들일 만한 손실입니다.
        // ═══════════════════════════════════════════════════════════
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { }
        }
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
                .frame(height: Self.controlHeight)
                // 캡슐 전체를 누를 수 있게 합니다.
                // 이 칩은 label 에 Text 가 있어서 글자 부분은 눌렸지만,
                // 좌우 패딩 영역은 히트 영역이 아니었습니다.
                .contentShape(Capsule())
                .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(onShowContext == nil)
        }
    }

}

// MARK: - Hero Card

/// Hero 카드의 탭 영역. 위쪽 컨트롤 줄을 뺀 나머지 사각형입니다.
///
/// Rectangle() 을 그대로 쓰면 카드 전체가 탭 영역이 되어 사진 위
/// 컨트롤과 겹칩니다. (HomeHeroCard 의 contentShape 주석 참고)
private struct HeroCardTapArea: Shape {
    let topExclusion: CGFloat

    func path(in rect: CGRect) -> Path {
        // 카드가 컨트롤 줄보다 짧은 비정상 상황에서 음수 높이가 되지
        // 않게 막습니다. 그런 경우에는 탭 영역이 없는 것이 맞습니다.
        let top = min(max(topExclusion, 0), rect.height)
        return Path(
            CGRect(
                x: rect.minX,
                y: rect.minY + top,
                width: rect.width,
                height: rect.height - top
            )
        )
    }
}

private struct HomeHeroCard: View {
    let recommendation: RecommendedSpot
    let distanceText: String?
    /// 카드의 정확한 크기.
    ///
    /// 이전에는 ZStack(alignment: .bottomLeading) 안에 사진과 텍스트를 형제로 두었습니다.
    /// scaledToFill 한 사진이 ZStack 을 화면보다 넓게 만들었고, .bottomLeading 정렬이
    /// 그 "화면 밖 왼쪽 경계" 를 기준으로 잡혀서 장소명이 왼쪽으로 잘렸습니다.
    /// 사진 크기를 먼저 고정하고 텍스트를 overlay 로 올려서 해결합니다.
    let size: CGSize
    /// 카드 상단에서 사진 위 컨트롤(날씨 칩 · 검색 버튼)이 차지하는 높이.
    /// 이 만큼을 탭 영역에서 제외합니다. 아래 contentShape 주석 참고.
    let controlStripHeight: CGFloat
    let communityPosts: [CommunityPost]
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    /// 상세 화면과 같은 계산기를 씁니다.
    /// 사용자가 현장 정보를 등록하면 홈 Hero 의 배지도 함께 바뀝니다.
    /// 제보가 없으면 nil 이고, 이때는 배지 대신 "현장 정보 없음" 을 보여줍니다.
    private var crowdLevel: VFCrowdLevel? {
        VFLiveCrowd.resolve(spot: spot, posts: communityPosts)
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
        // 탭 영역에서 상단 컨트롤 줄을 뺍니다.
        //
        // ★ 주의: 이것만으로는 동작하지 않습니다.
        //   상단 겹침 버그를 실제로 막는 것은 HomeHeroSection 의
        //   topControls 에 붙은 background 레이어입니다. 그쪽 주석에
        //   전체 경위가 있습니다.
        //
        // 이 도형을 남겨두는 이유는 원리상 맞는 코드이기 때문입니다.
        // 카드의 탭 영역이 사진 위 컨트롤 자리까지 뻗는 것은 어느 컨테이너
        // 안에서든 틀립니다. 지금은 TabView 의 page 스타일이
        // UIPageViewController 로 구현되어 이 요청이 무시되지만, 페이저
        // 구현이 바뀌면 이 도형이 제 역할을 하게 됩니다.
        .contentShape(HeroCardTapArea(topExclusion: controlStripHeight))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            "\(spot.name), \(region), \(crowdLevel?.accessibilityLabel ?? "현장 정보 없음")"
        )
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

                if let crowdLevel {
                    VFCrowdBadge(level: crowdLevel)
                } else {
                    // 시드 값으로 채우지 않고 없다고 말합니다.
                    // 제보를 유도하는 효과도 있습니다.
                    Text("현장 정보 없음")
                        .vfText(.mono)
                        .foregroundStyle(Color.white.opacity(0.58))
                }
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
    let recommendation: RecommendedSpot
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
    static var samples: [RecommendedSpot] {
        PhotoSpotSampleData.spots.prefix(5).map { spot in
            RecommendedSpot(
                spot: spot,
                reason: spot.summary
            )
        }
    }

    static var first: RecommendedSpot? { samples.first }
}

/// Preview 에서 @Namespace 를 쓰려면 뷰 안에 있어야 하므로 래퍼를 둡니다.
private struct HomeHeroPreviewHost: View {
    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ScrollView {
                LazyVStack(alignment: .leading, spacing: VFSpace.xl) {
                    HomeHeroSection(
                        recommendations: HomePreviewData.samples,
                        userLocation: nil,
                        cardSize: CGSize(
                            width: proxy.size.width,
                            height: (proxy.size.height + topInset) * VFPhoto.heroHeightRatio
                        ),
                        topInset: topInset,
                        contextText: "일몰까지 2시간 10분  ·  24°",
                        contextSymbolName: "sunset.fill",
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
                                .frame(width: proxy.size.width * VFPhoto.railWidthRatio)
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
    }
}

#Preview("Home Hero") {
    HomeHeroPreviewHost()
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
