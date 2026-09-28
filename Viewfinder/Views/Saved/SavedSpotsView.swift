import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — iOS 기본 스타일
//
//  [3차가 난잡했던 이유]
//  첫 화면 하나에 전면 사진, 사진 위 pill 과 톱니바퀴, 40pt 이름, 계기판 줄,
//  가로 사진 레일, 활동 행이 한꺼번에 있었습니다. 마이 탭은 사진을 구경하는
//  곳이 아니라 내 것을 찾고 설정을 바꾸는 곳인데, 홈처럼 꾸미면서 볼거리만 늘었습니다.
//
//  [지금] 새로 만든 모양 없이 iOS 기본 부품만 씁니다.
//    첫 화면      큰 제목 + 묶음 목록(List, insetGrouped). 설정 앱과 같은 구조입니다.
//                 프로필 행 → 계정(로그아웃)
//                 저장한 장소 · 추가한 장소 · 내 글 → 각 화면, 오른쪽에 개수
//                 화면 모드 · 사진 취향 다시 설정
//    저장한 장소  사진 앱 "앨범" 과 같은 2열 격자. 테마는 오른쪽 위 거르기 메뉴.
//    추가한 장소  목록 (사진 · 이름 · 지역과 날짜)
//    내 글        메모 앱과 같은 목록 (제목 · 시간과 장소 · 오른쪽 사진) → 글 상세
//    빈 상태      ContentUnavailableView (iOS 기본 빈 화면)
//
//  글자는 시스템 글자 스타일, 색은 시스템 색(목록 배경 · 회색 글자)을 그대로 씁니다.
//  주황은 앱의 tint 로, 목록 아이콘과 게스트의 "로그인" 에만 나옵니다.
// ═══════════════════════════════════════════════════════════════════

