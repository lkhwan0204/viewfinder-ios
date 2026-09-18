//
//  HomeHeroSection.swift
//  ViewFinder — Phase 2A
//
//  [1차] containerRelativeFrame 로 폭을 맞추려다 카드가 화면 절반 폭으로 렌더됨
//  [2차] GeometryReader 로 크기를 명시했지만, ScrollView + .paging 스냅이
//        불안정해서 두 사진이 걸친 상태로 멈추는 경우가 있었음
//  [현재] 실제 horizontal scroll position을 paging 애니메이션으로 이동합니다.
//  양 끝에 복제 페이지를 두어 마지막→첫 페이지도 같은 방향으로 이어집니다.
//
//  또한 검색 버튼을 Hero 안으로 들여왔습니다.
//  화면에 고정된 플로팅 검색 버튼은 스크롤할 때 카드의 북마크 버튼과
//  필연적으로 겹칩니다. Hero 와 함께 스크롤되면 충돌이 원천적으로 사라집니다.
//

import CoreLocation
import SwiftUI

struct HomeHeroSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let recommendations: [RecommendedSpot]
    let userLocation: CLLocationCoordinate2D?

    /// 카드 1장의 정확한 크기. 부모가 GeometryReader 로 측정해서 넘깁니다.
    let cardSize: CGSize
    /// 상태바 높이. 사진은 여기까지 올라가고 컨트롤만 아래로 내립니다.
    var topInset: CGFloat = 0

    /// Hero 상단 상태 줄 문자열. (예: "일몰까지 2시간 10분 · 24° · 구름 적음")
    var contextText: String? = nil
    /// pill 아이콘. 일몰 전이면 sunset.fill, 일몰 후면 sunrise.fill.
    var contextSymbolName: String = "sun.max"
    /// 날씨 snapshot을 기다리는 동안에도 상단 컨트롤의 자리를 유지합니다.
    /// 실제 기온이나 상태를 추정해서 보여주지는 않습니다.
    var contextIsLoading: Bool = false
    var onShowContext: (() -> Void)? = nil
    /// Hero 이유 줄에 넣을 일출·일몰까지의 남은 시간입니다.
    /// 상단 날씨 캡슐과 달리, 사진을 지금 보러 갈 행동 정보만 전달합니다.
    var heroReasonTimeText: String? = nil
    /// Hero 사진을 길게 눌러 저장하는 동작입니다.
    /// 카드마다 버튼을 띄우지 않아 사진을 가리지 않으면서도 저장을 발견할 수 있습니다.
    var savedSpotIDs: Set<String> = []
    var onToggleSave: ((PhotoSpot) -> Void)? = nil

    let onSelect: (PhotoSpot) -> Void
    let onSearch: () -> Void

    @State private var selection = 0
    @State private var carouselPosition: HeroCarouselPage? = .item(0)
    @State private var isHeroDragging = false
    @State private var autoAdvanceResetToken = 0

    private enum HeroCarouselPage: Hashable {
        case duplicateLast
        case item(Int)
        case duplicateFirst
    }

    private let maxCount = 3
    private static let autoAdvanceIntervalNanoseconds: UInt64 = 5_000_000_000
    private static let autoAdvanceAnimation = Animation.easeInOut(duration: 0.45)
    private static let carouselNormalizationDelayNanoseconds: UInt64 = 450_000_000

    private var visible: [RecommendedSpot] {
        Array(recommendations.prefix(maxCount))
    }

    private var carouselPages: [HeroCarouselPage] {
        guard visible.count > 1 else { return [.item(0)] }
        return [.duplicateLast]
            + visible.indices.map { .item($0) }
            + [.duplicateFirst]
    }

    private var carouselPageSignature: String {
        visible.map(\.id).joined(separator: ",")
    }

    private var shouldAutoAdvance: Bool {
        visible.count > 1
            && scenePhase == .active
            && !reduceMotion
            && !isHeroDragging
    }

    private var autoAdvanceTaskID: String {
        [
            visible.map(\.id).joined(separator: ","),
            String(describing: scenePhase),
            String(reduceMotion),
            String(isHeroDragging),
            String(autoAdvanceResetToken)
        ].joined(separator: "|")
    }

    var body: some View {
        if visible.isEmpty {
            NearbyRecommendationEmptyView(
                message: "주변 출사지 데이터가 부족해요",
                actionTitle: "출사지 검색",
                action: onSearch
            )
                .vfScreenMargin()
                .padding(.top, topInset + VFSpace.lg)
        } else {
            VStack(spacing: 0) {
                pager
                    .frame(width: cardSize.width, height: cardSize.height)
                    .clipped()
                    .overlay(alignment: .top) { topControls }

                if visible.count > 1 {
                    HomeHeroPageIndicator(
                        selection: $selection,
                        count: visible.count
                    )
                    // 사진 경계에 붙이지 않고 피드 위에 독립된 공간을 둡니다.
                    // 그라디언트와 다음 섹션 제목 양쪽에 여백이 생깁니다.
                    .frame(height: VFSpace.lg)
                }
            }
            .task(id: autoAdvanceTaskID) {
                await autoAdvanceHeroIfNeeded()
            }
            .onChange(of: selection) { _, newSelection in
                resetAutoAdvanceTimer()
                moveCarouselToSelectionIfNeeded(newSelection)
            }
            .onChange(of: carouselPageSignature) { _, _ in
                resetCarouselPosition()
                resetAutoAdvanceTimer()
            }
        }
    }

    @MainActor
    private func autoAdvanceHeroIfNeeded() async {
        guard shouldAutoAdvance else { return }

        do {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: Self.autoAdvanceIntervalNanoseconds)
                guard !Task.isCancelled, shouldAutoAdvance else { return }

                withAnimation(Self.autoAdvanceAnimation) {
                    carouselPosition = nextAutoAdvancePage
                }
            }
        } catch is CancellationError {
            // 화면 이탈·백그라운드·드래그 시작에 따른 취소는 정상 흐름입니다.
        } catch {
            // 자동 전환은 실패를 사용자에게 노출할 작업이 없습니다.
        }
    }

    private func resetAutoAdvanceTimer() {
        autoAdvanceResetToken += 1
    }

    private var nextAutoAdvancePage: HeroCarouselPage {
        guard selection == visible.count - 1 else {
            return .item(selection + 1)
        }

        // 마지막 카드에서 복제된 첫 카드를 먼저 보여준 뒤,
        // 애니메이션이 끝나면 실제 첫 카드로 무음 정규화합니다.
        return .duplicateFirst
    }

    private func moveCarouselToSelectionIfNeeded(_ newSelection: Int) {
        guard visible.indices.contains(newSelection) else { return }
        guard case .item(let currentIndex) = carouselPosition,
              currentIndex != newSelection else { return }

        withAnimation(Self.autoAdvanceAnimation) {
            carouselPosition = .item(newSelection)
        }
    }

    private func handleCarouselPositionChange(_ page: HeroCarouselPage?) {
        guard let page else { return }

        switch page {
        case .duplicateLast:
            selection = max(visible.count - 1, 0)
        case .item(let index):
            guard visible.indices.contains(index) else { return }
            selection = index
        case .duplicateFirst:
            selection = 0
        }
    }

    private func resetCarouselPosition() {
        guard !visible.isEmpty else { return }

        let safeSelection = min(max(selection, 0), visible.count - 1)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            carouselPosition = .item(safeSelection)
        }
    }

    @MainActor
    private func normalizeDuplicateCarouselPageIfNeeded() async {
        guard visible.count > 1,
              let page = carouselPosition else { return }

        let target: HeroCarouselPage
        switch page {
        case .duplicateLast:
            target = .item(visible.count - 1)
        case .duplicateFirst:
            target = .item(0)
        case .item:
            return
        }

        if !reduceMotion {
            do {
                try await Task.sleep(
                    nanoseconds: Self.carouselNormalizationDelayNanoseconds
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }

        guard !Task.isCancelled, carouselPosition == page else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            carouselPosition = target
        }
    }

    private var heroDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                guard !isHeroDragging else { return }
                isHeroDragging = true
            }
            .onEnded { _ in
                isHeroDragging = false
                resetAutoAdvanceTimer()
            }
    }

    /// 실제 스크롤 위치를 움직이는 native paging carousel입니다.
    /// 양 끝의 복제 페이지는 마지막→첫 페이지 전환 뒤 무음으로 실제 페이지에
    /// 정규화되어, 사용자에게 역방향 점프가 보이지 않게 합니다.
    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(carouselPages, id: \.self) { page in
                    heroCard(for: page)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $carouselPosition, anchor: .center)
        .simultaneousGesture(heroDragGesture)
        .onAppear {
            resetCarouselPosition()
        }
        .onChange(of: carouselPosition) { _, newPosition in
            handleCarouselPositionChange(newPosition)
        }
        .task(id: carouselPosition) {
            await normalizeDuplicateCarouselPageIfNeeded()
        }
    }

    private func heroCard(for page: HeroCarouselPage) -> some View {
        let index: Int
        switch page {
        case .duplicateLast:
            index = visible.count - 1
        case .item(let value):
            index = value
        case .duplicateFirst:
            index = 0
        }

        let recommendation = visible[index]
        return HomeHeroCard(
            recommendation: recommendation,
            distanceText: VFSpotDistance.text(
                from: userLocation,
                to: recommendation.spot
            ),
            heroReasonTimeText: heroReasonTimeText,
            size: cardSize,
            controlStripHeight: controlStripHeight,
            isSaved: savedSpotIDs.contains(recommendation.spot.id),
            onToggleSave: {
                onToggleSave?(recommendation.spot)
            },
            onSelect: { onSelect(recommendation.spot) }
        )
    }

    // MARK: - 사진 위 컨트롤
    //
    // 저장 버튼을 사진 위에 상시 노출하지 않습니다.
    //
    // 사진을 가리지 않으면서도 저장을 발견할 수 있도록 Hero 전체를
    // 길게 누르면 저장/저장 해제가 실행됩니다. 상세 화면의 저장 버튼은
    // 기존대로 유지됩니다.

    /// 사진 위 컨트롤 한 줄의 높이.
    ///
    /// 이 값을 상수로 뽑은 이유는 Hero 카드가 같은 값을 봐야 하기 때문입니다.
    /// 카드는 이 줄만큼을 자기 탭 영역에서 제외합니다. 둘이 다른 숫자를
    /// 쓰면 컨트롤 아래쪽이나 위쪽에 어긋난 띠가 생깁니다.
    private static let controlHeight: CGFloat = 38
    /// 검색 버튼은 날씨 pill과 독립적으로 정사각형을 유지해야 합니다.
    private static let searchButtonSize: CGFloat = 38

    /// 카드 상단에서 컨트롤 줄이 끝나는 지점.
    private var controlStripHeight: CGFloat {
        topInset + VFSpace.sm + max(Self.controlHeight, Self.searchButtonSize)
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: VFSpace.sm) {
            contextPill

            Spacer(minLength: VFSpace.sm)

            Button {
                onSearch()
            } label: {
                ZStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                    .frame(width: Self.searchButtonSize, height: Self.searchButtonSize)
                    .aspectRatio(1, contentMode: .fit)
                    .contentShape(Circle())
                    .vfGlass(in: Circle(), interactive: true)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: Self.searchButtonSize, height: Self.searchButtonSize)
            .fixedSize()
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
        //  보통은 앞에 있는 버튼이 터치를 먹고 끝납니다. 하지만 페이저
        //  컨테이너 안의 카드 제스처와 버튼이 서로 다른 레이어에 있으면
        //  두 제스처가 취소되지 않아 양쪽이 다 실행될 수 있습니다.
        //
        //  [1차 시도는 실패했습니다]
        //  카드의 contentShape 에서 이 줄 높이만큼을 뺐습니다.
        //  계산은 맞았습니다. 컨트롤은 topInset+8 부터 topInset+46 까지고
        //  카드에서 뺀 높이도 topInset+46, 좌표계도 같습니다.
        //  그래도 실기에서 카드가 계속 눌렸습니다.
        //  contentShape 은 "이 도형 안에서만 반응해라" 는 요청이고,
        //  페이저 컨테이너 경계를 넘으면 지켜지지 않습니다.
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
        } else if contextIsLoading {
            Button {
                onShowContext?()
            } label: {
                HStack(spacing: VFSpace.xs + 2) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.white)

                    Text("날씨 확인 중")
                        .vfText(.mono)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, VFSpace.md)
                .frame(height: Self.controlHeight)
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

