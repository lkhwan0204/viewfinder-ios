import CoreLocation
import Foundation
import SwiftUI
import UIKit

enum SpotDetailSource {
    case home
    case search
    case map
    case community
    case saved

    var detents: Set<PresentationDetent> {
        switch self {
        case .map:
            return [.fraction(0.72), .large]
        case .home, .search, .community, .saved:
            return [.large]
        }
    }

    var isMapContext: Bool {
        self == .map
    }

    var isCompact: Bool {
        self == .map
    }
}

struct SpotDetailPresentation: Identifiable {
    let id = UUID()
    let spot: PhotoSpot
    let source: SpotDetailSource
    /// 마이 → 추가한 장소 → "…" → 수정 으로 열 때 true. 상세가 뜨면 곧바로 장소 편집기를 올립니다.
    var opensPlaceEditor: Bool = false
}

struct SpotDetailView: View {
    @ObservedObject var authViewModel: AuthViewModel
    let spot: PhotoSpot
    let source: SpotDetailSource
    /// true 면 상세 시트가 다 올라온 뒤 장소 편집기를 한 번 엽니다. (SpotDetailPresentation.opensPlaceEditor)
    let opensPlaceEditorOnAppear: Bool
    let isSaved: Bool
    let communityPosts: [CommunityPost]
    let placePhotos: [PlacePhoto]
    let placePhotoGalleryStore: PlacePhotoGalleryStore
    let crowdReports: [CrowdReport]
    @ObservedObject var crowdReportStore: CrowdReportStore
    let currentUserID: String
    let spots: [PhotoSpot]
    /// 거리 표시용. 없으면 거리 지표가 "위치 확인 필요" 로 표시됩니다.
    var userLocation: CLLocationCoordinate2D? = nil
    let onToggleSave: () -> Void
    let onOpenMap: () -> Void
    let onReportPhoto: () -> Void
    /// 혼잡도를 제보하거나 취소합니다. 무엇을 했는지 돌려줘서, 새로 제보했을 때만 한 줄 글 시트를 띄워요.
    let onSubmitCrowdReport: (CommunityPost.Crowd) -> CrowdReportToggleOutcome
    let onSubmitCommunity: (CommunityPostDraft, String) async throws -> Void
    let onUpdateCommunity: (CommunityPost, CommunityPostDraft) async throws -> Void
    let onDeleteCommunity: (CommunityPost) async throws -> Void
    let onUpdatePlace: (PhotoSpot) async throws -> Void
    let onDeletePlace: () async throws -> Void
    @ObservedObject var communityViewModel: CommunityViewModel
    let onToggleCommunityLike: (CommunityPost) -> Void
    let onToggleCommunityFollow: (CommunityPost) -> Void
    let onAddCommunityComment: (String, CommunityPost) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDirectionsDialogPresented = false
    @State private var isCommunityComposerPresented = false
    @State private var editingCommunityPost: CommunityPost?
    @State private var isEditingUserPlace = false
    @State private var isPlaceDeleteConfirmationPresented = false
    @State private var isDeletingPlace = false
    @State private var placeOperationError: String?
    @State private var didOpenPlaceEditorOnAppear = false
    @State private var authenticationDestination: AuthenticationDestination?
    @State private var pendingAuthenticatedAction: (() -> Void)?
    /// 혼잡도를 새로 제보한 뒤 띄우는 한 줄 글 시트.
    @State private var crowdNotePrompt: SpotDetailCrowdNotePrompt?
    /// 혼잡도를 취소하거나 바꾸려는데 이 제보와 함께 올린 글이 있을 때 먼저 묻는 확인.
    @State private var pendingCrowdChange: SpotDetailCrowdChangeRequest?
    /// 함께 올린 글을 지우거나 바꾸는 중. 그동안 혼잡도 버튼을 "저장 중…"으로 잠가요.
    @State private var isApplyingCrowdChange = false
    @State private var crowdChangeError: String?
    @State private var isVisitInformationExpanded = false
    @State private var sessionGalleryPhotos: [PlacePhoto]
    @State private var selectedGalleryIndex = 0

    init(
        authViewModel: AuthViewModel,
        spot: PhotoSpot,
        source: SpotDetailSource,
        opensPlaceEditorOnAppear: Bool = false,
        isSaved: Bool,
        communityPosts: [CommunityPost],
        placePhotos: [PlacePhoto] = [],
        placePhotoGalleryStore: PlacePhotoGalleryStore? = nil,
        crowdReports: [CrowdReport] = [],
        crowdReportStore: CrowdReportStore? = nil,
        currentUserID: String,
        spots: [PhotoSpot],
        userLocation: CLLocationCoordinate2D? = nil,
        onToggleSave: @escaping () -> Void,
        onOpenMap: @escaping () -> Void,
        onReportPhoto: @escaping () -> Void,
        onSubmitCrowdReport: @escaping (CommunityPost.Crowd) -> CrowdReportToggleOutcome = { _ in .ignored },
        onSubmitCommunity: @escaping (CommunityPostDraft, String) async throws -> Void,
        onUpdateCommunity: @escaping (CommunityPost, CommunityPostDraft) async throws -> Void,
        onDeleteCommunity: @escaping (CommunityPost) async throws -> Void,
        onUpdatePlace: @escaping (PhotoSpot) async throws -> Void = { _ in },
        onDeletePlace: @escaping () async throws -> Void = {},
        communityViewModel: CommunityViewModel? = nil,
        onToggleCommunityLike: @escaping (CommunityPost) -> Void = { _ in },
        onToggleCommunityFollow: @escaping (CommunityPost) -> Void = { _ in },
        onAddCommunityComment: @escaping (String, CommunityPost) -> Bool = { _, _ in false }
    ) {
        self.authViewModel = authViewModel
        self.spot = spot
        self.source = source
        self.opensPlaceEditorOnAppear = opensPlaceEditorOnAppear
        self.isSaved = isSaved
        self.communityPosts = communityPosts
        self.placePhotos = placePhotos
        self.placePhotoGalleryStore = placePhotoGalleryStore ?? .shared
        self.crowdReports = crowdReports
        self._crowdReportStore = ObservedObject(wrappedValue: crowdReportStore ?? .shared)
        self.currentUserID = currentUserID
        self.spots = spots
        self.userLocation = userLocation
        self.onToggleSave = onToggleSave
        self.onOpenMap = onOpenMap
        self.onReportPhoto = onReportPhoto
        self.onSubmitCrowdReport = onSubmitCrowdReport
        self.onSubmitCommunity = onSubmitCommunity
        self.onUpdateCommunity = onUpdateCommunity
        self.onDeleteCommunity = onDeleteCommunity
        self.onUpdatePlace = onUpdatePlace
        self.onDeletePlace = onDeletePlace
        self._communityViewModel = ObservedObject(wrappedValue: communityViewModel ?? CommunityViewModel())
        self.onToggleCommunityLike = onToggleCommunityLike
        self.onToggleCommunityFollow = onToggleCommunityFollow
        self.onAddCommunityComment = onAddCommunityComment
        _sessionGalleryPhotos = State(
            initialValue: PlacePhotoPool.select(
                from: placePhotos.isEmpty ? PlacePhotoPool.candidates(for: spot) : placePhotos
            )
        )
    }

    private var isDetailOverlayPresented: Bool {
        isDirectionsDialogPresented
            || isCommunityComposerPresented
            || crowdNotePrompt != nil
            || pendingCrowdChange != nil
            || authenticationDestination != nil
            || isPlaceDeleteConfirmationPresented
            || isDeletingPlace
    }

    private var isCrowdReportSubmitting: Bool {
        guard !currentUserID.isEmpty else { return false }
        return crowdReportStore.isSubmitting(
            placeID: spot.id,
            authorID: currentUserID
        )
    }