struct MyTabView: View {
    let user: AuthUser?
    let savedSpots: [PhotoSpot]
    let submissionReceipts: [PlaceSubmissionReceipt]
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let communityViewModel: CommunityViewModel
    let onTabBarVisibilityChange: (Bool) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    /// 저장한 장소 화면에서 길게 눌러 저장을 해제합니다.
    let onToggleSave: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) async throws -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onRequestSignIn: () -> Void
    let onExploreSpots: () -> Void
    /// 빈 "추가한 장소" 화면에서 바로 장소 추가로 갑니다.
    let onAddPlace: () -> Void
    /// 빈 "내 글" 화면에서 바로 글쓰기로 갑니다.
    let onCompose: () -> Void
    let onResetTaste: () -> Void
    let onSignOut: () -> Void

    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.defaultValue.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .defaultValue
    }

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileRow
                }

                Section {
                    NavigationLink {
                        MySavedSpotsView(
                            spots: savedSpots,
                            onSelect: onSelectSpot,
                            onUnsave: unsave,
                            onExplore: onExploreSpots
                        )
                    } label: {
                        MyRowLabel(title: "저장한 장소", symbolName: "bookmark", value: "\(savedSpots.count)")
                    }

                    // 추가한 장소 · 내 글은 계정 활동이라 로그인했을 때만 둡니다.
                    // 게스트에게는 맨 위 로그인 행이 그 설명을 대신합니다.
                    if user != nil {
                        NavigationLink {
                            MyPlacesView(
                                receipts: submissionReceipts,
                                spots: spots,
                                onSelectSpot: onSelectSpot,
                                onAddPlace: onAddPlace
                            )
                        } label: {
                            MyRowLabel(
                                title: "추가한 장소",
                                symbolName: "mappin.and.ellipse",
                                value: "\(submissionReceipts.count)"
                            )
                        }

                        NavigationLink {
                            MyPostsView(posts: myPosts, makeRow: postRow, onCompose: onCompose)
                        } label: {
                            MyRowLabel(title: "내 글", symbolName: "text.bubble", value: "\(myPosts.count)")
                        }
                    }
                } footer: {
                    Text(user == nil
                         ? "저장은 로그인 없이도 돼요. 저장한 장소는 이 기기에 남아요."
                         : "저장한 장소는 이 기기에 저장돼요.")
                }

                Section {
                    Picker(selection: $appearanceRawValue) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title)
                                .tag(option.rawValue)
                        }
                    } label: {
                        MyRowLabel(title: "화면 모드", symbolName: appearance.symbolName)
                    }
                    .pickerStyle(.menu)

                    Button(action: onResetTaste) {
                        MyRowLabel(title: "사진 취향 다시 설정", symbolName: "photo.on.rectangle.angled")
                    }
                    .accessibilityHint("홈 추천의 출발점이 되는 사진 3장을 다시 고릅니다")
                } footer: {
                    Text(Self.versionText)
                }
            }
            .listStyle(.insetGrouped)
            // iOS 26: 위로 조금만 올려도 줄어든 탭바가 다시 펼쳐지게 합니다.
            .vfReportsTabBarScroll()
            .navigationTitle("마이")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    // MARK: - 프로필

    @ViewBuilder
    private var profileRow: some View {
        if let user {
            NavigationLink {
                MyAccountView(user: user, onSignOut: onSignOut)
            } label: {
                MyProfileLabel(user: user)
            }
        } else {
            Button(action: onRequestSignIn) {
                MyGuestLabel()
            }
            .accessibilityHint("로그인 화면을 엽니다")
        }
    }

    // MARK: - 저장 해제

    /// 길게 눌러 저장 해제. 다른 화면의 저장 버튼(VFSaveButton)과 같은 촉감이고,
    /// 빠진 자리를 나머지 사진이 채우는 움직임이 보이게 합니다.
    private func unsave(_ spot: PhotoSpot) {
        VFHaptics.save()
        withAnimation(VFMotion.standard) {
            onToggleSave(spot)
        }
    }

    // MARK: - 내 글

    /// 목록 행과 글 상세를 한 곳에서 만듭니다. "내 글" 화면이 이 함수를 그대로 받아 씁니다.
    private func postRow(_ post: CommunityPost) -> some View {
        NavigationLink {
            postDetail(post)
        } label: {
            MyPostRow(post: post)
        }
    }

    private func postDetail(_ post: CommunityPost) -> some View {
        CommunityPostDetailView(
            post: post,
            spot: spot(for: post),
            captureLocationSpot: captureLocationSpot(for: post),
            currentUserID: user?.id ?? "",
            isLiked: likedPostIDs.contains(post.id),
            likeCount: displayedLikeCount(for: post),
            isFollowing: followedAuthorIDs.contains(post.authorID),
            comments: commentsByPostID[post.id] ?? [],
            focusCommentComposerOnAppear: false,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot,
            onEdit: onEditPost,
            onDelete: onDeletePost,
            communityViewModel: communityViewModel
        )
    }

    private func displayedLikeCount(for post: CommunityPost) -> Int {
        post.likeCount + (likedPostIDs.contains(post.id) ? 1 : 0)
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first(where: { $0.id == post.spotID })
    }

    private func captureLocationSpot(for post: CommunityPost) -> PhotoSpot? {
        guard let placeID = post.captureLocation?.placeID else { return nil }
        return spots.first(where: { $0.id == placeID })
    }

    /// 목록 맨 아래 작은 글씨. 설정 앱의 버전 표기처럼 둡니다.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "뷰파인더 \(version) (\(build))"
    }
}

// MARK: - 목록 행

private enum MyListMetrics {
    /// 목록 아이콘 칸의 폭. 기호마다 폭이 달라도 제목이 한 줄로 맞게 합니다.
    static let iconWidth: CGFloat = 28
    /// 프로필 행 아바타. 설정 앱 맨 위 계정 행과 비슷한 크기입니다.
    static let profileAvatarSize: CGFloat = 60
    /// 계정 화면 가운데 아바타.
    static let accountAvatarSize: CGFloat = 84
    /// 목록 행의 작은 사진.
    static let thumbnailSize: CGFloat = 56
}

/// 목록 한 줄: 주황 아이콘 + 제목, 값이 있으면 오른쪽에 회색으로.
/// 메일 · 메모 앱의 폴더 목록과 같은 모양입니다.
private struct MyRowLabel: View {
    let title: String
    let symbolName: String
    var value: String? = nil