/// 풀폭 사진과 피드 캔버스가 한 화면처럼 이어지게 하는 하단 전환입니다.
///
/// 고정 흰색이나 검정색을 쓰지 않고 동적 피드 색을 사용해 라이트·다크
/// 모드에서 같은 구조를 유지합니다. 마지막 픽셀은 완전히 불투명하게
/// 만들어 Hero 와 다음 섹션 사이의 직선 이음새도 숨깁니다.
private struct HeroFeedBackgroundTransition: View {
    @Environment(\.colorScheme) private var colorScheme

    private var feedBackground: Color {
        Color(uiColor: VFPalette.feedCanvas)
    }

    /// 순검정 피드는 같은 거리에서도 밝기 변화가 더 급하게 느껴집니다.
    /// 다크 모드는 긴 전환을 유지하고, 라이트 모드는 사진 하단을 흐리지
    /// 않도록 마지막 32pt 안에서만 피드 배경과 연결합니다.
    private var transitionHeight: CGFloat {
        colorScheme == .dark ? 96 : 32
    }

    private var gradientStops: [Gradient.Stop] {
        if colorScheme == .dark {
            return [
                .init(color: feedBackground.opacity(0), location: 0),
                .init(color: feedBackground.opacity(0.06), location: 0.26),
                .init(color: feedBackground.opacity(0.20), location: 0.52),
                .init(color: feedBackground.opacity(0.46), location: 0.74),
                .init(color: feedBackground.opacity(0.78), location: 0.91),
                .init(color: feedBackground, location: 1)
            ]
        }

        return [
            .init(color: feedBackground.opacity(0), location: 0),
            .init(color: feedBackground.opacity(0), location: 0.50),
            .init(color: feedBackground.opacity(0.12), location: 0.72),
            .init(color: feedBackground.opacity(0.50), location: 0.92),
            .init(color: feedBackground, location: 1)
        ]
    }