    private var isCrowdReportLoading: Bool {
        crowdReportStore.isLoading(placeID: spot.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = detailHorizontalPadding
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: source.isCompact ? 14 : 20) {
                        SpotDetailPhotoGallery(
                            spot: spot,
                            photos: sessionGalleryPhotos,
                            selectedIndex: $selectedGalleryIndex,
                            height: heroHeight(in: proxy.size),
                            cornerRadius: source.isMapContext ? AppLayout.cardCornerRadius : 0,
                            showsBorder: source.isMapContext,
                            onReportPhoto: {
                                requireAuthentication(action: onReportPhoto)
                            }
                        )
                            // 사진 진입(전체 화면)에서는 화면 폭을 꽉 채웁니다.
                            // 음수 패딩으로 부모의 좌우 마진을 상쇄합니다.
                            .frame(width: source.isMapContext ? contentWidth : proxy.size.width)

                            .padding(
                                .horizontal,
                                source.isMapContext ? 0 : -horizontalPadding
                            )

                        header
                        shootingConditions
                        visitInformation

                        if !source.isMapContext {
                            mapPreview
                        }

                        SpotDetailCommunitySection(
                            spot: spot,
                            posts: communityPosts,
                            crowdReports: crowdReports,
                            currentUserID: currentUserID,
                            spots: spots,
                            isCrowdReportSubmitting: isCrowdReportSubmitting || isApplyingCrowdChange,
                            isCrowdReportLoading: isCrowdReportLoading,
                            onReportCrowd: { crowd in
                                requireAuthentication {
                                    handleCrowdTap(crowd)
                                }
                            },
                            onEdit: { post in
                                requireAuthentication {
                                    editingCommunityPost = post
                                    isCommunityComposerPresented = true
                                }
                            },
                            onDelete: { post in
                                try await onDeleteCommunity(post)
                            },
                            communityViewModel: communityViewModel,
                            onToggleLike: { post in
                                requireAuthentication {
                                    onToggleCommunityLike(post)
                                }
                            },
                            onToggleFollow: { post in
                                requireAuthentication {
                                    onToggleCommunityFollow(post)
                                }
                            },
                            onAddComment: { message, post in
                                onAddCommunityComment(message, post)
                            }
                        )
                        // 혼잡도를 취소하거나 바꿀 때 이 제보와 함께 올린 글이 있으면 먼저 물어봐요.
                        // 상세 본문 끝의 확인 · 알림과 섞이지 않게 이 섹션에 붙입니다.
                        .confirmationDialog(
                            crowdChangeDialogTitle,
                            isPresented: Binding(
                                get: { pendingCrowdChange != nil },
                                set: { if !$0 { pendingCrowdChange = nil } }
                            ),
                            titleVisibility: .visible,
                            presenting: pendingCrowdChange
                        ) { request in
                            crowdChangeDialogActions(for: request)
                        } message: { request in
                            Text(crowdChangeDialogMessage(for: request))
                        }
                        .alert(
                            "처리하지 못했어요",
                            isPresented: Binding(
                                get: { crowdChangeError != nil },
                                set: { if !$0 { crowdChangeError = nil } }
                            )
                        ) {
                            Button("확인", role: .cancel) { crowdChangeError = nil }
                        } message: {
                            Text(crowdChangeError ?? "다시 시도해 주세요.")
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    // full-bleed 사진이 화면 최상단에 붙어야 하므로
                    // 전체 화면일 때는 상단 여백을 두지 않습니다.
                    .padding(.top, source.isMapContext ? 12 : 0)
                    .padding(.bottom, actionBarOverlayReserve)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: proxy.size.width)

                actionBar
                    .frame(width: proxy.size.width)
                    .padding(.bottom, actionBarBottomPadding)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .accessibilityHidden(isDetailOverlayPresented)
        .background(AppColors.background.ignoresSafeArea())
        .confirmationDialog("길찾기 앱 선택", isPresented: $isDirectionsDialogPresented, titleVisibility: .visible) {
            ForEach(MapProvider.allCases) { provider in
                Button(provider.title) {
                    openDirections(with: provider)
                }
            }

            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("장소를 삭제할까요?", isPresented: $isPlaceDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("장소 삭제", role: .destructive) {
                deleteOwnedPlace()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("장소를 공개 목록에서 숨깁니다. 게시물과 기존 사진은 삭제되지 않아요.")
        }
        .alert("장소 작업을 완료하지 못했어요", isPresented: Binding(
            get: { placeOperationError != nil },
            set: { if !$0 { placeOperationError = nil } }
        )) {
            Button("확인", role: .cancel) { placeOperationError = nil }
        } message: {
            Text(placeOperationError ?? "다시 시도해 주세요.")
        }
        .sheet(isPresented: $isCommunityComposerPresented) {
            CommunityComposerView(
                spots: spots,
                selectedSpot: spot,
                locksSelectedSpot: true,
                editingPost: editingCommunityPost,
                purpose: isEditingUserPlace ? .editPlace(placeID: spot.id) : .fieldReport,
                onSubmit: { draft, submissionID in
                    if isEditingUserPlace {
                        guard let updatedSpot = draft.spot, updatedSpot.id == spot.id else {
                            throw PlacesRepositoryError.invalidDocument
                        }
                        try await onUpdatePlace(updatedSpot)
                        isEditingUserPlace = false
                    } else if let editingCommunityPost {
                        try await onUpdateCommunity(editingCommunityPost, draft)
                    } else {
                        try await onSubmitCommunity(draft, submissionID)
                    }
                    self.editingCommunityPost = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $crowdNotePrompt) { prompt in
            SpotDetailCrowdNoteSheet(
                spot: spot,
                crowd: prompt.crowd,
                authorID: prompt.authorID,
                crowdReportStore: crowdReportStore,
                onSubmit: onSubmitCommunity
            )
        }
        .fullScreenCover(
            item: $authenticationDestination,
            onDismiss: resumePendingAuthenticatedActionIfPossible
        ) { _ in
            LoginView(authViewModel: authViewModel)
        }
        .task(id: spot.id) {
            let loadedPhotos = await placePhotoGalleryStore.load(for: spot)
            sessionGalleryPhotos = PlacePhotoPool.select(
                from: loadedPhotos.isEmpty ? PlacePhotoPool.candidates(for: spot) : loadedPhotos
            )
            selectedGalleryIndex = min(selectedGalleryIndex, max(sessionGalleryPhotos.count - 1, 0))
            await crowdReportStore.load(for: spot)
        }
        .background {
            // 마이에서 "수정" 으로 열었을 때만 붙습니다. 상세가 다 올라오면 장소 편집기를 엽니다.
            if opensPlaceEditorOnAppear {
                SpotDetailDidAppearObserver(onDidAppear: { openPlaceEditorIfRequested() })
            }
        }
        .task {
            // 위 관찰자가 알려주지 못했을 때를 위한 대비입니다. 시트가 넉넉히 다 올라왔을 때 한 번 더 봅니다.
            // 이미 열었으면 아무것도 하지 않습니다. 그 사이 상세를 닫았으면 열지 않습니다.
            guard opensPlaceEditorOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            openPlaceEditorIfRequested()
        }
    }

    /// 장소 정보 수정. 오른쪽 위 "…" 메뉴와, 마이에서 "수정" 으로 들어왔을 때 같은 길로 엽니다.
    private func beginEditingOwnedPlace() {
        requireAuthentication {
            editingCommunityPost = nil
            isEditingUserPlace = true
            isCommunityComposerPresented = true
        }
    }

    /// 마이 → 추가한 장소 → "…" → 수정. 상세가 다 올라온 뒤 장소 편집기를 한 번 엽니다.
    ///
    /// 편집기를 닫고 상세에 남아 있을 때 다시 열리지 않습니다.
    /// 저장 · 오류 · 로그인 처리는 오른쪽 위 "…" 메뉴로 열 때와 같습니다.
    private func openPlaceEditorIfRequested() {
        guard opensPlaceEditorOnAppear, !didOpenPlaceEditorOnAppear, isCurrentUserPlace else { return }
        didOpenPlaceEditorOnAppear = true
        beginEditingOwnedPlace()
    }

    /// 혼잡도 버튼을 눌렀을 때. 지금 내 제보가 내가 올린 글과 연결돼 있으면 먼저 물어봐요.
    /// - 같은 단계를 다시 눌러 취소: 글도 지울지
    /// - 다른 단계로 바꾸기: 글의 혼잡도도 바꿀지 (잘못 누른 건지, 실제로 상황이 바뀐 건지 앱은 모르니까요)
    /// 그 밖에는 바로 제보 · 취소 · 변경해요.
    ///
    /// 로그인한 뒤 이어서 실행될 때도 있어서, 사용자는 authViewModel 에서 바로 읽습니다.
    private func handleCrowdTap(_ crowd: CommunityPost.Crowd) {
        guard let authorID = authViewModel.currentUser?.id else {
            reportCrowdAndOfferNote(crowd)
            return
        }

        let ownPosts = communityPosts.filter { $0.relatedSpotID == spot.id && $0.authorID == authorID }
        guard let question = SpotDetailCrowdLinkedPostPolicy.question(
            tapped: crowd,
            reports: crowdReports,
            placeID: spot.id,
            userID: authorID,
            ownPostIDs: Set(ownPosts.map(\.id)),
            now: Date(),
            freshnessWindow: CrowdReportStore.freshnessWindow
        ),
              let post = ownPosts.first(where: { $0.id == question.postID }) else {
            reportCrowdAndOfferNote(crowd)
            return
        }

        pendingCrowdChange = SpotDetailCrowdChangeRequest(tapped: crowd, question: question, post: post)
    }

    private var crowdChangeDialogTitle: String {
        guard let request = pendingCrowdChange else { return "" }
        switch request.question {
        case .cancel:
            return "혼잡도 제보를 취소할까요?"
        case .change:
            let name = request.tapped.displayName
            return "\(name)\(SpotDetailCrowdNotePolicy.directionalParticle(after: name)) 바꿀까요?"
        }
    }

    private func crowdChangeDialogMessage(for request: SpotDetailCrowdChangeRequest) -> String {
        switch request.question {
        case .cancel:
            return "이 제보와 함께 올린 글이 있어요. 글도 삭제하면 커뮤니티에서 사라져요."
        case .change(_, let previous):
            let name = previous.displayName
            return "함께 올린 글에는 \"작성 당시 \(name)\"\(SpotDetailCrowdNotePolicy.directionalParticle(after: name)) 남아 있어요."
        }
    }

    @ViewBuilder
    private func crowdChangeDialogActions(for request: SpotDetailCrowdChangeRequest) -> some View {
        switch request.question {
        case .cancel:
            Button("글도 함께 삭제", role: .destructive) {
                deleteLinkedPost(request.post)
            }
            Button("제보만 취소") {
                reportCrowdAndOfferNote(request.tapped)
            }
        case .change:
            let name = request.tapped.displayName
            Button("글도 \(name)\(SpotDetailCrowdNotePolicy.directionalParticle(after: name)) 바꾸기") {
                changeLinkedPostCrowd(request.post, to: request.tapped)
            }
            Button("제보만 바꾸기") {
                reportCrowdAndOfferNote(request.tapped)
            }
        }
        Button("닫기", role: .cancel) {}
    }

    /// "글도 ○○으로 바꾸기". 글 내용은 그대로 두고 혼잡도만 바꿔요.
    ///
    /// 글을 고치면 CommunityViewModel.updatePost 가 쓴 지 1시간 안의 글만 현재 혼잡도에 반영해요.
    /// 그보다 오래된 글이면 제보는 따로 바꿔요(그러면 글과의 연결은 풀려요).
    private func changeLinkedPostCrowd(_ post: CommunityPost, to crowd: CommunityPost.Crowd) {
        isApplyingCrowdChange = true
        let draft = CommunityPostDraft(
            spot: spot,
            title: post.title,
            captureLocation: post.captureLocation,
            message: post.message,
            tags: post.tags,
            photoAttachments: post.photoAttachments,
            crowd: crowd
        )

        Task {
            do {
                try await onUpdateCommunity(post, draft)
                let postUpdatesLiveCrowd = CommunityViewModel.editRefreshesLiveCrowd(
                    postCreatedAt: post.createdAt,
                    now: Date(),
                    freshnessWindow: CrowdReportStore.freshnessWindow
                )
                if !postUpdatesLiveCrowd {
                    _ = onSubmitCrowdReport(crowd)
                }
                VFHaptics.success()
            } catch {
                if let communityError = error as? FirebaseCommunityError,
                   case .crowdReportPending = communityError {
                    crowdChangeError = "글은 바꿨지만 혼잡도 제보는 바꾸지 못했어요. 혼잡도를 다시 눌러 주세요."
                } else {
                    crowdChangeError = "글을 바꾸지 못했어요. 혼잡도 제보도 그대로 있어요. 다시 시도해 주세요."
                }
                VFHaptics.error()
                AppLog.persistence.error(
                    "Linked post crowd change failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            isApplyingCrowdChange = false
        }
    }

    /// "글도 함께 삭제". 글을 지우면 이 글과 연결된 혼잡도 제보도 같이 지워져요
    /// (CommunityViewModel.deletePost → CrowdReportStore.removeCommunityReport).
    private func deleteLinkedPost(_ post: CommunityPost) {
        isApplyingCrowdChange = true
        Task {
            do {
                try await onDeleteCommunity(post)
                VFHaptics.success()
            } catch {
                crowdChangeError = "글을 삭제하지 못했어요. 혼잡도 제보도 그대로 있어요. 다시 시도해 주세요."
                VFHaptics.error()
                AppLog.persistence.error(
                    "Linked post delete failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            isApplyingCrowdChange = false
        }
    }

    /// 혼잡도를 제보하고, 새로 제보했으면 한 줄 글 시트를 띄웁니다.
    ///
    /// 로그인하지 않았으면 로그인한 뒤 이어서 실행돼요(requireAuthentication). 그때는
    /// 이 화면이 로그인 전 값을 들고 있을 수 있어서, 사용자는 authViewModel 에서 바로 읽습니다.
    private func reportCrowdAndOfferNote(_ crowd: CommunityPost.Crowd) {
        let outcome = onSubmitCrowdReport(crowd)
        guard let authorID = authViewModel.currentUser?.id else { return }

        let recentOwnPostDates = communityPosts
            .filter { $0.relatedSpotID == spot.id && $0.authorID == authorID }
            .map(\.createdAt)
        guard SpotDetailCrowdNotePolicy.shouldOffer(
            outcome: outcome,
            recentOwnPostDates: recentOwnPostDates,
            now: Date(),
            freshnessWindow: CrowdReportStore.freshnessWindow
        ) else { return }

        crowdNotePrompt = SpotDetailCrowdNotePrompt(crowd: crowd, authorID: authorID)
    }

    private func requireAuthentication(action: @escaping () -> Void) {
        guard !authViewModel.isAuthenticated else {
            action()
            return
        }

        pendingAuthenticatedAction = action
        authViewModel.prepareForSignInPresentation()
        authenticationDestination = .signIn
    }

    private func resumePendingAuthenticatedActionIfPossible() {
        guard authViewModel.isAuthenticated else {
            pendingAuthenticatedAction = nil
            return
        }

        let action = pendingAuthenticatedAction
        pendingAuthenticatedAction = nil
        DispatchQueue.main.async {
            guard authViewModel.isAuthenticated else { return }
            action?()
        }
    }

    /// 대표 사진 높이.
    ///
    /// 전체 화면에서는 화면 높이의 44% 를 씁니다. 홈 Hero(72%)보다는 작지만
    /// 사진이 먼저 눈에 들어오고, 아래 정보도 함께 보이는 균형점입니다.
    private func heroHeight(in size: CGSize) -> CGFloat {
        if source.isCompact {
            return 172
        }
        return max(300, size.height * 0.44)
    }

    private var detailHorizontalPadding: CGFloat {
        source.isCompact ? 14 : AppLayout.pageHorizontalPadding
    }

    private var actionBarOverlayReserve: CGFloat {
        actionButtonHeight + actionBarBottomPadding + (source.isCompact ? 16 : 18)
    }

    private var actionBarBottomPadding: CGFloat {
        source.isCompact ? 15 : 17
    }

    @ViewBuilder
    private var actionBar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtons
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                    )
            }
            .padding(.horizontal, source.isCompact ? 14 : 18)
        } else {
            actionButtons
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                        .stroke(AppColors.divider.opacity(0.82), lineWidth: 1)
                )
                .padding(.horizontal, source.isCompact ? 14 : 18)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            if !source.isMapContext {
                Button {
                    dismiss()
                    onOpenMap()
                } label: {
                    DetailActionButton(title: "지도에서 보기", symbolName: "map.fill", isPrimary: false, height: actionButtonHeight)
                }
                .buttonStyle(.plain)
            }

            if !source.isMapContext {
                NativeActionDivider()
            }

            Button {
                isDirectionsDialogPresented = true
            } label: {
                DetailActionButton(title: "길찾기", symbolName: "location.fill", isPrimary: true, height: actionButtonHeight)
            }
            .buttonStyle(.plain)

        }
    }

    private var actionButtonHeight: CGFloat {
        AppLayout.touchTarget
    }

    private var actionBarCornerRadius: CGFloat {
        source.isCompact ? 22 : 24
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: source.isCompact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(source.isCompact ? AppTypography.sectionTitle : AppTypography.prominentCardTitle)
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(HomeSpotDisplayFormatter.region(for: spot))
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    VFSaveButton(
                        isSaved: isSaved,
                        action: onToggleSave,
                        diameter: 30,
                        style: .plain
                    )

                    if isCurrentUserPlace {
                        Menu {
                            Button {
                                beginEditingOwnedPlace()
                            } label: {
                                Label("장소 정보 수정", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                isPlaceDeleteConfirmationPresented = true
                            } label: {
                                Label("장소 삭제", systemImage: "trash")
                            }
                            .disabled(isDeletingPlace)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 36, height: 36)
                                .background(.thinMaterial, in: Circle())
                                // 보이는 원은 36pt 그대로, 누를 수 있는 영역만 44pt 로 넓힙니다. (개선안 41)
                                // 원은 44pt 영역 가운데에 놓여 전보다 4pt 안쪽에 보입니다.
                                .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("내 장소 관리")
                    }
                }
                .offset(y: -4)
            }

            Text(spot.summary)
                .font(source.isCompact ? AppTypography.metadata : AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(source.isCompact ? 2 : 2)
                .lineSpacing(1)

            VFMetaLine(items: decisionSummaryItems)

            HStack(spacing: 6) {
                ForEach(spot.hashtags.prefix(2), id: \.self) { tag in
                    Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
    }

    private var isCurrentUserPlace: Bool {
        spot.isOwned(by: currentUserID)
    }

    private func deleteOwnedPlace() {
        guard isCurrentUserPlace, !isDeletingPlace else { return }
        isDeletingPlace = true
        Task { @MainActor in
            do {
                try await onDeletePlace()
                isDeletingPlace = false
                dismiss()
            } catch {
                isDeletingPlace = false
                placeOperationError = error.localizedDescription
            }
        }
    }

    private func openDirections(with provider: MapProvider) {
        let appURL = spot.directionsURL(for: provider)
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
        } else {
            openURL(spot.fallbackDirectionsURL(for: provider))
        }
    }

    private var shootingConditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "촬영 가이드",
                subtitle: "현장에서 바로 판단할 수 있는 정보예요"
            )

            LazyVGrid(
                columns: shootingConditionColumns,
                spacing: 10
            ) {
                SpotShootingMetric(
                    symbolName: "clock.fill",
                    title: "추천 시간",
                    value: HomeSpotDisplayFormatter.bestTime(spot.bestTime)
                )
                SpotShootingMetric(
                    symbolName: "clock.badge.checkmark.fill",
                    title: "이용 시간",
                    value: openingHoursMetricValue
                )
            }
            SpotShootingMetric(
                symbolName: "cloud.sun.fill",
                title: "날씨 궁합",
                value: spot.weatherFit
            )
        }
    }

    private var decisionSummaryItems: [String] {
        [
            VFSpotDistance.text(from: userLocation, to: spot)
                ?? HomeSpotDisplayFormatter.region(for: spot),
            HomeSpotDisplayFormatter.bestTime(spot.bestTime)
        ]
    }

    private var shootingConditionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    /// 지금 들어갈 수 있는지. 사진가가 출발 전 가장 먼저 확인하는 정보입니다.
    ///
    /// 기존에는 "방문 전 확인" 접힌 영역 안에만 있어서 잘 보이지 않았습니다.
    /// 촬영 가이드로 끌어올리고 접힌 영역에서는 제거했습니다.
    private var openingHoursMetricValue: String {
        let hours = spot.openingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        return hours.isEmpty ? "정보 없음" : hours
    }

    private var visitInformation: some View {
        DisclosureGroup(isExpanded: $isVisitInformationExpanded) {
            VStack(spacing: 14) {
                // "추천 이유"(eventTitle) 행을 제거했습니다.
                // 이 섹션은 운영시간/비용/주차를 확인하는 곳이라
                // 추천 이유가 들어갈 자리가 아니었습니다.
                DetailInfoRow(symbolName: "ticket.fill", title: "입장/비용", value: spot.feeInfo, tint: AppColors.secondaryText)
                DetailInfoRow(
                    symbolName: "parkingsign.circle.fill",
                    title: "주차",
                    value: "\(spot.parkingInfo) · \(spot.nearbyParkingInfo)",
                    tint: AppColors.secondaryText
                )
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text("방문 전 확인")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.primary)
                    Text("비용과 주차 정보를 확인하세요")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .tint(AppColors.accent)
        .padding(16)
        .appCardSurface()
    }

    private var mapPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "위치 미리보기",
                subtitle: HomeSpotDisplayFormatter.region(for: spot)
            )

            SpotHeroMap(spot: spot)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.mediaCornerRadius, style: .continuous))
        }
    }
}