    var body: some View {
        if let value {
            LabeledContent {
                Text(value)
                    .monospacedDigit()
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        Label {
            // 버튼 행은 기본으로 글자까지 tint(주황)가 칠해지므로 본문 색을 직접 정합니다.
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(AppColors.accent)
                .frame(width: MyListMetrics.iconWidth)
        }
    }
}

/// 설정 앱 맨 위 계정 행과 같은 모양입니다. 누르면 계정 화면이 열립니다.
private struct MyProfileLabel: View {
    let user: AuthUser

    var body: some View {
        HStack(spacing: 14) {
            MyAvatar(name: user.displayName, size: MyListMetrics.profileAvatarSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return MyAccountText.providerTitle(for: user).map { "\($0) 계정" } ?? "내 계정"
    }
}

/// 설정 앱의 "iPhone에 로그인" 행과 같은 모양입니다.
private struct MyGuestLabel: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .scaledToFit()
                .foregroundStyle(Color(uiColor: .systemGray))
                .frame(width: MyListMetrics.profileAvatarSize, height: MyListMetrics.profileAvatarSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("로그인")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.accent)

                Text("장소를 추가하고 현장 글을 남길 수 있어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private enum MyAccountText {
    /// "Apple" · "Google". 알 수 없는 로그인 방식이면 nil.
    static func providerTitle(for user: AuthUser) -> String? {
        AuthProviderKind(rawValue: user.provider)?.title
    }
}

/// 커뮤니티 아바타(CommunityAuthorAvatar)와 같은 규칙입니다.
/// 이름 첫 글자 + 이름으로 고른 무채색 톤이라, 내 글에 붙는 아바타와 똑같이 보입니다.
private struct MyAvatar: View {
    let name: String
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(initial)
            // Dynamic Type 제외: 원 지름에 비례하는 크기다. 원이 안 커지므로 글자도 안 커진다.
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.72))
            .frame(width: size, height: size)
            .background(tone, in: Circle())
            .overlay {
                Circle()
                    .stroke(AppColors.divider, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var tone: Color {
        let tones = VFPalette.avatarTones
        let seed = name.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Color(uiColor: tones[seed % tones.count])
    }
}

/// 목록 행의 작은 사진 칸.
private struct MyRowThumbnail<Content: View>: View {
    var size: CGFloat = MyListMetrics.thumbnailSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 사진이 없을 때의 칸. 시스템 채움 색 위 기호 하나.
private struct MyThumbnailPlaceholder: View {
    let symbolName: String

    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)

            Image(systemName: symbolName)
                // Dynamic Type 제외: 고정 크기 칸 안의 기호.
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}

/// 커뮤니티 글에 붙은 사진 한 장. (기기에 있는 데이터 또는 서버 주소)
private struct MyAttachmentImage: View {
    let attachment: CommunityPhotoAttachment
    var detail: VFPhotoDetail = .thumbnail

    var body: some View {
        if let data = attachment.imageData,
           let image = CommunityPhotoDecoder.image(
            from: data,
            cacheKey: attachment.id,
            detail: detail
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteURL = attachment.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .tertiarySystemFill)
                }
            }
        } else {
            Color(uiColor: .tertiarySystemFill)
        }
    }
}

private enum MyDateText {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    static func day(fromISO8601 raw: String) -> String? {
        guard let date = isoFormatter.date(from: raw) else { return nil }
        return dayFormatter.string(from: date)
    }
}

/// 내가 추가한 장소 한 줄. 누르면 장소 상세가 열립니다.
private struct MyPlaceRow: View {
    let receipt: PlaceSubmissionReceipt
    /// 지금 불러온 장소 목록에서 찾은 장소. 아직 못 불러왔으면 nil 이고,
    /// 그때는 누를 수 없는 행으로 둡니다.
    let spot: PhotoSpot?
    let onSelectSpot: (PhotoSpot) -> Void

