//
//  HomeHeroSection.swift
//  ViewFinder — Phase 2A
//
//  Home 최상단 Hero.
//
//  [기존 문제]
//  "오늘의 프레임" 섹션이 272x352 고정 카드의 가로 카로셀이었습니다.
//  화면 폭의 70% 정도만 쓰는 카드였고, 그 위에 섹션 헤더가 있고
//  그 아래에 날씨 칩이 있어서, 앱을 열었을 때 사진이 화면의 절반도 차지하지 못했습니다.
//  사진 앱의 첫 화면에서 사진이 주인공이 아니었습니다.
//
//  [변경]
//  화면 폭을 꽉 채우는(full-bleed) 4:5 사진으로, 높이는 뷰포트의 72%.
//  스크롤 전 첫 화면에 사실상 사진만 보이게 됩니다.
//  장소명은 사진 아래가 아니라 사진 위 scrim 안에 놓입니다.
//
//  [정보 설계]
//  기존 카드는 "지역"과 "추천 이유 2줄"을 보여줬습니다. 서술형이라 스캔이 안 됐습니다.
//  이 앱 사용자가 실제로 알고 싶은 것은 "지금 갈 만한가"입니다.
//  그래서 거리 / 지역 / 혼잡도로 바꿨습니다. 전부 mono 로 렌더해서
//  계기판처럼 읽히게 했습니다.
//

import CoreLocation
import SwiftUI

struct HomeHeroSection: View {
    let recommendations: [GPTRecommendedSpot]
    let savedSpotIDs: Set<String>
    let userLocation: CLLocationCoordinate2D?
    /// Hero 좌상단 glass pill 에 표시할 짧은 문자열. (예: "구로동 25°")
    /// Phase 2B 에서 "일몰까지 2h 14m" 으로 대체됩니다.
    var contextText: String? = nil
    var onShowContext: (() -> Void)? = nil
    let onToggleSave: (PhotoSpot) -> Void
    let onSelect: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void

    /// Hero 에 노출할 최대 장수. 추천 엔진이 실제로 5개까지 만듭니다.
    private let maxCount = 5

    private var visible: [GPTRecommendedSpot] {
        Array(recommendations.prefix(maxCount))
    }

    var body: some View {
        if visible.isEmpty {
            NearbyRecommendationEmptyView(message: "주변 출사지 데이터가 부족해요")
                .vfScreenMargin()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(visible) { recommendation in
                        HomeHeroCard(
                            recommendation: recommendation,
                            isSaved: savedSpotIDs.contains(recommendation.spot.id),
                            distanceText: VFSpotDistance.text(
                                from: userLocation,
                                to: recommendation.spot
                            ),
                            onToggleSave: { onToggleSave(recommendation.spot) },
                            onSelect: { onSelect(recommendation.spot) },
                            onOpenMap: { onOpenMap(recommendation.spot) }
                        )
                        // 화면 폭을 그대로 채웁니다. 이것이 full-bleed 의 핵심입니다.
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .containerRelativeFrame(.vertical, alignment: .top) { length, _ in
                length * VFPhoto.heroHeightRatio
            }
            .overlay(alignment: .topLeading) { contextPill }
        }
    }

    /// 사진 위에 떠 있는 유리 pill. Glass 를 써도 되는 위치입니다.
    @ViewBuilder
    private var contextPill: some View {
        if let contextText, !contextText.isEmpty {
            Button {
                onShowContext?()
            } label: {
                HStack(spacing: VFSpace.xs + 2) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 12, weight: .semibold))
                    Text(contextText)
                        .vfText(.mono)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, VFSpace.md)
                .frame(height: 34)
                .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(onShowContext == nil)
            .padding(.leading, VFSpace.lg)
            .padding(.top, VFSpace.sm)
        }
    }
}

// MARK: - Hero Card

private struct HomeHeroCard: View {
    let recommendation: GPTRecommendedSpot
    let isSaved: Bool
    let distanceText: String?
    let onToggleSave: () -> Void
    let onSelect: () -> Void
    let onOpenMap: () -> Void

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
        ZStack(alignment: .bottomLeading) {
            // 사진. 코너 반경 0 = 화면 경계를 넘어가는 느낌.
            VFPhotoTile(
                spot: spot,
                aspectRatio: nil,
                height: nil,
                cornerRadius: 0,
                showsScrim: true,
                scrimHeightRatio: 0.58,
                showsTopControlScrim: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            textLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            VFSaveButton(isSaved: isSaved, action: onToggleSave)
                .padding(.trailing, VFSpace.sm)
                .padding(.top, VFSpace.sm)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(region), \(crowdLevel.label)")
        .accessibilityAction(named: "상세 보기", onSelect)
        .accessibilityAction(named: isSaved ? "저장 해제" : "저장", onToggleSave)
    }

    private var textLayer: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text("오늘의 출사지")
                .vfText(.caption)
                .foregroundStyle(AppColors.accent)

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

            Button(action: onOpenMap) {
                HStack(spacing: VFSpace.xs + 2) {
                    Image(systemName: "map")
                        .font(.system(size: 12, weight: .semibold))
                    Text("지도에서 보기")
                        .vfText(.callout)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, VFSpace.md + 2)
                .frame(height: 38)
                .vfGlass(interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.top, VFSpace.xs)
        }
        .padding(.horizontal, VFSpace.lg)
        .padding(.bottom, VFSpace.lg + VFSpace.xs)
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - HomePhotoCard
//
//  섹션 카드. 사진 아래 흰 영역에 텍스트를 두지 않고 사진 위 scrim 에 올립니다.
//
//  [기존 문제]
//  HomeSecondarySpotCard 는 사진(132pt) + 텍스트 블록(최소 54pt) 구조였습니다.
//  카드 높이의 30% 가 텍스트 영역이라 사진 밀도가 낮았고,
//  화면에서 체감되는 흰(=배경) 면적이 사진보다 컸습니다.
//
//  [변경]
//  텍스트를 사진 위로 올려 같은 높이에서 사진을 30% 더 크게 보여줍니다.
//  작은 정사각 타일에서는 메타 라인을 생략합니다 — 작은 타일에 정보를 쌓으면
//  지저분해지고, 어차피 탭하면 알 수 있습니다.
// ═══════════════════════════════════════════════════════════════════

struct HomePhotoCard: View {
    let recommendation: GPTRecommendedSpot
    let aspectRatio: CGFloat
    let isSaved: Bool
    let distanceText: String?
    var showsMeta: Bool = true
    let onToggleSave: () -> Void
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
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
            aspectRatio: aspectRatio,
            cornerRadius: VFRadius.photo,
            showsScrim: true,
            scrimHeightRatio: 0.62,
            showsTopControlScrim: true
        )
        .overlay(alignment: .bottomLeading) { caption }
        .overlay(alignment: .topTrailing) {
            VFSaveButton(isSaved: isSaved, action: onToggleSave, diameter: 32)
                .padding(.trailing, VFSpace.xs)
                .padding(.top, VFSpace.xs)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(region)")
        .accessibilityAction(named: "상세 보기", onSelect)
        .accessibilityAction(named: isSaved ? "저장 해제" : "저장", onToggleSave)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: VFSpace.xs) {
            Text(spot.name)
                .vfText(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if showsMeta {
                VFMetaLineOnPhoto(items: metaItems)
            }
        }
        .padding(.horizontal, VFSpace.md + 2)
        .padding(.bottom, VFSpace.md + 2)
    }
}