    var body: some View {
        LinearGradient(
            stops: gradientStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: transitionHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hero 사진을 가리지 않고 피드 경계에서 현재 페이지를 알려줍니다.
/// 시각적으로는 작은 점이지만 VoiceOver 에서는 조절 가능한 페이지
/// 컨트롤로 동작해 네이티브 인디케이터의 접근성을 유지합니다.
private struct HomeHeroPageIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: Int
    let count: Int

    private let activeIndicatorWidth: CGFloat = 13
    private let indicatorHeight: CGFloat = 5

    private var indicatorColor: Color {
        Color(uiColor: VFPalette.ink1)
    }

    private var activeOpacity: Double {
        colorScheme == .dark ? 0.94 : 0.76
    }

    private var inactiveOpacity: Double {
        colorScheme == .dark ? 0.46 : 0.28
    }

    private var normalizedSelection: Int {
        min(max(selection, 0), max(count - 1, 0))
    }

    private var accessibleSelection: Binding<Int> {
        Binding(
            get: { normalizedSelection },
            set: { newValue in
                withAnimation(.easeOut(duration: 0.18)) {
                    selection = min(max(newValue, 0), max(count - 1, 0))
                }
            }
        )
    }

    @ViewBuilder
    var body: some View {
        if count > 1 {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    let isSelected = index == normalizedSelection

                    Capsule()
                        .fill(indicatorColor.opacity(isSelected ? activeOpacity : inactiveOpacity))
                        .frame(
                            width: isSelected ? activeIndicatorWidth : indicatorHeight,
                            height: indicatorHeight
                        )
                }
            }
            .frame(height: 18)
            .animation(.easeOut(duration: 0.18), value: normalizedSelection)
            .accessibilityRepresentation {
                Stepper(
                    "추천 출사지 페이지 \(normalizedSelection + 1)/\(count)",
                    value: accessibleSelection,
                    in: 0...(count - 1)
                )
            }
        }
    }
}

