//
//  VFComponents.swift
//  ViewFinder — Design System "Frame & Light" / 공용 컴포넌트
//
//  VFDesign.swift 가 토큰이고, 이 파일이 그 토큰으로 만든 재사용 컴포넌트입니다.
//  화면 코드에서 사진 타일 / 저장 버튼 / 메타 라인 / 섹션 헤더를 직접 만들지 마세요.
//
//  이 파일이 해결하는 중복
//  - 북마크 버튼이 HomeFeedView 안에 4번 중복 구현되어 있었습니다.
//    (FeaturedSpotCard / HomeSecondarySpotCard / HomeCategoryListRow / CompactSpotCard)
//    크기도 36 / 34 / 31 / 32 로 다르고 배경 불투명도도 0.20 / 0.22 / 0.26 으로 달랐습니다.
//  - scrim 그라디언트가 카드마다 손으로 만들어져 있었습니다.
//  - 거리 문자열 포맷이 MapTabView 안에 private 으로 갇혀 있었습니다.
//

import CoreLocation
import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - VFPhotoTile
//
//  비율 기반 사진 타일.
//  기존 SpotVisualTile 은 width/height 고정값 API 라서 full-bleed 나
//  반응형 그리드에 쓸 수 없었습니다. 이 타입은 비율 또는 높이를 받습니다.
// ═══════════════════════════════════════════════════════════════════

/// 사진이 실제로 쓰이는 크기 단계.
///
/// 요청 해상도를 이 단계로 정해서, 작은 타일이 큰 이미지를 디코딩하는 낭비를 막습니다.
/// 값은 3배 해상도 기준으로 여유를 조금 둔 크기입니다.
enum VFPhotoDetail {
    /// 3열 타일, 리스트 leading 썸네일 (~64-120pt)
    case thumbnail
    /// 섹션 카로셀 카드 (~236pt)
    case card
    /// full-bleed Hero, 상세 화면 대표 사진 (화면 폭)
    case hero

    var pixelWidth: Int {
        switch self {
        case .thumbnail:
            return 400
        case .card:
            return 900
        case .hero:
            return 1600
        }
    }
}

struct VFPhotoTile: View {
    let spot: PhotoSpot

    /// 가로:세로 비율. VFPhoto.heroAspect / carouselAspect / squareAspect / wideAspect
    var aspectRatio: CGFloat? = VFPhoto.squareAspect
    /// 비율 대신 높이를 직접 지정할 때 사용. (Hero 처럼 화면 비율로 계산할 때)
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = VFRadius.photo
    /// 사진 위에 텍스트를 올릴 때만 true.
    var showsScrim: Bool = false
    var scrimHeightRatio: CGFloat = 0.55
    /// scrim 강도 배율. 밝은 사진(하늘, 잔디)에서 흰 텍스트 대비를 확보할 때 올립니다.
    var scrimStrength: Double = 1.0
    /// 사진 위 상단 컨트롤(저장 버튼)이 있을 때 true.
    var showsTopControlScrim: Bool = false
    /// 상단 scrim 강도. Hero 는 상태바(흰 시계/배터리)까지 보호해야 하므로 더 진하게.
    var topScrimStrength: Double = 0.40
    var topScrimHeight: CGFloat = 92
    /// 요청할 이미지 해상도 단계.
    var imageDetail: VFPhotoDetail = .card

    var body: some View {
        sizedImage
            .clipped()
            .modifier(
                VFPhotoTileScrims(
                    showsScrim: showsScrim,
                    scrimHeightRatio: scrimHeightRatio,
                    scrimStrength: scrimStrength,
                    showsTopControlScrim: showsTopControlScrim,
                    topScrimStrength: topScrimStrength,
                    topScrimHeight: topScrimHeight
                )
            )
            .clipShape(VFRadius.shape(cornerRadius))
    }

