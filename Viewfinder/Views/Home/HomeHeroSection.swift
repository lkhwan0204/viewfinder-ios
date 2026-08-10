//
//  HomeHeroSection.swift
//  ViewFinder — Phase 2A (2차 수정)
//
//  [1차 시도의 실패]
//  containerRelativeFrame(.horizontal) 로 카드 폭을 화면 폭에 맞추려 했으나
//  컨테이너가 기대와 다르게 해석되어 카드가 화면의 절반 폭으로 렌더되었고,
//  결과적으로 Hero 에 사진 두 장이 반쪽씩 나란히 보였습니다.
//  또한 nav bar 를 남겨둔 채 배경만 숨겨서 사진 위에 검정 띠가 생겼습니다.
//
//  [수정 방향]
//  1. 크기를 추측하지 않습니다. 부모가 GeometryReader 로 측정한 값을 그대로 받습니다.
//  2. 사진은 상태바까지 올라갑니다. 컨트롤만 상태바 아래로 내립니다.
//     (topInset 을 받아서 컨트롤에만 적용)
//

import CoreLocation
import SwiftUI

struct HomeHeroSection: View {
    let recommendations: [GPTRecommendedSpot]
    let savedSpotIDs: Set<String>
    let userLocation: CLLocationCoordinate2D?

    /// 카드 1장의 정확한 크기. 부모가 GeometryReader 로 측정해서 넘깁니다.
    let cardSize: CGSize
    /// 상태바 높이. 사진은 여기까지 올라가고 컨트롤만 아래로 내립니다.
    var topInset: CGFloat = 0

    /// Hero 좌상단 glass pill 문자열. (예: "구로동 25°")
    /// Phase 2B 에서 "일몰까지 2h 14m" 으로 대체됩니다.
    var contextText: String? = nil
    var onShowContext: (() -> Void)? = nil

    let onToggleSave: (PhotoSpot) -> Void
    let onSelect: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void

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
                            topInset: topInset,
                            onToggleSave: { onToggleSave(recommendation.spot) },
                            onSelect: { onSelect(recommendation.spot) },
                            onOpenMap: { onOpenMap(recommendation.spot) }
                        )
                        // 크기를 명시적으로 고정합니다. 이것이 1차 실패의 수정 지점입니다.
                        .frame(width: cardSize.width, height: cardSize.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .frame(height: cardSize.height)
            .overlay(alignment: .topLeading) { contextPill }
            .overlay(alignment: .bottomTrailing) { pageDots }
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
            .padding(.top, topInset + VFSpace.sm)
        }
    }

    /// 몇 장이 있는지 알려주는 최소한의 힌트.
    @ViewBuilder
    private var pageDots: some View {
        if visible.count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<visible.count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, VFSpace.md)
            .frame(height: 22)
            .vfGlass()
            .padding(.trailing, VFSpace.lg)
            .padding(.bottom, VFSpace.lg)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Hero Card

private struct HomeHeroCard: View {
    let recommendation: GPTRecommendedSpot
    let isSaved: Bool
    let distanceText: String?
    let topInset: CGFloat
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
                .padding(.trailing, VFSpace.lg - VFSpace.xs)
                .padding(.top, topInset + VFSpace.sm)
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
        // 페이지 인디케이터와 겹치지 않게 아래 여백을 넉넉히 둡니다.
        .padding(.bottom, VFSpace.xl + VFSpace.sm)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - HomePhotoCard
//
//  섹션 카드. 사진 아래 흰 영역에 텍스트를 두지 않고 사진 위 scrim 에 올립니다.
//
//  [1차 시도의 실패]
//  작은 정사각 타일에도 장소명을 넣었더니 2줄로 늘어나면서 타일 밖으로 잘렸습니다.
//  ("동대문디자인플라자 DDP" 등)
//  작은 타일은 사진만 보여주는 것이 맞습니다. 이름은 탭하면 알 수 있습니다.
//  Apple Photos 의 그리드가 그렇게 합니다.
// ═══════════════════════════════════════════════════════════════════

struct HomePhotoCard: View {
    let recommendation: GPTRecommendedSpot
    let aspectRatio: CGFloat
    let isSaved: Bool
    let distanceText: String?
    /// 작은 정사각 타일에서는 false. 사진만 보여줍니다.
    var showsCaption: Bool = true
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
            showsScrim: showsCaption,
            scrimHeightRatio: 0.62,
            showsTopControlScrim: true
        )
        .overlay(alignment: .bottomLeading) {
            if showsCaption {
                caption
            }
        }
        .overlay(alignment: .topTrailing) {
            VFSaveButton(isSaved: isSaved, action: onToggleSave, diameter: 32)
                .padding(.trailing, 2)
                .padding(.top, 2)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if showsMeta {
                VFMetaLineOnPhoto(items: metaItems)
            }
        }
        .padding(.horizontal, VFSpace.md + 2)
        .padding(.bottom, VFSpace.md)
    }
}