private struct HomeHeroCard: View {
    let recommendation: RecommendedSpot
    let distanceText: String?
    let heroReasonTimeText: String?
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
    let isSaved: Bool
    let onToggleSave: () -> Void
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    private var heroReasonItems: [String] {
        var items = [distanceText ?? region]

        if let heroReasonTimeText, !heroReasonTimeText.isEmpty {
            items.append(heroReasonTimeText)
        }

        if let shootingCondition = HomeSpotDisplayFormatter.heroShootingCondition(for: spot),
           !items.contains(shootingCondition) {
            items.append(shootingCondition)
        }

        return Array(items.prefix(3))
    }

    var body: some View {
        VFPhotoTile(
            spot: spot,
            aspectRatio: nil,
            height: size.height,
            cornerRadius: 0,
            showsScrim: true,
            // 제목과 촬영 정보가 놓이는 하단만 보호해 사진의 색과 질감은 유지합니다.
            scrimHeightRatio: 0.44,
            scrimStrength: 1.05,
            showsTopControlScrim: true,
            // Hero 는 상태바(흰 시계/배터리)까지 보호해야 합니다.
            topScrimStrength: 0.62,
            topScrimHeight: 130,
            imageDetail: .hero
        )
        // 사진 크기를 먼저 확정합니다. 이 순서가 중요합니다.
        .frame(width: size.width, height: size.height)
        .clipped()
        // 사진 하단을 피드 배경으로 부드럽게 연결합니다.
        // 순검정 대비가 강한 다크 모드에서는 전환 구간을 더 길게 사용합니다.
        // 텍스트보다 먼저 쌓아 장소명과 이유 한 줄의 대비는 유지합니다.
        .overlay(alignment: .bottom) { HeroFeedBackgroundTransition() }
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
        // 안에서든 틀립니다. 페이저 구현이 바뀌어도 이 도형이 제 역할을
        // 하도록 남겨 둡니다.
        .contentShape(HeroCardTapArea(topExclusion: controlStripHeight))
        .onTapGesture(perform: onSelect)
        .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 24) {
            VFHaptics.save()
            onToggleSave()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(spot.name), \(heroReasonItems.joined(separator: ", "))")
        .accessibilityAction(named: "상세 보기", onSelect)
        .accessibilityAction(named: isSaved ? "저장 해제" : "저장", onToggleSave)
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

            VFMetaLineOnPhoto(items: heroReasonItems)

        }
        .padding(.horizontal, VFSpace.lg)
        // 커스텀 페이지 인디케이터가 하단 중앙에 놓이므로
        // 텍스트가 그 위로 오도록 여백을 확보합니다.
        .padding(.bottom, VFSpace.xxl + VFSpace.sm)
        // 긴 장소명이 카드 밖으로 넘치지 않게 폭을 고정합니다.
        .frame(width: size.width, alignment: .leading)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - HomePhotoCard
//
//  섹션 카드. 사진·캡션 언어는 한 컴포넌트로 통일하되, 우선순위에 따라
//  비율·높이만 달리해 Hero 다음의 시각 리듬을 이어 갑니다.
//
//  [이전 시도]
//  섹션마다 레이아웃을 다르게 해서(3:2 카로셀 / 2:1+1:1 모자이크) 리듬을 만들려 했으나
//  실제 화면에서는 "리듬"이 아니라 "규격이 안 맞는 것"으로 읽혔고,
//  캡션 없는 정사각 타일은 어디인지 알 수 없다는 문제가 있었습니다.
//  통일이 분화보다 낫다는 판단으로 사진 위 캡션과 정보 밀도는 동일하게 유지합니다.
// ═══════════════════════════════════════════════════════════════════

struct HomePhotoCard: View {
    let recommendation: RecommendedSpot
    let aspectRatio: CGFloat?
    /// 첫 우선 레일처럼 비율보다 사진 높이의 존재감이 중요할 때 사용합니다.
    var height: CGFloat? = nil
    var showsMeta: Bool = true
    var metaItems: [String]? = nil
    var cornerRadius: CGFloat = VFRadius.photo
    var scrimHeightRatio: CGFloat = 0.62
    var scrimStrength: Double = 1.15
    let onSelect: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    // 카드마다 "몇 km" 를 붙이면 사진 위에 숫자가 반복되어
    // 훑어볼 때 노이즈가 됩니다. 지역명만 남깁니다.
    private var displayedMetaItems: [String] {
        metaItems ?? [region]
    }

    var body: some View {
        VFPhotoTile(
            spot: spot,
            aspectRatio: aspectRatio,
            height: height,
            cornerRadius: cornerRadius,
            showsScrim: true,
            scrimHeightRatio: scrimHeightRatio,
            scrimStrength: scrimStrength
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
                VFMetaLineOnPhoto(items: displayedMetaItems)
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
}
#endif