    var body: some View {
        if let spot {
            // 기본 버튼 스타일이라 누르면 행 전체가 회색으로 반응합니다. (목록 기본 동작)
            // 상세는 밀어 넣는 화면이 아니라 시트라서 오른쪽 화살표(›)를 두지 않습니다.
            Button {
                onSelectSpot(spot)
            } label: {
                content
            }
            .accessibilityHint("장소 상세를 엽니다")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            MyRowThumbnail {
                if let spot, spot.hasReliableDisplayImage {
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 16,
                        targetPixelWidth: VFPhotoDetail.thumbnail.pixelWidth
                    )
                } else {
                    MyThumbnailPlaceholder(symbolName: "photo")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // 홈과 지도는 사진이 있는 장소만 보여줍니다. 사진이 없는 곳만 그 사실을 알립니다.
                if let spot, !spot.hasReliableDisplayImage {
                    Text("사진이 없어 아직 검색에만 보여요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// 지역 · 추가한 날.
    private var detailText: String {
        [regionText, MyDateText.day(fromISO8601: receipt.submittedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var regionText: String? {
        if let spot {
            return HomeSpotDisplayFormatter.region(for: spot)
        }
        guard let region = receipt.region?.trimmingCharacters(in: .whitespacesAndNewlines),
              !region.isEmpty else {
            return nil
        }
        return region
    }
}

/// 내 글 한 줄. 메모 앱 목록과 같은 모양입니다. (제목 / 시간 · 장소 / 오른쪽에 첫 사진)
private struct MyPostRow: View {
    let post: CommunityPost

    private var photo: CommunityPhotoAttachment? {
        post.publicPhotoAttachments.first
    }

    private var trimmedTitle: String? {
        guard let title = post.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    /// 본문을 줄 단위로. 빈 줄은 뺍니다.
    private var messageLines: [String] {
        post.message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 제목이 없으면 본문 첫 줄을 제목처럼 씁니다.
    private var headline: String {
        if let trimmedTitle {
            return trimmedTitle
        }
        if let firstLine = messageLines.first {
            return firstLine
        }
        return post.hasPhotos ? "사진" : "글"
    }

    /// 시간 · 장소. 장소가 없는 글은 장소 대신 본문 미리보기를 붙입니다.
    private var detailText: String {
        var parts = [communityRelativeTimeText(for: post.createdAt)]

        if let spotName = post.relatedSpotName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !spotName.isEmpty {
            parts.append(spotName)
        } else {
            // 제목을 본문 첫 줄에서 가져왔으면 그 다음 줄부터 씁니다.
            let lines = trimmedTitle == nil ? Array(messageLines.dropFirst()) : messageLines
            let preview = lines.joined(separator: " ")
            if !preview.isEmpty {
                parts.append(preview)
            }
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let photo {
                MyRowThumbnail(size: 52) {
                    MyAttachmentImage(attachment: photo)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 각 화면
// ═══════════════════════════════════════════════════════════════════

/// 저장한 장소. 사진 앱 "앨범" 과 같은 2열 격자입니다.
private struct MySavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void
    let onUnsave: (PhotoSpot) -> Void
    let onExplore: () -> Void

    @State private var selectedTheme: SpotTheme?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// 저장한 장소에 실제로 있는 테마만, SpotTheme 순서대로.
    private var themes: [SpotTheme] {
        SpotTheme.allCases.filter { theme in
            spots.contains { $0.theme == theme }
        }
    }

    /// 고른 테마의 장소를 모두 저장 해제하면 "전체" 로 돌아갑니다.
    private var activeTheme: SpotTheme? {
        guard let selectedTheme, themes.contains(selectedTheme) else { return nil }
        return selectedTheme
    }

    private var visibleSpots: [PhotoSpot] {
        guard let activeTheme else { return spots }
        return spots.filter { $0.theme == activeTheme }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(visibleSpots) { spot in
                    MySavedSpotTile(
                        spot: spot,
                        onSelect: { onSelect(spot) },
                        onUnsave: { onUnsave(spot) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(VFMotion.quick, value: activeTheme)
        }
        .vfReportsTabBarScroll()
        .overlay {
            if spots.isEmpty {
                ContentUnavailableView {
                    Label("저장한 출사지가 아직 없어요", systemImage: "bookmark")
                } description: {
                    Text("홈이나 지도에서 마음에 드는 곳을 저장하면 여기에 모여요.")
                } actions: {
                    Button("출사지 둘러보기", action: onExplore)
                }
            }
        }
        .navigationTitle("저장한 장소")
        .toolbar {
            // 테마가 하나뿐이면 거를 게 없으므로 메뉴를 두지 않습니다.
            if themes.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    themeMenu
                }
            }
        }
        .onChange(of: themes) { _, newThemes in
            if let selectedTheme, !newThemes.contains(selectedTheme) {
                self.selectedTheme = nil
            }
        }
    }

    /// 사진 앱 · 메일 앱의 거르기 버튼과 같은 모양입니다. 거르는 중에는 채운 아이콘.
    private var themeMenu: some View {
        Menu {
            Picker("테마", selection: $selectedTheme) {
                Text("전체")
                    .tag(SpotTheme?.none)

                ForEach(themes) { theme in
                    Text(theme.title)
                        .tag(SpotTheme?.some(theme))
                }
            }
        } label: {
            Image(systemName: activeTheme == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("테마로 거르기")
        .accessibilityValue(activeTheme?.title ?? "전체")
    }
}

/// 사진 앱 앨범 칸과 같은 모양: 정사각 사진 + 아래 이름 · 지역.
private struct MySavedSpotTile: View {
    let spot: PhotoSpot
    let onSelect: () -> Void
    let onUnsave: () -> Void

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                VFPhotoTile(
                    spot: spot,
                    aspectRatio: 1,
                    cornerRadius: VFRadius.inner,
                    imageDetail: .card
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(spot.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 길게 눌렀을 때 떠오르는 미리보기의 모서리를 사진과 맞춥니다.
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
        )
        .contextMenu {
            Button(role: .destructive, action: onUnsave) {
                Label("저장 해제", systemImage: "bookmark.slash")
            }
        }
        .accessibilityLabel("\(spot.name), \(region)")
        .accessibilityAction(named: "저장 해제", onUnsave)
    }
}

private struct MyPlacesView: View {
    let receipts: [PlaceSubmissionReceipt]
    let spots: [PhotoSpot]
    let onSelectSpot: (PhotoSpot) -> Void
    let onAddPlace: () -> Void

    var body: some View {
        List {
            if !receipts.isEmpty {
                Section {
                    ForEach(receipts) { receipt in
                        MyPlaceRow(
                            receipt: receipt,
                            spot: spots.first(where: { $0.id == receipt.id }),
                            onSelectSpot: onSelectSpot
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .overlay {
            if receipts.isEmpty {
                ContentUnavailableView {
                    Label("직접 추가한 장소가 아직 없어요", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("나만 아는 출사지를 알려주세요. 다른 사진가의 다음 출사지가 돼요.")
                } actions: {
                    Button("장소 추가", action: onAddPlace)
                }
            }
        }
        .navigationTitle("추가한 장소")
        .toolbar {
            // 비어 있을 때는 가운데 "장소 추가" 버튼이 같은 일을 하므로 숨깁니다.
            if !receipts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddPlace) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("장소 추가")
                }
            }
        }
    }
}

/// 행 생성을 클로저로 받습니다.
///
/// 글 상세로 가는 링크에 필요한 인자가 많습니다. 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고,
/// 하나라도 어긋나면 다르게 동작합니다. MyTabView.postRow 를 그대로 받습니다.
private struct MyPostsView<Row: View>: View {
    let posts: [CommunityPost]
    let makeRow: (CommunityPost) -> Row
    let onCompose: () -> Void

    var body: some View {
        List {
            if !posts.isEmpty {
                Section {
                    ForEach(posts) { post in
                        makeRow(post)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .overlay {
            if posts.isEmpty {
                ContentUnavailableView {
                    Label("남긴 글이 아직 없어요", systemImage: "text.bubble")
                } description: {
                    Text("지금 현장의 분위기와 혼잡도를 남겨보세요. 다음 사람의 출사가 쉬워져요.")
                } actions: {
                    Button("글쓰기", action: onCompose)
                }
            }
        }
        .navigationTitle("내 글")
        .toolbar {
            if !posts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCompose) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("글쓰기")
                }
            }
        }
    }
}

/// 계정. 설정 앱의 계정 화면처럼 가운데 프로필 + 맨 아래 로그아웃입니다.
private struct MyAccountView: View {
    let user: AuthUser
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    MyAvatar(name: user.displayName, size: MyListMetrics.accountAvatarSize)

                    VStack(spacing: 3) {
                        Text(user.displayName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            if let providerTitle = MyAccountText.providerTitle(for: user) {
                Section {
                    LabeledContent("로그인 방식", value: providerTitle)
                }
            }

            Section {
                // 다시 로그인하면 되돌릴 수 있어서 확인 창을 띄우지 않습니다.
                Button("로그아웃", role: .destructive) {
                    dismiss()
                    onSignOut()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .navigationTitle("계정")
        .navigationBarTitleDisplayMode(.inline)
    }
}
