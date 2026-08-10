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
    let savedSpotIDs: Set<String>
    let userLocation: CLLocationCoordinate2D?

    /// 카드 1장의 정확한 크기. 부모가 GeometryReader 로 측정해서 넘깁니다.
    let cardSize: CGSize
    /// 상태바 높이. 사진은 여기까지 올라가고 컨트롤만 아래로 내립니다.
    var topInset: CGFloat = 0

    /// Hero 좌상단 glass pill 문자열. (예: "구로동 24°")
    /// Phase 2B 에서 "일몰까지 2h 14m" 으로 대체됩니다.
    var contextText: String? = nil
    var onShowContext: (() -> Void)? = nil

    let onToggleSave: (PhotoSpot) -> Void
    let onSelect: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void
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
                .overlay(alignment: .bottomTrailing) { pageDots }
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
                    isSaved: savedSpotIDs.contains(recommendation.spot.id),
                    distanceText: VFSpotDistance.text(
                        from: userLocation,
                        to: recommendation.spot
                    ),
                    topInset: topInset,
                    onSelect: { onSelect(recommendation.spot) },
                    onOpenMap: { onOpenMap(recommendation.spot) }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - 사진 위 컨트롤
    //
    // 저장 / 검색 버튼을 한 줄에 모았습니다.
    // 화면 고정 플로팅 버튼이 아니라 Hero 안에 있으므로
    // 아래 카드들의 북마크 버튼과 겹치지 않습니다.

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

            if let current = visible.indices.contains(selection) ? visible[selection] : visible.first {
                VFSaveButton(
                    isSaved: savedSpotIDs.contains(current.spot.id),
                    action: { onToggleSave(current.spot) },
                    diameter: 38
                )
            }
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
                    Image(systemName: "sun.max")
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

    @ViewBuilder
    private var pageDots: some View {
        if visible.count > 1 {
            HStack(spacing: 5) {
                ForEach(visible.indices, id: \.self) { index in
                    Circle()
                        .fill(
                            index == selection
                                ? Color.white
                                : Color.white.opacity(0.42)
                        )
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, VFSpace.md)
            .frame(height: 22)
            .vfGlass()
            .padding(.trailing, VFSpace.lg)
            .padding(.bottom, VFSpace.lg)
            .allowsHitTesting(false)
            .animation(VFMotion.quick, value: selection)
        }
    }
}

// MARK: - Hero Card

private struct HomeHeroCard: View {
    let recommendation: GPTRecommendedSpot
    let isSaved: Bool
    let distanceText: String?
    let topInset: CGFloat
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
                // 밝은 사진(하늘, 잔디)에서 흰 텍스트가 읽히지 않는 문제가 있었습니다.
                // scrim 을 더 높고 진하게 깝니다.
                scrimHeightRatio: 0.72,
                scrimStrength: 1.25,
                showsTopControlScrim: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            textLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(region), \(crowdLevel.label)")
        .accessibilityAction(named: "상세 보기", onSelect)
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
        .padding(.bottom, VFSpace.xl + VFSpace.md)
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
            scrimStrength: 1.15,
            showsTopControlScrim: true
        )
        .overlay(alignment: .bottomLeading) { caption }
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
                .minimumScaleFactor(0.78)

            if showsMeta {
                VFMetaLineOnPhoto(items: metaItems)
            }
        }
        .padding(.horizontal, VFSpace.md + 2)
        .padding(.bottom, VFSpace.md)
    }
}