/// 상세 시트가 다 올라온 뒤(UIKit viewDidAppear) 한 번 알려줍니다.
///
/// 시트가 올라오는 도중에 그 위로 편집기 시트를 띄우면 UIKit 이 무시해서 편집기가 뜨지 않습니다.
/// 시간을 어림해 기다리는 대신, 올라오기를 마친 순간을 받습니다.
/// (커뮤니티 편집기의 CommunityDismissAttemptObserver 와 같은 방식)
private struct SpotDetailDidAppearObserver: UIViewControllerRepresentable {
    let onDidAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onDidAppear = onDidAppear
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onDidAppear = onDidAppear
    }

    final class Controller: UIViewController {
        var onDidAppear: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            // 화면 뒤에 깔리는 빈 칸입니다. 누름을 받지 않습니다.
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // 나타나기 처리 중에 바로 띄우지 않고 다음 차례에 띄웁니다.
            DispatchQueue.main.async { [weak self] in
                self?.onDidAppear?()
            }
        }
    }
}

struct SpotDetailHeroImage: View {
    let spot: PhotoSpot
    let height: CGFloat
    /// full-bleed 로 쓸 때는 0. 지도 시트에서는 카드처럼 둥글게.
    var cornerRadius: CGFloat = AppLayout.cardCornerRadius
    /// full-bleed 에서는 테두리를 그리지 않습니다.
    var showsBorder: Bool = true
    let onReportPhoto: () -> Void