    @ViewBuilder
    private var sizedImage: some View {
        if let height {
            imageLayer
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else if let aspectRatio {
            // 투명한 상자로 비율을 정하고, 사진이 그 상자를 채우게 합니다.
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay { imageLayer }
        } else {
            imageLayer
        }
    }

    private var imageLayer: some View {
        PhotoSpotImageView(
            spot: spot,
            symbolSize: 32,
            targetPixelWidth: imageDetail.pixelWidth
        )
    }
}

private struct VFPhotoTileScrims: ViewModifier {
    let showsScrim: Bool
    let scrimHeightRatio: CGFloat
    let scrimStrength: Double
    let showsTopControlScrim: Bool
    let topScrimStrength: Double
    let topScrimHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showsTopControlScrim {
                    VFScrim(edge: .top, strength: topScrimStrength)
                        .frame(height: topScrimHeight)
                }
            }
            .overlay(alignment: .bottom) {
                if showsScrim {
                    GeometryReader { geometry in
                        VFScrim(edge: .bottom, strength: scrimStrength)
                            .frame(height: geometry.size.height * scrimHeightRatio)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - VFSaveButton
//
//  저장은 이 앱에서 가장 많이 쓰는 동작입니다.
//  하나의 컴포넌트로 통일하고 촉감까지 포함합니다.
// ═══════════════════════════════════════════════════════════════════

enum VFSaveButtonStyle {
    /// 사진 위. 어두운 원 배경 + 흰 아이콘.
    case onPhoto
    /// 콘텐츠 표면 위(상세 화면 제목 옆 등). 배경 없이 아이콘만.
    case plain
}

struct VFSaveButton: View {
    let isSaved: Bool
    let action: () -> Void

    /// 시각적 원 크기. 터치 영역은 항상 44pt 이상으로 유지됩니다.
    var diameter: CGFloat = 36
    var style: VFSaveButtonStyle = .onPhoto

    var body: some View {
        Button {
            VFHaptics.save()
            action()
        } label: {
            ZStack {
                if style == .onPhoto {
                    // 저장된 상태는 브랜드 오렌지로 채웁니다.
                    // 아이콘은 onAccent(어두운 잉크)라서 오렌지 위에서 6.7:1 을 확보합니다.
                    Circle()
                        .fill(isSaved ? AppColors.accent : Color.black.opacity(0.30))

                    if !isSaved {
                        // 어떤 사진 위에서도 경계가 보이도록 얇은 흰 테두리를 둡니다.
                        Circle()
                            .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                    }
                }

                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: max(diameter, 44), height: max(diameter, 44))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(VFMotion.quick, value: isSaved)
        .accessibilityLabel(isSaved ? "저장 해제" : "저장")
        .accessibilityAddTraits(.isButton)
    }

    private var iconSize: CGFloat {
        style == .onPhoto ? diameter * 0.42 : diameter * 0.62
    }

    private var iconColor: Color {
        switch style {
        case .onPhoto:
            return isSaved ? AppColors.onAccent : Color.white
        case .plain:
            return isSaved ? AppColors.accent : AppColors.secondaryText
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - VFMetaLine
//
//  "2.1km · 일몰 19:42 · 여유" 같은 계기판형 정보 라인.
//  숫자가 mono rounded 로 렌더되는 것이 이 앱의 목소리입니다.
// ═══════════════════════════════════════════════════════════════════

struct VFMetaLine: View {
    let items: [String]
    var color: Color = AppColors.secondaryText
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        let visible = items.filter { !$0.isEmpty }

        if !visible.isEmpty {
            Text(visible.joined(separator: "  ·  "))
                .vfText(.mono)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

/// 사진 위에 올라가는 메타 라인. 흰색 고정.
struct VFMetaLineOnPhoto: View {
    let items: [String]

    var body: some View {
        VFMetaLine(items: items, color: Color.white.opacity(0.88))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - VFSectionTitle
//
//  섹션 헤더. 아이콘을 붙이지 않습니다.
//  섹션마다 아이콘을 달면 모든 섹션이 같은 무게가 되어 강조가 사라집니다.
//  부제는 "설명"이 아니라 "에디토리얼 카피"일 때만 씁니다.
//  (O: "꽃과 물, 그리고 늦은 빛"  X: "최근 활동을 항목별로 빠르게 확인하세요")
// ═══════════════════════════════════════════════════════════════════

struct VFSectionTitle: View {
    let title: String
    var editorialSubtitle: String? = nil
    var count: Int? = nil
    var showsMore: Bool = false
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm - 1) {
                    Text(title)
                        .vfText(.title1)
                        .foregroundStyle(AppColors.primary)

                    if let count {
                        Text("\(count)")
                            .vfText(.mono)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                if let editorialSubtitle, !editorialSubtitle.isEmpty {
                    Text(editorialSubtitle)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            Spacer(minLength: VFSpace.sm)

            if showsMore, let onMore {
                Button(action: onMore) {
                    HStack(spacing: 2) {
                        Text("더보기")
                            .vfText(.callout)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: AppLayout.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) 전체 보기")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - VFSpotDistance
//
//  기존에는 MapTabView 안에 private 으로 갇혀 있어서
//  Home 에서 거리를 보여줄 수 없었습니다. 공용으로 승격합니다.
// ═══════════════════════════════════════════════════════════════════

enum VFSpotDistance {

    /// "820m" 또는 "2.1km". 위치를 모르면 nil.
    static func text(from coordinate: CLLocationCoordinate2D?, to spot: PhotoSpot) -> String? {
        guard let coordinate else { return nil }
        let meters = meters(from: coordinate, to: spot)
        return text(meters: meters)
    }

    static func text(meters: CLLocationDistance) -> String {
        if meters < 1_000 {
            return "\(Int(meters.rounded()))m"
        }
        return String(format: "%.1fkm", meters / 1_000)
    }

    static func meters(from coordinate: CLLocationCoordinate2D, to spot: PhotoSpot) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════

#if DEBUG
#Preview("VFComponents") {
    VStack(alignment: .leading, spacing: VFSpace.xl) {
        VFSectionTitle(
            title: "8월의 서울",
            editorialSubtitle: "꽃과 물, 그리고 늦은 빛",
            showsMore: true,
            onMore: {}
        )

        HStack(spacing: VFSpace.lg) {
            VFSaveButton(isSaved: false, action: {})
            VFSaveButton(isSaved: true, action: {})
        }

        VFMetaLine(items: ["2.1km", "일몰 19:42", "여유"])

        VFCrowdBadge(level: .normal)
    }
    .vfScreenMargin()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(uiColor: VFPalette.canvas))
    .preferredColorScheme(.dark)
}
#endif


// ═══════════════════════════════════════════════════════════════════
// MARK: - Zoom Transition
//
//  사진을 탭하면 그 자리에서 확대되어 상세가 되는 전환입니다.
//  사진 앱의 기본 문법이고, 사용자는 "애니메이션이 좋다" 고 인지하지 않고
//  "이 앱 잘 만들었다" 고 인지합니다.
//
//  ⚠️ iOS 18+ API 입니다. 두 모디파이어에 격리했습니다.
//
//  ⚠️ 현재 어디에서도 쓰지 않습니다. 정의만 남겨둔 이유:
//     상세 화면에 적용해봤지만 되돌렸습니다.
//      1. 전환 중 대표 사진(1600px) 디코딩이 겹쳐 애니메이션이 끊겼습니다.
//      2. 전체 화면은 드래그로 닫을 수 없어 닫기 버튼이 필요한데,
//         상세 화면은 하단 액션 바와 내부 시트를 이미 갖고 있어 컨트롤이 과해집니다.
//      3. zoom transition 은 push 네비게이션과 궁합이 맞습니다.
//         모달 위에 얹으면 계층이 모호해집니다.
//     상세를 push 구조로 바꾸거나 이미지 디코딩을 최적화하면 다시 쓸 수 있습니다.
// ═══════════════════════════════════════════════════════════════════

/// 전환이 시작될 위치. 사진 카드에 붙입니다.
struct VFZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// 전환이 도착할 화면. 상세 화면에 붙입니다.
struct VFZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func vfZoomSource(id: String, in namespace: Namespace.ID) -> some View {
        modifier(VFZoomSource(id: id, namespace: namespace))
    }

    func vfZoomDestination(id: String, in namespace: Namespace.ID) -> some View {
        modifier(VFZoomDestination(id: id, namespace: namespace))
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - VFLiveCrowd
//
//  혼잡도를 계산하는 단 하나의 장소.
//
//  [문제였던 상황]
//  홈 Hero 는 spot.crowdLevel(시드 고정값)을 쓰고,
//  상세 화면은 커뮤니티 제보를 반영해서 계산했습니다.
//  그래서 같은 장소인데 홈에서는 "붐빔", 상세에서는 "여유" 로 보였습니다.
//  화면마다 다른 값을 보여주면 사용자는 어느 쪽도 믿지 않습니다.
//
//  [해결]
//  모든 화면이 이 함수를 통해서만 혼잡도를 얻습니다.
//  새로 혼잡도를 표시할 화면이 생기면 여기를 쓰면 되고,
//  판정 규칙을 바꿀 때도 한 곳만 고치면 전부 반영됩니다.
// ═══════════════════════════════════════════════════════════════════

enum VFLiveCrowd {

    /// 최근 제보에서 계산한 혼잡도. 제보가 없으면 nil 입니다.
    ///
    /// 제보가 없을 때 시드 데이터(spot.crowdLevel)로 채우지 않는 것이 중요합니다.
    /// 시드 값은 실제 현장을 관측한 결과가 아니라 데이터에 미리 적어둔 문자열입니다.
    /// 그걸 실시간 정보처럼 보여주면, 현장에 아무도 없는 곳에 "붐빔" 이 뜨는 일이
    /// 생기고 사용자는 혼잡도 자체를 믿지 않게 됩니다.
    /// 근거를 설명할 수 없는 값은 보여주지 않고 "정보 없음" 으로 두는 편이
    /// 신뢰를 지키고, 제보를 유도하기도 합니다.
    ///
    /// - Parameters:
    ///   - spot: 대상 장소
    ///   - posts: 전체 커뮤니티 글. 내부에서 spotID 로 걸러냅니다.
    ///   - hours: 제보를 유효하게 볼 시간 창. 기본 3시간.
    static func resolve(
        spot: PhotoSpot,
        posts: [CommunityPost],
        within hours: Double = 3
    ) -> VFCrowdLevel? {
        let cutoff = Date().addingTimeInterval(-hours * 60 * 60)

        let recent = posts.filter { post in
            post.spotID == spot.id && post.createdAt >= cutoff
        }

        guard let latest = recent.max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }

        return VFCrowdLevel.from(latest.crowd.rawValue)
    }
}