    var body: some View {
        Group {
            if spot.hasReliableDisplayImage {
                ZStack(alignment: .bottomTrailing) {
                    // 상세 화면 대표 사진은 화면 폭을 채우므로 hero 해상도로 받습니다.
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 34,
                        targetPixelWidth: VFPhotoDetail.hero.pixelWidth
                    )

                    if let attributionText {
                        Text(attributionText)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(.black.opacity(0.42), in: Capsule())
                            .padding(8)
                    }
                }
            } else {
                Button(action: onReportPhoto) {
                    ZStack(alignment: .bottom) {
                        MissingSpotPhotoPrompt(layout: .hero)

                        Text("대표 사진 제보")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(AppColors.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                            .padding(.bottom, 15)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var attributionText: String? {
        guard let credit = spot.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credit.isEmpty else {
            return nil
        }

        if let license = spot.imageLicense?.trimmingCharacters(in: .whitespacesAndNewlines),
           !license.isEmpty {
            return "\(credit) · \(license)"
        }

        return credit
    }
}

struct SpotDetailPhotoGallery: View {
    let spot: PhotoSpot
    let photos: [PlacePhoto]
    @Binding var selectedIndex: Int
    let height: CGFloat
    var cornerRadius: CGFloat = AppLayout.cardCornerRadius
    var showsBorder: Bool = true
    let onReportPhoto: () -> Void

    var body: some View {
        Group {
            if photos.isEmpty {
                Button(action: onReportPhoto) {
                    ZStack(alignment: .bottom) {
                        MissingSpotPhotoPrompt(layout: .hero)

                        Text("대표 사진 제보")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(AppColors.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                            .padding(.bottom, 15)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            SpotDetailGalleryImage(photo: photo)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    VStack {
                        HStack {
                            Spacer(minLength: 0)

                            Button(action: onReportPhoto) {
                                Label("사진 추가", systemImage: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(.black.opacity(0.46), in: Capsule())
                                    // 보이는 캡슐은 28pt 그대로, 누를 수 있는 영역만 44pt 로 넓힙니다. (개선안 41)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("이 장소에 사진 추가")
                        }

                        Spacer(minLength: 0)
                    }
                    // 위쪽 여백 10pt = 2pt + 넓힌 터치 영역 8pt. 캡슐 위치는 전과 같습니다.
                    .padding(.horizontal, 10)
                    .padding(.top, 2)

                    HStack(spacing: 8) {
                        if let attributionText {
                            Text(attributionText)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(.black.opacity(0.42), in: Capsule())
                        }

                        if photos.count > 1 {
                            Text("\(min(selectedIndex + 1, photos.count)) / \(photos.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(.black.opacity(0.48), in: Capsule())
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var attributionText: String? {
        guard let credit = spot.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credit.isEmpty else {
            return nil
        }

        if let license = spot.imageLicense?.trimmingCharacters(in: .whitespacesAndNewlines),
           !license.isEmpty {
            return "\(credit) · \(license)"
        }

        return credit
    }
}

private struct SpotDetailGalleryImage: View {
    let photo: PlacePhoto
    @State private var revealedRemoteImageKey: String?

    var body: some View {
        Group {
            if let imageData = photo.imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageName = photo.imageName,
                      let image = UIImage(named: imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = photo.imageURL {
                AsyncImage(
                    url: imageURL,
                    transaction: Transaction(animation: .easeOut(duration: 0.18))
                ) { phase in
                    ZStack {
                        placeholderSurface

                        switch phase {
                        case .empty:
                            EmptyView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .opacity(revealedRemoteImageKey == imageURL.absoluteString ? 1 : 0)
                                .onAppear {
                                    guard revealedRemoteImageKey != imageURL.absoluteString else { return }
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        revealedRemoteImageKey = imageURL.absoluteString
                                    }
                                }
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                }
                .onChange(of: imageURL) { _, newURL in
                    guard revealedRemoteImageKey != newURL.absoluteString else { return }
                    revealedRemoteImageKey = nil
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        placeholderSurface
            .overlay {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText.opacity(0.58))
            }
    }

    private var placeholderSurface: some View {
        AppColors.mutedSurface
            .overlay {
                Rectangle()
                    .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
            }
    }
}

struct SpotHeroMap: View {
    let spot: PhotoSpot

    var body: some View {
        // 기존에는 allowsHitTesting(false) 로 지도가 완전히 상호작용 불가였습니다.
        // 위치만 확인할 수 있었고 확대/축소가 아예 되지 않았습니다.
        //
        // 핀치 확대/축소와 확대 버튼은 켜고, 지도 패닝(드래그)은 끕니다.
        // 상세 화면이 세로 스크롤 시트라서 지도 패닝을 허용하면
        // 지도 위에서 손가락을 움직일 때 화면 스크롤이 막힙니다.
        // 위치를 옮겨서 둘러보는 것은 "지도에서 보기" 전체 지도에서 하도록 유도합니다.
        NaverSpotPreviewMap(spot: spot, allowsZoom: true)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
    }
}

func communityRelativeTimeText(for date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "방금 전"
    }

    let minutes = Int(interval / 60)
    if minutes < 60 {
        return "\(minutes)분 전"
    }

    let hours = Int(interval / (60 * 60))
    if hours < 24 {
        return "\(hours)시간 전"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "M월 d일"
    return formatter.string(from: date)
}

func communityAbsoluteTimeText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy.MM.dd a h:mm"
    return formatter.string(from: date)
}

func communityWrittenTimeText(for date: Date) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "ko_KR")
    timeFormatter.dateFormat = "a h:mm"
    let timeText = timeFormatter.string(from: date)

    if Calendar.current.isDateInToday(date) {
        return "오늘 \(timeText) 작성"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제 \(timeText) 작성"
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.dateFormat = "M월 d일"
    return "\(dateFormatter.string(from: date)) \(timeText) 작성"
}

struct SpotDetailCommunitySection: View {
    let spot: PhotoSpot
    let posts: [CommunityPost]
    let crowdReports: [CrowdReport]
    let currentUserID: String
    let spots: [PhotoSpot]
    let isCrowdReportSubmitting: Bool
    let isCrowdReportLoading: Bool
    let onReportCrowd: (CommunityPost.Crowd) -> Void
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) async throws -> Void
    @ObservedObject var communityViewModel: CommunityViewModel
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool

    @State private var isCommunityPostsPresented = false

    private var relatedCommunityPosts: [CommunityPost] {
        var seenIDs = Set<String>()

        return posts
            .filter { $0.relatedSpotID == spot.id }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seenIDs.insert($0.id).inserted }
    }

    private var selectedCrowd: CommunityPost.Crowd? {
        Self.currentUserSelection(
            in: crowdReports,
            placeID: spot.id,
            userID: currentUserID,
            now: Date(),
            freshnessWindow: CrowdReportStore.freshnessWindow
        )
    }

    /// 내가 지금 고른 혼잡도. 현장 정보가 유효한 시간(1시간) 안의 내 제보만 봅니다.
    ///
    /// 전에는 제보가 없으면 1시간 안에 쓴 내 글의 혼잡도로 대신했어요(아주 예전 앱은 제보 없이
    /// 글에만 혼잡도를 넣었어요). 지금은 글을 올릴 때 늘 제보도 함께 저장해서 그럴 일이 없고,
    /// 오히려 제보를 취소해도 방금 쓴 글 때문에 선택이 그대로 남아 취소가 안 되는 것처럼 보였어요.
    /// 글의 혼잡도는 글에 "작성 당시"로만 보여줘요.
    static func currentUserSelection(
        in reports: [CrowdReport],
        placeID: String,
        userID: String,
        now: Date,
        freshnessWindow: TimeInterval
    ) -> CommunityPost.Crowd? {
        guard !userID.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-freshnessWindow)
        return reports
            .filter { $0.placeID == placeID && $0.authorID == userID && $0.updatedAt >= cutoff }
            .max { $0.updatedAt < $1.updatedAt }?
            .crowd
    }

    /// 장소의 현재 혼잡도. 최근 1시간 안의 제보만 셉니다. 글은 세지 않아요(위와 같은 이유로,
    /// 제보를 취소해도 글 때문에 "현재 혼잡도"에 그대로 남았어요).
    private var recentCrowdSummary: CrowdReportSummary? {
        VFLiveCrowd.summary(spot: spot, reports: crowdReports)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실시간 현장 정보")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.primary)

            VStack(alignment: .leading, spacing: 14) {
                // 현재 상태를 먼저 보여주고, 바로 아래에서 사용자가
                // 자신의 현장 상태를 선택하도록 한 덩어리로 묶습니다.
                CommunityCrowdSummaryCard(summary: recentCrowdSummary)

                SpotDetailCrowdReportControl(
                    selection: selectedCrowd,
                    isSaving: isCrowdReportSubmitting,
                    isLoading: isCrowdReportLoading,
                    onSelect: onReportCrowd
                )
            }
            .padding(12)
            .appCardSurface()

            if !relatedCommunityPosts.isEmpty {
                Button {
                    isCommunityPostsPresented = true
                } label: {
                    SpotDetailCommunityEntryCard(postCount: relatedCommunityPosts.count)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isCommunityPostsPresented) {
                    SpotCommunityPostsSheet(
                        spot: spot,
                        posts: relatedCommunityPosts,
                        spots: spots,
                        currentUserID: currentUserID,
                        communityViewModel: communityViewModel,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onToggleLike: onToggleLike,
                        onToggleFollow: onToggleFollow,
                        onAddComment: onAddComment
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

}

private struct SpotDetailCommunityEntryCard: View {
    let postCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text("커뮤니티에서 이 장소")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.primary)

                Text("최근 언급 \(postCount)개를 확인해보세요")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("커뮤니티에서 이 장소, 최근 언급 \(postCount)개 보기")
    }
}

private struct SpotCommunityPostsSheet: View {
    private static let initialLimit = 5
    private static let maximumLimit = 10

    let spot: PhotoSpot
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let currentUserID: String
    @ObservedObject var communityViewModel: CommunityViewModel
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) async throws -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var visiblePostCount = SpotCommunityPostsSheet.initialLimit

    private var orderedPosts: [CommunityPost] {
        var seenIDs = Set<String>()

        return posts
            .filter { $0.relatedSpotID == spot.id }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seenIDs.insert($0.id).inserted }
            .prefix(Self.maximumLimit)
            .map { $0 }
    }

    private var visiblePosts: [CommunityPost] {
        Array(orderedPosts.prefix(min(visiblePostCount, Self.maximumLimit)))
    }

    private var canShowMore: Bool {
        visiblePosts.count < orderedPosts.count
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: VFSpace.md) {
                    ForEach(visiblePosts) { post in
                        NavigationLink(value: post.id) {
                            SpotCommunityPostRow(post: post, spot: spot)
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowMore {
                        Button {
                            visiblePostCount = min(visiblePostCount + Self.initialLimit, Self.maximumLimit)
                        } label: {
                            Text("더 보기")
                                .vfText(.callout.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.md)
                .vfScrollBottomInset()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("커뮤니티에서 이 장소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 닫기는 앱 전체에서 오른쪽 위 X 예요(로그인 · 사진 뷰어 · 글쓰기와 같아요).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                }
            }
            .navigationDestination(for: String.self) { postID in
                if let post = orderedPosts.first(where: { $0.id == postID }) {
                    CommunityPostDetailView(
                        post: post,
                        spot: spot,
                        captureLocationSpot: captureLocationSpot(for: post),
                        currentUserID: currentUserID,
                        isLiked: communityViewModel.isLiked(post),
                        likeCount: post.likeCount + (communityViewModel.isLiked(post) ? 1 : 0),
                        isFollowing: communityViewModel.isFollowing(post),
                        comments: communityViewModel.comments(for: post),
                        focusCommentComposerOnAppear: false,
                        onToggleLike: onToggleLike,
                        onToggleFollow: onToggleFollow,
                        onAddComment: onAddComment,
                        onSelectSpot: { _ in
                            dismiss()
                        },
                        onEdit: onEdit,
                        onDelete: onDelete,
                        communityViewModel: communityViewModel
                    )
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func captureLocationSpot(for post: CommunityPost) -> PhotoSpot? {
        guard let placeID = post.captureLocation?.placeID else { return nil }
        return spots.first { $0.id == placeID }
    }
}

private struct SpotCommunityPostRow: View {
    let post: CommunityPost
    let spot: PhotoSpot

    private var displayTags: [String] {
        communityDisplayTags(post.tags, excluding: spot, crowd: post.crowd, limit: 2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .vfText(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text("·")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)

                    Text(communityRelativeTimeText(for: post.createdAt))
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                if let title = post.title {
                    Text(title)
                        .vfText(.subhead.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)
                }

                if !post.message.isEmpty {
                    Text(post.message)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.primary.opacity(0.82))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if post.hasStatusInfo || !displayTags.isEmpty {
                    HStack(spacing: 6) {
                        if post.hasStatusInfo {
                            // 바로 위 줄에 작성 시각이 있어서 "작성 당시"만 붙입니다.
                            CommunityPostCrowdObservation(
                                crowd: post.crowd,
                                observedAt: post.createdAt,
                                badgeStyle: .capsule,
                                showsTime: false
                            )
                        }

                        ForEach(displayTags, id: \.self) { tag in
                            Text(tag)
                                .vfText(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let attachment = post.publicPhotoAttachments.first {
                SpotCommunityPostThumbnail(attachment: attachment)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.8))
                .padding(.top, 26)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface(cornerRadius: VFRadius.inner)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let crowd = post.hasStatusInfo ? ", 작성 당시 혼잡도 \(post.crowd.displayName)" : ""
        return "\(post.authorName), \(communityRelativeTimeText(for: post.createdAt))\(crowd), 게시글 보기"
    }
}

private struct SpotCommunityPostThumbnail: View {
    let attachment: CommunityPhotoAttachment

    var body: some View {
        ZStack {
            AppColors.mutedSurface

            if let imageData = attachment.imageData,
               let image = CommunityPhotoDecoder.image(from: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = attachment.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if case .failure = phase {
                        Image(systemName: "photo")
                            .foregroundStyle(AppColors.secondaryText)
                    } else {
                        ProgressView()
                            .tint(AppColors.secondaryText)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(width: 76, height: 64)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct SpotDetailCrowdReportControl: View {
    let selection: CommunityPost.Crowd?
    /// 방금 누른 제보(또는 취소)를 저장하는 중.
    let isSaving: Bool
    /// 이 장소의 제보를 처음 불러오는 중.
    let isLoading: Bool
    let onSelect: (CommunityPost.Crowd) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBusy: Bool {
        isSaving || isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("지금 얼마나 붐비나요?")
                    .font(AppTypography.metadata.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)

                Spacer(minLength: 0)

                // 저장하는 동안(보통 1초 안쪽) 버튼이 잠겨요. 모양이 그대로면 누른 게
                // 무시된 것처럼 보여서, 잠긴 동안에는 여기에 표시하고 버튼을 조금 옅게 둬요.
                if isBusy {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(isSaving ? "저장 중…" : "불러오는 중…")
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                }
            }

            HStack(spacing: 8) {
                ForEach(CommunityPost.Crowd.allCases) { crowd in
                    VFCrowdLevelButton(
                        crowd: crowd,
                        isSelected: selection == crowd,
                        isDisabled: isBusy
                    ) {
                        onSelect(crowd)
                    }
                }
            }
            .opacity(isBusy ? 0.6 : 1)
        }
        .animation(reduceMotion ? nil : VFMotion.quick, value: isBusy)
    }
}

// MARK: - 혼잡도 제보 뒤 한 줄 글

/// 혼잡도 버튼으로 새로 제보한 뒤 띄우는 한 줄 글 시트의 내용입니다.
/// 띄울 때마다 id 가 새로 생겨서, 다시 띄우면 입력칸과 글 ID 가 새로 시작해요.
struct SpotDetailCrowdNotePrompt: Identifiable, Equatable {
    let id = UUID()
    let crowd: CommunityPost.Crowd
    /// 시트를 띄울 때 로그인한 사용자. 방금 누른 혼잡도 제보가 저장 중인지 볼 때 씁니다.
    let authorID: String
}

/// 한 줄 글 시트를 띄울지, 입력을 어떻게 다듬을지 정하는 규칙입니다.
/// 화면과 떼어 둬서 Foundation 만으로 확인할 수 있어요.
enum SpotDetailCrowdNotePolicy {
    /// 한 줄 글 최대 글자 수.
    static let maximumLength = 100
    /// 이 글자 수부터 "87/100" 처럼 글자 수를 보여줘요.
    static let counterThreshold = 80

    /// 새로 제보했거나 다른 단계로 바꿨을 때만 띄워요. 같은 버튼을 다시 눌러 취소했거나
    /// 아무 일도 없었으면 띄우지 않아요. 현장 정보가 유효한 시간(1시간) 안에 이 장소에
    /// 이미 글을 올렸다면, 혼잡도를 바꿔도 다시 띄우지 않아요(매번 뜨면 귀찮아요).
    static func shouldOffer(
        outcome: CrowdReportToggleOutcome,
        recentOwnPostDates: [Date],
        now: Date,
        freshnessWindow: TimeInterval
    ) -> Bool {
        guard outcome == .submitted else { return false }
        let cutoff = now.addingTimeInterval(-freshnessWindow)
        return !recentOwnPostDates.contains { $0 >= cutoff }
    }

    /// 한 줄 글이라 줄바꿈은 빼요. 붙여 넣은 여러 줄은 한 칸 띄어 이어 붙이고,
    /// 최대 글자 수까지만 남겨요.
    static func sanitized(_ text: String) -> String {
        let singleLine = text
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(singleLine.prefix(maximumLength))
    }

    /// "여유로 · 보통으로 · 혼잡으로 제보했어요".
    static func reportedTitle(displayName: String) -> String {
        "\(displayName)\(directionalParticle(after: displayName)) 제보했어요"
    }

    /// 받침이 없거나 ㄹ 받침이면 "로", 그 밖의 받침이면 "으로".
    static func directionalParticle(after word: String) -> String {
        guard let scalar = word.unicodeScalars.last,
              (0xAC00...0xD7A3).contains(scalar.value) else {
            return "(으)로"
        }
        let finalConsonant = (scalar.value - 0xAC00) % 28
        // 0: 받침 없음, 8: ㄹ 받침
        return finalConsonant == 0 || finalConsonant == 8 ? "로" : "으로"
    }

    /// "1시간" 처럼 현장 정보가 유효한 시간을 글로 나타내요.
    static func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes % 60 == 0 {
            return "\(minutes / 60)시간"
        }
        return "\(minutes)분"
    }
}

/// 혼잡도 버튼을 눌렀을 때, 이 제보와 함께 올린 내 글이 있으면 어떻게 할지 먼저 물어볼지 정합니다.
/// 화면과 떼어 둬서 Foundation 만으로 확인할 수 있어요.
enum SpotDetailCrowdLinkedPostPolicy {
    enum Question: Equatable {
        /// 같은 단계를 다시 눌러 취소하려는데, 이 제보와 함께 올린 글이 있어요.
        case cancel(postID: String)
        /// 다른 단계로 바꾸려는데, 이 제보와 함께 올린 글이 있어요.
        case change(postID: String, from: CommunityPost.Crowd)

        var postID: String {
            switch self {
            case .cancel(let postID), .change(let postID, _):
                return postID
            }
        }
    }

    /// 지금 내 제보(현장 정보가 유효한 1시간 안)가 내가 올린 글과 연결돼 있을 때만 물어요.
    /// 글 없이 한 제보, 처음 누르는 경우, 연결된 글이 목록에 없는 경우는 nil 이라 바로 제보 · 취소해요.
    /// 제보를 바꾸면(글 없이) 글과의 연결이 풀려서, 그 뒤로는 묻지 않아요.
    static func question(
        tapped: CommunityPost.Crowd,
        reports: [CrowdReport],
        placeID: String,
        userID: String,
        ownPostIDs: Set<String>,
        now: Date,
        freshnessWindow: TimeInterval
    ) -> Question? {
        guard !userID.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-freshnessWindow)
        guard let current = reports
            .filter({ $0.placeID == placeID && $0.authorID == userID && $0.updatedAt >= cutoff })
            .max(by: { $0.updatedAt < $1.updatedAt }),
              let postID = current.communityPostID,
              ownPostIDs.contains(postID) else {
            return nil
        }
        return current.crowd == tapped
            ? .cancel(postID: postID)
            : .change(postID: postID, from: current.crowd)
    }
}

/// 혼잡도를 취소 · 변경하기 전에 띄우는 확인의 내용입니다.
struct SpotDetailCrowdChangeRequest: Identifiable {
    let id = UUID()
    /// 사용자가 누른 단계.
    let tapped: CommunityPost.Crowd
    let question: SpotDetailCrowdLinkedPostPolicy.Question
    /// 이 제보와 함께 올린 내 글.
    let post: CommunityPost
}

/// 혼잡도를 새로 제보한 뒤 한 번 떠요. 한 줄을 남기면 그 혼잡도와 함께 커뮤니티에 올라가요.
///
/// - 제보는 버튼을 누른 순간 이미 저장돼요. "나중에"를 눌러도 혼잡도 제보는 남아요.
/// - 올리기는 커뮤니티 글쓰기와 같은 길(onSubmitCommunity → CommunityViewModel.addPost)을
///   씁니다. 장소 · 혼잡도가 글에 같이 저장되고, 혼잡도 제보가 이 글과 연결돼요.
/// - 사진은 사진 업로드 작업 때 이 시트에 붙여요.
private struct SpotDetailCrowdNoteSheet: View {
    let spot: PhotoSpot
    let crowd: CommunityPost.Crowd
    let authorID: String
    @ObservedObject var crowdReportStore: CrowdReportStore
    let onSubmit: (CommunityPostDraft, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var note = ""
    /// 다시 시도해도 글이 하나만 생기게 시트마다 한 번 만들어 둡니다.
    /// (addPost 는 같은 ID 의 글이 이미 있으면 새로 만들지 않아요)
    @State private var submissionID = UUID().uuidString
    @State private var isPosting = false
    /// 글은 올라갔는데 혼잡도 연결만 못 했을 때. 같은 글로 다시 시도하도록 입력을 잠가요.
    @State private var isPostSavedRemotely = false
    @State private var errorMessage: String?
    @FocusState private var isNoteFocused: Bool

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 방금 누른 혼잡도 제보가 아직 저장 중인지. 저장 중에 글을 올리면 같은 제보 문서를
    /// 동시에 두 번 쓰게 되어 실패해요(CrowdReportStore.submitCommunityReport → alreadyInProgress).
    private var isCrowdReportSaving: Bool {
        crowdReportStore.isSubmitting(placeID: spot.id, authorID: authorID)
    }

    private var canPost: Bool {
        !trimmedNote.isEmpty && !isPosting && !isCrowdReportSaving
    }

    private var postButtonTitle: String {
        if isPosting { return "올리는 중…" }
        if isCrowdReportSaving { return "제보 저장 중…" }
        if isPostSavedRemotely { return "다시 시도" }
        return "커뮤니티에 올리기"
    }

    /// 내용에 맞춘 낮은 높이로 올라와요. 글자를 크게 쓰면 더 높이, 손쉬운 사용 크기면 전체 높이로.
    /// 넘치면 스크롤되고, 위로 끌어 전체 높이로 펼칠 수도 있어요.
    private var detents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize {
            return [.large]
        }
        return [.height(dynamicTypeSize > .large ? 400 : 340), .large]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.lg) {
                header
                noteSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.pageHorizontalPadding)
            .padding(.top, VFSpace.lg + VFSpace.sm)
            .padding(.bottom, VFSpace.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .background(AppColors.background.ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isPosting)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: VFSpace.md) {
            Image(systemName: "checkmark.circle.fill")
                .vfIcon(22, relativeTo: .headline)
                .foregroundStyle(crowd.tint)

            VStack(alignment: .leading, spacing: VFSpace.xs) {
                Text(SpotDetailCrowdNotePolicy.reportedTitle(displayName: crowd.displayName))
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)

                Text("\(SpotDetailCrowdNotePolicy.durationText(CrowdReportStore.freshnessWindow)) 동안 이 장소의 현재 혼잡도에 반영돼요.")
                    .vfText(.subhead)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text("지금 현장은 어때요?")
                .vfText(.subhead.weight(.semibold))
                .foregroundStyle(AppColors.primary)

            TextField("예: 노을은 다리 왼쪽 계단이 명당이에요", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .vfText(.body)
                .tint(AppColors.accent)
                .submitLabel(.done)
                .focused($isNoteFocused)
                .disabled(isPosting || isPostSavedRemotely)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget, alignment: .leading)
                .background(
                    AppColors.mutedSurface,
                    in: RoundedRectangle(cornerRadius: AppLayout.controlCornerRadius, style: .continuous)
                )
                .onChange(of: note) { _, newValue in
                    if newValue.contains(where: \.isNewline) {
                        // 한 줄 글이라 return 은 입력 끝내기로 씁니다.
                        isNoteFocused = false
                    }
                    let cleaned = SpotDetailCrowdNotePolicy.sanitized(newValue)
                    if cleaned != newValue {
                        note = cleaned
                    }
                }
                .accessibilityLabel("한 줄 남기기")
                .accessibilityHint("한 줄을 남기면 커뮤니티에도 함께 올라가요")

            HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm) {
                Text("한 줄을 남기면 커뮤니티에도 함께 올라가요.")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if note.count >= SpotDetailCrowdNotePolicy.counterThreshold {
                    Text("\(note.count)/\(SpotDetailCrowdNotePolicy.maximumLength)")
                        .monospacedDigit()
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .accessibilityLabel("\(note.count)자, 최대 \(SpotDetailCrowdNotePolicy.maximumLength)자")
                }
            }

            if let errorMessage {
                Label {
                    Text(errorMessage)
                        .vfText(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: VFSpace.sm + 2) {
            Button {
                dismiss()
            } label: {
                Text(isPostSavedRemotely ? "닫기" : "나중에")
                    .vfText(.callout.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget)
                    .background(AppColors.mutedSurface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPosting)

            Button(action: post) {
                HStack(spacing: 6) {
                    if isPosting || isCrowdReportSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.secondaryText)
                    }

                    Text(postButtonTitle)
                        .vfText(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(canPost ? AppColors.onAccent : AppColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget)
                .background(canPost ? AppColors.accent : AppColors.mutedSurface, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canPost)
        }
        .padding(.horizontal, AppLayout.pageHorizontalPadding)
        .padding(.top, VFSpace.sm)
        .padding(.bottom, VFSpace.md)
        .background(AppColors.background)
    }

    private func post() {
        guard canPost else { return }
        let message = trimmedNote
        isNoteFocused = false
        isPosting = true
        errorMessage = nil

        Task {
            do {
                try await onSubmit(
                    CommunityPostDraft(spot: spot, title: nil, message: message, crowd: crowd),
                    submissionID
                )
                isPosting = false
                VFHaptics.success()
                dismiss()
            } catch {
                isPosting = false
                VFHaptics.error()
                if let communityError = error as? FirebaseCommunityError,
                   case .crowdReportPending = communityError {
                    // 글은 이미 올라갔어요. 같은 ID 로 다시 시도하면 글이 하나 더 생기지 않고
                    // 혼잡도 연결만 마저 해요.
                    isPostSavedRemotely = true
                    errorMessage = communityError.localizedDescription
                } else {
                    errorMessage = "올리지 못했어요. 쓴 내용은 그대로 있어요. 다시 시도해 주세요."
                }
                AppLog.persistence.error(
                    "Crowd note post failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

private struct CommunityCrowdSummaryCard: View {
    let summary: CrowdReportSummary?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: summary == nil ? "person.2.slash" : "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("현재 혼잡도")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    if let summary {
                        Text(summary.crowd.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(summary.crowd.tint)
                            .padding(.horizontal, 7)
                            .frame(height: 21)
                            .background(summary.crowd.fill, in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var tint: Color {
        summary?.crowd.tint ?? AppColors.secondaryText
    }

    private var subtitle: String {
        guard let summary else {
            return "최근 유효한 제보 없음"
        }

        return "최근 제보 \(summary.reportCount)개 기준 · \(communityRelativeTimeText(for: summary.latestDate)) 갱신"
    }
}

struct DetailInfoRow: View {
    let symbolName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.metadata.weight(.bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(value)
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SpotShootingMetric: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 32, height: 32)
                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)

            Text(value)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .appCardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct DetailActionButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    let height: CGFloat
    var tint: Color? = nil

    private var foregroundColor: Color {
        // "지도에서 보기" 와 "길찾기" 는 같은 유리 바 안의 같은 계층이므로
        // 글자색을 동일하게 둡니다.
        //
        // 한동안 길찾기만 앰버로 강조했는데, 두 버튼이 나란히 있는 상태에서
        // 한쪽만 색이 다르면 위계보다 불일치로 읽혔습니다.
        // 주 동작 강조가 필요해지면 배경이나 크기로 구분하는 편이 낫습니다.
        tint ?? AppColors.primary.opacity(0.94)
    }

    var body: some View {
        content
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(height, AppLayout.touchTarget))
            // 액션 바 전체에 이미 Liquid Glass 가 적용되어 있습니다.
            // 여기서 흰 캡슐을 덮으면 유리 위에 불투명 블록이 얹혀
            // "지도에서 보기" 와 재료가 달라 보입니다. (유리 위 유리/불투명 금지)
            // 주 동작 구분은 배경이 아니라 글자 색(앰버)으로 표현합니다.
            .contentShape(Rectangle())
    }

    private var content: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: isPrimary ? .bold : .semibold))
                .symbolRenderingMode(.monochrome)

            Text(title)
                .font(.system(size: 13, weight: isPrimary ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

struct NativeActionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppColors.divider.opacity(colorScheme == .dark ? 0.42 : 0.64))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
