import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation

protocol CommunityService {
    func fetchPosts() -> [CommunityPost]
    func addPost(_ draft: CommunityPostDraft, author: AuthUser) -> CommunityPost
    func updatePost(id: String, draft: CommunityPostDraft) -> CommunityPost?
    func deletePost(id: String)
}

final class MockCommunityService: CommunityService {
    private var posts: [CommunityPost] = [
        CommunityPost(
            id: "mock-seonyudo",
            spotID: "seed-seonyudo-park",
            spotName: "선유도공원",
            message: "해질녘 빛이 좋고 산책로는 비교적 여유 있어요.",
            crowd: .normal,
            tags: ["노을 좋음"],
            photoData: nil,
            likeCount: 12,
            authorID: "mock-local-seonyudo",
            authorName: "필름러버",
            createdAt: Date().addingTimeInterval(-18 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-banpo",
            spotID: "seed-banpo-fountain",
            spotName: "반포대교 달빛무지개분수",
            message: "분수 시간대에는 삼각대 자리 경쟁이 조금 있어요.",
            crowd: .crowded,
            tags: ["야경 좋음", "조명 좋음"],
            photoData: nil,
            likeCount: 8,
            authorID: "mock-local-banpo",
            authorName: "야경팀",
            createdAt: Date().addingTimeInterval(-42 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-bukchon",
            spotID: "seed-bukchon",
            spotName: "북촌한옥마을",
            message: "오전 골목은 조용한 편이고 생활지역 예절만 조심하면 좋아요.",
            crowd: .relaxed,
            tags: ["사람 적음", "사진 찍기 좋음"],
            photoData: nil,
            likeCount: 19,
            authorID: "mock-local-bukchon",
            authorName: "골목산책",
            createdAt: Date().addingTimeInterval(-2 * 60 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-seoul-forest-daisy",
            spotID: "seed-seoul-forest",
            spotName: "서울숲",
            message: "군락지 쪽 데이지가 피기 시작해서 낮은 앵글로 찍기 좋아요.",
            crowd: .normal,
            tags: ["데이지", "꽃 만개", "사진 찍기 좋음"],
            photoData: nil,
            likeCount: 27,
            authorID: "mock-local-seoul-forest",
            authorName: "꽃스냅",
            createdAt: Date().addingTimeInterval(-27 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-mullae-film",
            spotID: "seed-mullae-local-cafe-alley",
            spotName: "문래창작촌",
            message: "철공소 골목 쪽 로컬카페 외관이 필름감성으로 잘 나와요.",
            crowd: .relaxed,
            tags: ["필름감성", "로컬카페", "사람 적음"],
            photoData: nil,
            likeCount: 14,
            authorID: "mock-local-mullae",
            authorName: "문래스냅",
            createdAt: Date().addingTimeInterval(-51 * 60),
            updatedAt: nil
        )
    ]

    func fetchPosts() -> [CommunityPost] {
        posts.sorted { $0.createdAt > $1.createdAt }
    }

    func addPost(_ draft: CommunityPostDraft, author: AuthUser) -> CommunityPost {
        let post = CommunityPost(
            id: UUID().uuidString,
            spot: draft.spot,
            title: draft.title,
            captureLocation: draft.captureLocation,
            crowd: draft.crowd,
            message: draft.message,
            tags: draft.tags,
            photoAttachments: draft.photoAttachments,
            likeCount: 0,
            authorID: author.id,
            authorName: author.displayName,
            createdAt: Date(),
            updatedAt: nil
        )
        posts.insert(post, at: 0)
        return post
    }

    func updatePost(id: String, draft: CommunityPostDraft) -> CommunityPost? {
        guard let index = posts.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let original = posts[index]
        let updated = CommunityPost(
            id: original.id,
            spot: draft.spot,
            title: draft.title,
            captureLocation: draft.captureLocation,
            crowd: draft.crowd,
            message: draft.message,
            tags: draft.tags,
            photoAttachments: draft.photoAttachments,
            likeCount: original.likeCount,
            authorID: original.authorID,
            authorName: original.authorName,
            createdAt: original.createdAt,
            updatedAt: Date()
        )
        posts[index] = updated
        return updated
    }

    func deletePost(id: String) {
        posts.removeAll { $0.id == id }
    }
}

/// Community 게시글의 Firebase 저장 경로입니다.
///
/// 공개 Firestore 문서에는 사용자가 동의한 촬영정보만 기록합니다.
/// 원본 EXIF dictionary나 비공개 GPS 좌표는 문서에 저장하지 않고,
/// Storage 업로드 전에도 CommunityPhotoPrivacyProcessor 로 제거합니다.
final class FirebaseCommunityPostStore {
    private static let maxConcurrentPhotoUploads = 2

    private let firestore: Firestore
    private let storage: Storage

    init(
        firestore: Firestore? = nil,
        storage: Storage? = nil
    ) {
        self.firestore = firestore ?? Firestore.firestore()
        self.storage = storage ?? Storage.storage()
    }

    func fetchPosts() async throws -> [CommunityPost] {
        guard FirebaseApp.app() != nil else { return [] }

        let snapshot = try await getDocuments(
            from: firestore.collection("communityPosts")
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
        )

        return snapshot.documents.compactMap(Self.decodePost)
    }

    func addPost(_ draft: CommunityPostDraft, author: AuthUser, id: String) async throws -> CommunityPost {
        guard FirebaseApp.app() != nil else {
            throw FirebaseCommunityError.notConfigured
        }

        let postReference = firestore.collection("communityPosts").document(id)
        let attachments = try await uploadAttachments(
            draft.photoAttachments,
            authorID: author.id,
            postID: id
        )
        let createdAt = Date()
        let post = CommunityPost(
            id: id,
            spot: draft.spot,
            title: draft.title,
            captureLocation: draft.captureLocation,
            crowd: draft.crowd,
            message: draft.message,
            tags: draft.tags,
            photoAttachments: attachments,
            likeCount: 0,
            authorID: author.id,
            authorName: author.displayName,
            createdAt: createdAt,
            updatedAt: nil
        )

        try await setData(Self.firestoreData(for: post), on: postReference)
        return post
    }

    func updatePost(_ post: CommunityPost, draft: CommunityPostDraft) async throws -> CommunityPost {
        let attachments = try await uploadAttachments(
            draft.photoAttachments,
            authorID: post.authorID,
            postID: post.id
        )
        let updated = CommunityPost(
            id: post.id,
            spot: draft.spot,
            title: draft.title,
            captureLocation: draft.captureLocation,
            crowd: draft.crowd,
            message: draft.message,
            tags: draft.tags,
            photoAttachments: attachments,
            likeCount: post.likeCount,
            authorID: post.authorID,
            authorName: post.authorName,
            createdAt: post.createdAt,
            updatedAt: Date()
        )
        try await setData(
            Self.firestoreData(for: updated),
            on: firestore.collection("communityPosts").document(post.id)
        )
        return updated
    }

    func deletePost(_ post: CommunityPost) async throws {
        try await deleteDocument(firestore.collection("communityPosts").document(post.id))
    }

    private func uploadAttachments(
        _ attachments: [CommunityPhotoAttachment],
        authorID: String,
        postID: String
    ) async throws -> [CommunityPhotoAttachment] {
        guard !attachments.isEmpty else { return [] }

        return try await withThrowingTaskGroup(
            of: (Int, CommunityPhotoAttachment).self
        ) { group in
            let initialCount = min(Self.maxConcurrentPhotoUploads, attachments.count)
            var nextIndex = initialCount

            for index in 0..<initialCount {
                let attachment = attachments[index]
                group.addTask { [self] in
                    (
                        index,
                        try await uploadAttachment(
                            attachment,
                            authorID: authorID,
                            postID: postID
                        )
                    )
                }
            }

            var result: [CommunityPhotoAttachment] = []
            result.reserveCapacity(attachments.count)

            while let (_, attachment) = try await group.next() {
                result.append(attachment)

                if nextIndex < attachments.count {
                    let index = nextIndex
                    let nextAttachment = attachments[index]
                    nextIndex += 1
                    group.addTask { [self] in
                        (
                            index,
                            try await uploadAttachment(
                                nextAttachment,
                                authorID: authorID,
                                postID: postID
                            )
                        )
                    }
                }
            }

            // 기존 저장 결과의 정렬 규칙을 유지합니다.
            return result.sorted { $0.id < $1.id }
        }
    }

    private func uploadAttachment(
        _ attachment: CommunityPhotoAttachment,
        authorID: String,
        postID: String
    ) async throws -> CommunityPhotoAttachment {
        guard let imageData = attachment.imageData else {
            return CommunityPhotoAttachment(
                id: attachment.id,
                imageData: nil,
                remoteURL: attachment.remoteURL,
                metadata: attachment.metadata,
                location: attachment.location,
                sharesToPlaceGallery: attachment.sharesToPlaceGallery
            )
        }

        let path = "communityPosts/\(authorID)/\(postID)/\(attachment.id).jpg"
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await putData(imageData, metadata: metadata, at: reference)
        let downloadURL = try await downloadURL(for: reference)

        return CommunityPhotoAttachment(
            id: attachment.id,
            imageData: nil,
            remoteURL: downloadURL,
            metadata: attachment.metadata,
            location: attachment.location,
            sharesToPlaceGallery: attachment.sharesToPlaceGallery
        )
    }

    private func getDocuments(from query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], on reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func deleteDocument(_ reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func putData(
        _ data: Data,
        metadata: StorageMetadata,
        at reference: StorageReference
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            reference.putData(data, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func downloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private static func firestoreData(for post: CommunityPost) -> [String: Any] {
        var data: [String: Any] = [
            "id": post.id,
            "authorID": post.authorID,
            "authorName": post.authorName,
            "message": post.message,
            "tags": post.tags,
            "hasStatusInfo": post.hasStatusInfo,
            "likeCount": post.likeCount,
            "createdAt": Timestamp(date: post.createdAt)
        ]

        if post.hasStatusInfo {
            data["crowd"] = post.crowd.rawValue
        }

        if let title = post.title, !title.isEmpty {
            data["title"] = title
        }
        if let spotID = post.relatedSpotID {
            data["relatedSpotID"] = spotID
        }
        if let spotName = post.relatedSpotName {
            data["relatedSpotName"] = spotName
        }
        if let captureLocation = post.captureLocation {
            data["captureLocation"] = captureLocation.firestoreData
        }
        if let updatedAt = post.updatedAt {
            data["updatedAt"] = Timestamp(date: updatedAt)
        }

        let attachmentData = post.photoAttachments.compactMap { attachment -> [String: Any]? in
            guard let remoteURL = attachment.remoteURL else { return nil }
            var result: [String: Any] = [
                "id": attachment.id,
                "downloadURL": remoteURL.absoluteString
            ]
            if let metadata = attachment.metadata, !metadata.isEmpty {
                result["metadata"] = metadata.firestoreData
            }
            if attachment.sharesToPlaceGallery {
                result["sharesToPlaceGallery"] = true
            }
            return result
        }
        data["attachments"] = attachmentData
        return data
    }

    private static func decodePost(_ document: QueryDocumentSnapshot) -> CommunityPost? {
        let data = document.data()
        guard let message = data["message"] as? String,
              let authorID = data["authorID"] as? String,
              let authorName = data["authorName"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let title = data["title"] as? String
        let captureLocation = decodeCaptureLocation(data["captureLocation"] as? [String: Any])
        let spotID = (data["relatedSpotID"] as? String) ?? (data["spotID"] as? String) ?? ""
        let spotName = (data["relatedSpotName"] as? String) ?? (data["spotName"] as? String) ?? ""
        let tags = data["tags"] as? [String] ?? []
        let crowd = CommunityPost.Crowd.fromStoredValue(data["crowd"] as? String) ?? .normal
        let hasStatusInfo = data["hasStatusInfo"] as? Bool ?? data["crowd"] != nil
        let attachments: [CommunityPhotoAttachment] = (data["attachments"] as? [[String: Any]] ?? []).compactMap {
            (attachment: [String: Any]) -> CommunityPhotoAttachment? in
            guard let id = attachment["id"] as? String,
                  let rawURL = attachment["downloadURL"] as? String,
                  let remoteURL = URL(string: rawURL) else {
                return nil
            }

            return CommunityPhotoAttachment(
                id: id,
                imageData: nil,
                remoteURL: remoteURL,
                metadata: decodeExif(attachment["metadata"] as? [String: Any]),
                location: decodeLocation(attachment["location"] as? [String: Any]),
                sharesToPlaceGallery: attachment["sharesToPlaceGallery"] as? Bool ?? false
            )
        }

        let compatibleAttachments: [CommunityPhotoAttachment]
        if !attachments.isEmpty {
            compatibleAttachments = attachments
        } else if let rawURL = data["photoURL"] as? String,
                  let remoteURL = URL(string: rawURL) {
            compatibleAttachments = [
                CommunityPhotoAttachment(
                    id: "legacy-\(document.documentID)",
                    imageData: nil,
                    remoteURL: remoteURL,
                    metadata: nil,
                    location: nil
                )
            ]
        } else {
            compatibleAttachments = []
        }

        return CommunityPost(
            id: (data["id"] as? String) ?? document.documentID,
            spotID: spotID,
            spotName: spotName,
            title: title,
            captureLocation: captureLocation,
            message: message,
            crowd: hasStatusInfo ? crowd : nil,
            tags: tags,
            photoData: nil,
            photoAttachments: compatibleAttachments,
            hasStatusInfo: hasStatusInfo,
            likeCount: intValue(data["likeCount"]) ?? 0,
            authorID: authorID,
            authorName: authorName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func decodeExif(_ data: [String: Any]?) -> CommunityPhotoExif? {
        guard let data else { return nil }
        let exif = CommunityPhotoExif(
            cameraMake: data["cameraMake"] as? String,
            cameraModel: data["cameraModel"] as? String,
            lensMake: data["lensMake"] as? String,
            lensModel: data["lensModel"] as? String,
            focalLengthMillimeters: doubleValue(data["focalLengthMillimeters"]),
            focalLength35mm: intValue(data["focalLength35mm"]),
            aperture: doubleValue(data["aperture"]),
            exposureTime: doubleValue(data["exposureTime"]),
            iso: intValue(data["iso"]),
            capturedAt: (data["capturedAt"] as? Timestamp)?.dateValue() ?? data["capturedAt"] as? Date
        )
        return exif.isEmpty ? nil : exif
    }

    private static func decodeLocation(_ data: [String: Any]?) -> CommunityPhotoLocation? {
        guard let data,
              let rawVisibility = data["visibility"] as? String,
              let visibility = CommunityLocationVisibility(rawValue: rawVisibility),
              visibility != .privateOnly else {
            return nil
        }
        return CommunityPhotoLocation(
            visibility: visibility,
            regionName: data["regionName"] as? String,
            latitude: doubleValue(data["latitude"]),
            longitude: doubleValue(data["longitude"])
        )
    }

    private static func decodeCaptureLocation(_ data: [String: Any]?) -> CommunityCaptureLocation? {
        guard let data,
              let name = data["name"] as? String,
              !name.isEmpty else {
            return nil
        }

        return CommunityCaptureLocation(
            placeID: data["placeID"] as? String,
            name: name,
            region: data["region"] as? String,
            address: data["address"] as? String
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return value as? Double
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}

private extension CommunityPost {
    func with(
        title: String?,
        captureLocation: CommunityCaptureLocation?,
        attachments: [CommunityPhotoAttachment],
        hasStatusInfo: Bool
    ) -> CommunityPost {
        CommunityPost(
            id: id,
            spotID: spotID,
            spotName: spotName,
            title: title,
            captureLocation: captureLocation,
            message: message,
            crowd: crowd,
            tags: tags,
            photoData: photoData,
            photoAttachments: attachments,
            hasStatusInfo: hasStatusInfo,
            likeCount: likeCount,
            authorID: authorID,
            authorName: authorName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension CommunityPost {
    init(
        id: String,
        spotID: String,
        spotName: String,
        title: String?,
        captureLocation: CommunityCaptureLocation?,
        message: String,
        crowd: Crowd?,
        tags: [String],
        photoData: Data?,
        photoAttachments: [CommunityPhotoAttachment],
        hasStatusInfo: Bool,
        likeCount: Int,
        authorID: String,
        authorName: String,
        createdAt: Date,
        updatedAt: Date?
    ) {
        self.id = id
        self.spotID = spotID
        self.spotName = spotName
        self.title = title
        self.captureLocation = captureLocation
        self.message = message
        self.crowd = crowd ?? .normal
        self.tags = tags
        self.photoData = photoData
        self.photoAttachments = photoAttachments
        self.hasStatusInfo = hasStatusInfo || crowd != nil
        self.likeCount = likeCount
        self.authorID = authorID
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum FirebaseCommunityError: LocalizedError {
    case notConfigured
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase가 구성되지 않았어요."
        case .emptyResponse:
            return "Firebase 응답이 비어 있어요."
        }
    }
}

/// 장소 상세 사진 풀의 Firebase 저장소입니다.
/// Community 사진이 갤러리 공유를 선택한 경우에도 사진 파일은 다시
/// 업로드하지 않고, 이미 Community Storage에 올라간 URL만 참조합니다.
final class FirebasePlacePhotoStore {
    private let firestore: Firestore
    private let storage: Storage

    init(
        firestore: Firestore? = nil,
        storage: Storage? = nil
    ) {
        self.firestore = firestore ?? Firestore.firestore()
        self.storage = storage ?? Storage.storage()
    }

    func fetch(placeID: String) async throws -> [PlacePhoto] {
        guard FirebaseApp.app() != nil else { return [] }

        let snapshot = try await getDocuments(
            from: firestore.collection("placePhotos")
                .whereField("placeID", isEqualTo: placeID)
                .limit(to: 100)
        )

        return snapshot.documents
            .compactMap(Self.decode)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func syncCommunityContribution(_ post: CommunityPost) async throws {
        guard FirebaseApp.app() != nil else { return }

        try await removeCommunityContribution(postID: post.id)
        guard let placeID = post.relatedSpotID else { return }

        for attachment in post.photoAttachments where attachment.sharesToPlaceGallery {
            guard let remoteURL = attachment.remoteURL else { continue }

            let photo = PlacePhoto(
                id: Self.documentID(postID: post.id, attachmentID: attachment.id),
                placeID: placeID,
                imageURL: remoteURL,
                uploaderID: post.authorID,
                uploaderName: post.authorName,
                createdAt: post.createdAt,
                source: .communityContribution,
                communityPostID: post.id
            )

            try await setData(Self.firestoreData(for: photo), on: firestore.collection("placePhotos").document(photo.id))
        }
    }

    /// 기존 Place에 사진만 추가합니다.
    ///
    /// 이 경로에서는 `places`나 장소 제보 문서를 만들지 않고,
    /// 사진 파일과 `placePhotos` 문서만 저장합니다. Community 글의
    /// EXIF 공개 상태와 무관하게 저장 직전에 다시 private-only로
    /// 정리해 장소 사진 풀에는 촬영 메타데이터를 넣지 않습니다.
    func uploadPlaceContribution(
        placeID: String,
        attachments: [CommunityPhotoAttachment],
        uploaderID: String,
        uploaderName: String
    ) async throws -> [PlacePhoto] {
        guard FirebaseApp.app() != nil else {
            throw FirebaseCommunityError.notConfigured
        }

        let batchID = UUID().uuidString
        let baseDate = Date()
        var photos: [PlacePhoto] = []

        for (index, attachment) in attachments
            .prefix(PlaceSubmissionService.maxPhotoCount)
            .enumerated() {
            guard let imageData = attachment.imageData else { continue }

            let photoID = "place-\(batchID)-\(index)"
            let path = "communityPosts/\(Self.safePathComponent(uploaderID))/place-contributions/\(Self.safePathComponent(placeID))/\(photoID).jpg"
            let reference = storage.reference(withPath: path)
            let storageMetadata = StorageMetadata()
            storageMetadata.contentType = "image/jpeg"

            let sanitizedData = CommunityPhotoPrivacyProcessor.sanitizedData(
                from: imageData,
                exifVisibility: .privateOnly
            )
            _ = try await putData(sanitizedData, metadata: storageMetadata, at: reference)
            let downloadURL = try await downloadURL(for: reference)

            photos.append(
                PlacePhoto(
                    id: photoID,
                    placeID: placeID,
                    imageURL: downloadURL,
                    uploaderID: uploaderID,
                    uploaderName: uploaderName,
                    // 첫 번째 선택 사진이 새 사진 풀의 첫 항목이 되도록
                    // 아주 작은 시간 차를 둬 재조회 순서도 보존합니다.
                    createdAt: baseDate.addingTimeInterval(-Double(index) * 0.001),
                    source: .placeContribution
                )
            )
        }

        guard !photos.isEmpty else { return [] }

        let batch = firestore.batch()
        let collection = firestore.collection("placePhotos")
        for photo in photos {
            batch.setData(
                Self.firestoreData(for: photo),
                forDocument: collection.document(photo.id),
                merge: true
            )
        }
        try await commit(batch)
        return photos
    }

    func removeCommunityContribution(postID: String) async throws {
        guard FirebaseApp.app() != nil else { return }

        let snapshot = try await getDocuments(
            from: firestore.collection("placePhotos")
                .whereField("communityPostID", isEqualTo: postID)
        )
        guard !snapshot.documents.isEmpty else { return }

        let batch = firestore.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await commit(batch)
    }

    private static func documentID(postID: String, attachmentID: String) -> String {
        "community-\(postID)-\(attachmentID.replacingOccurrences(of: "/", with: "-"))"
    }

    private static func safePathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    private static func firestoreData(for photo: PlacePhoto) -> [String: Any] {
        var data: [String: Any] = [
            "id": photo.id,
            "placeID": photo.placeID,
            "source": photo.source.rawValue
        ]
        if let imageURL = photo.imageURL {
            data["imageURL"] = imageURL.absoluteString
        }
        if let uploaderID = photo.uploaderID {
            data["uploaderID"] = uploaderID
        }
        if let uploaderName = photo.uploaderName {
            data["uploaderName"] = uploaderName
        }
        if let createdAt = photo.createdAt {
            data["createdAt"] = Timestamp(date: createdAt)
        }
        if let communityPostID = photo.communityPostID {
            data["communityPostID"] = communityPostID
        }
        return data
    }

    private static func decode(_ document: QueryDocumentSnapshot) -> PlacePhoto? {
        let data = document.data()
        guard let placeID = data["placeID"] as? String,
              let rawURL = data["imageURL"] as? String,
              let imageURL = URL(string: rawURL) else {
            return nil
        }

        return PlacePhoto(
            id: (data["id"] as? String) ?? document.documentID,
            placeID: placeID,
            imageURL: imageURL,
            imageName: data["imageName"] as? String,
            uploaderID: data["uploaderID"] as? String,
            uploaderName: data["uploaderName"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            source: PlacePhotoSource(rawValue: data["source"] as? String ?? "") ?? .communityContribution,
            communityPostID: data["communityPostID"] as? String
        )
    }

    private func getDocuments(from query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], on reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func putData(
        _ data: Data,
        metadata: StorageMetadata,
        at reference: StorageReference
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            reference.putData(data, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func downloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func commit(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

/// Place Detail과 Community가 함께 바라보는 장소 사진 캐시입니다.
@MainActor
final class PlacePhotoGalleryStore: ObservableObject {
    static let shared = PlacePhotoGalleryStore()

    @Published private(set) var photosByPlaceID: [String: [PlacePhoto]] = [:]

    private let remoteStore: FirebasePlacePhotoStore
    private var loadedPlaceIDs: Set<String> = []

    init(remoteStore: FirebasePlacePhotoStore = FirebasePlacePhotoStore()) {
        self.remoteStore = remoteStore
    }

    func photos(for spot: PhotoSpot) -> [PlacePhoto] {
        Self.deduplicated(spot.galleryPhotos + (photosByPlaceID[spot.id] ?? []))
            .filter(\.hasDisplayImage)
    }

    func load(for spot: PhotoSpot) async -> [PlacePhoto] {
        if !spot.galleryPhotos.isEmpty {
            photosByPlaceID[spot.id] = Self.deduplicated(
                spot.galleryPhotos + (photosByPlaceID[spot.id] ?? [])
            )
        }

        guard !loadedPlaceIDs.contains(spot.id) else {
            return photos(for: spot)
        }
        loadedPlaceIDs.insert(spot.id)

        do {
            let remotePhotos = try await remoteStore.fetch(placeID: spot.id)
            photosByPlaceID[spot.id] = Self.deduplicated(
                spot.galleryPhotos + (photosByPlaceID[spot.id] ?? []) + remotePhotos
            )
        } catch {
            AppLog.persistence.error(
                "Place photo pool fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        return photos(for: spot)
    }

    /// 기존 장소에 사진만 추가하는 공통 경로입니다.
    /// 반환된 사진은 캐시에 먼저 반영되어, 업로드 완료 후 Place Detail을
    /// 열면 별도의 장소 재생성 없이 바로 사진 풀에서 읽을 수 있습니다.
    func contributePhotos(
        for spot: PhotoSpot,
        attachments: [CommunityPhotoAttachment],
        uploader: AuthUser
    ) async throws -> [PlacePhoto] {
        let uploadableAttachments = attachments
            .filter { $0.imageData != nil }
            .prefix(PlaceSubmissionService.maxPhotoCount)

        guard !uploadableAttachments.isEmpty else { return [] }

        let newPhotos = try await remoteStore.uploadPlaceContribution(
            placeID: spot.id,
            attachments: Array(uploadableAttachments),
            uploaderID: uploader.id,
            uploaderName: uploader.displayName
        )

        photosByPlaceID[spot.id] = Self.deduplicated(
            (photosByPlaceID[spot.id] ?? []) + newPhotos
        )
        loadedPlaceIDs.insert(spot.id)
        return newPhotos
    }

    /// Community 글이 로컬에서 먼저 보이도록 사진 풀에도 즉시 반영합니다.
    func applyLocalContribution(post: CommunityPost) {
        guard let placeID = post.relatedSpotID else { return }

        var photos = photosByPlaceID[placeID] ?? []
        photos.removeAll { $0.communityPostID == post.id }
        photos.append(contentsOf: post.photoAttachments.compactMap { attachment in
            guard attachment.sharesToPlaceGallery,
                  attachment.imageData != nil || attachment.remoteURL != nil else {
                return nil
            }

            return PlacePhoto(
                id: "community-\(post.id)-\(attachment.id)",
                placeID: placeID,
                imageURL: attachment.remoteURL,
                imageData: attachment.imageData,
                uploaderID: post.authorID,
                uploaderName: post.authorName,
                createdAt: post.createdAt,
                source: .communityContribution,
                communityPostID: post.id
            )
        })
        photosByPlaceID[placeID] = Self.deduplicated(photos)
    }

    func removeLocalContribution(postID: String) {
        for placeID in photosByPlaceID.keys {
            photosByPlaceID[placeID]?.removeAll { $0.communityPostID == postID }
        }
    }

    func syncCommunityContribution(post: CommunityPost) async {
        applyLocalContribution(post: post)

        do {
            try await remoteStore.syncCommunityContribution(post)
            guard let placeID = post.relatedSpotID else { return }
            let remotePhotos = try await remoteStore.fetch(placeID: placeID)
            photosByPlaceID[placeID] = Self.deduplicated(
                (photosByPlaceID[placeID] ?? []) + remotePhotos
            )
        } catch {
            AppLog.persistence.error(
                "Place photo pool sync failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func removeCommunityContribution(postID: String) async {
        removeLocalContribution(postID: postID)
        do {
            try await remoteStore.removeCommunityContribution(postID: postID)
        } catch {
            AppLog.persistence.error(
                "Place photo contribution removal failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func deduplicated(_ photos: [PlacePhoto]) -> [PlacePhoto] {
        var seenIDs = Set<String>()
        var seenRemoteImages = Set<String>()
        var seenAssetImages = Set<String>()

        return photos.filter { photo in
            let remoteKey = photo.imageURL.map {
                "\(photo.placeID)|\($0.absoluteString)"
            }
            let assetKey = photo.imageName.map {
                "\(photo.placeID)|\($0)"
            }

            guard !seenIDs.contains(photo.id),
                  remoteKey.map({ !seenRemoteImages.contains($0) }) ?? true,
                  assetKey.map({ !seenAssetImages.contains($0) }) ?? true else {
                return false
            }

            seenIDs.insert(photo.id)
            if let remoteKey { seenRemoteImages.insert(remoteKey) }
            if let assetKey { seenAssetImages.insert(assetKey) }
            return true
        }
    }
}

final class FirebaseCrowdReportStore {
    private let firestore: Firestore

    init(firestore: Firestore? = nil) {
        self.firestore = firestore ?? Firestore.firestore()
    }

    func fetch(placeID: String) async throws -> [CrowdReport] {
        guard FirebaseApp.app() != nil else { return [] }

        let snapshot = try await getDocuments(
            from: firestore.collection("crowdReports")
                .whereField("placeID", isEqualTo: placeID)
                .limit(to: 100)
        )
        return snapshot.documents
            .compactMap(Self.decode)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestReport(
        placeID: String,
        authorID: String,
        since: Date
    ) async throws -> CrowdReport? {
        guard FirebaseApp.app() != nil else { return nil }

        let documents = try await userReportDocuments(placeID: placeID, authorID: authorID)
        return documents
            .compactMap(Self.decode)
            .filter { $0.updatedAt >= since }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// 사용자+장소 조합의 canonical 문서를 upsert합니다.
    ///
    /// 문서 ID는 CrowdReportStore가 결정적으로 만들기 때문에 동시에 여러
    /// 기기에서 제보해도 최종적으로 하나의 문서만 남습니다. 기존에 random ID로
    /// 저장된 레거시 문서는 같은 batch에서 정리합니다.
    func upsert(_ report: CrowdReport) async throws {
        guard FirebaseApp.app() != nil else { return }

        let collection = firestore.collection("crowdReports")
        let canonicalReference = collection.document(report.id)
        let legacyDocuments = try await userReportDocuments(
            placeID: report.placeID,
            authorID: report.authorID
        )

        let batch = firestore.batch()
        batch.setData(
            Self.firestoreData(for: report),
            forDocument: canonicalReference,
            merge: true
        )

        for document in legacyDocuments where document.documentID != report.id {
            batch.deleteDocument(document.reference)
        }

        try await commit(batch)
    }

    /// 사용자+장소의 active 제보를 모두 제거합니다.
    /// canonical 문서뿐 아니라 예전 random ID 문서도 함께 지워
    /// 취소 직후 aggregation에 다시 나타나지 않도록 합니다.
    func deleteReports(placeID: String, authorID: String) async throws {
        guard FirebaseApp.app() != nil else { return }

        let documents = try await userReportDocuments(placeID: placeID, authorID: authorID)
        guard !documents.isEmpty else { return }

        let batch = firestore.batch()
        documents.forEach { batch.deleteDocument($0.reference) }
        try await commit(batch)
    }

    func removeCommunityReport(postID: String) async throws {
        guard FirebaseApp.app() != nil else { return }

        let snapshot = try await getDocuments(
            from: firestore.collection("crowdReports")
                .whereField("communityPostID", isEqualTo: postID)
        )
        guard !snapshot.documents.isEmpty else { return }

        let batch = firestore.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await commit(batch)
    }

    private static func firestoreData(for report: CrowdReport) -> [String: Any] {
        var data: [String: Any] = [
            "id": report.id,
            "placeID": report.placeID,
            "crowd": report.crowd.rawValue,
            "authorID": report.authorID,
            "createdAt": Timestamp(date: report.createdAt),
            "updatedAt": Timestamp(date: report.updatedAt),
            "source": report.source.rawValue
        ]
        if let communityPostID = report.communityPostID {
            data["communityPostID"] = communityPostID
        }
        return data
    }

    private static func decode(_ document: QueryDocumentSnapshot) -> CrowdReport? {
        let data = document.data()
        guard let placeID = data["placeID"] as? String,
              let rawCrowd = data["crowd"] as? String,
              let crowd = CommunityPost.Crowd.fromStoredValue(rawCrowd),
              let authorID = data["authorID"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return CrowdReport(
            id: (data["id"] as? String) ?? document.documentID,
            placeID: placeID,
            crowd: crowd,
            authorID: authorID,
            createdAt: createdAt,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt,
            source: CrowdReportSource(rawValue: data["source"] as? String ?? "") ?? .placeDetail,
            communityPostID: data["communityPostID"] as? String
        )
    }

    private func getDocuments(from query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseCommunityError.emptyResponse)
                }
            }
        }
    }

    private func userReportDocuments(
        placeID: String,
        authorID: String
    ) async throws -> [QueryDocumentSnapshot] {
        do {
            let snapshot = try await getDocuments(
                from: firestore.collection("crowdReports")
                    .whereField("placeID", isEqualTo: placeID)
                    .whereField("authorID", isEqualTo: authorID)
            )
            return snapshot.documents
        } catch {
            // 복합 인덱스가 아직 배포되지 않은 환경에서도
            // 장소 단위 조회 후 authorID로 좁혀 같은 동작을 유지합니다.
            let snapshot = try await getDocuments(
                from: firestore.collection("crowdReports")
                    .whereField("placeID", isEqualTo: placeID)
            )
            return snapshot.documents.filter { document in
                document.data()["authorID"] as? String == authorID
            }
        }
    }

    private func setData(_ data: [String: Any], on reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func commit(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class CrowdReportStore: ObservableObject {
    static let shared = CrowdReportStore()
    static let freshnessWindow = VFLiveCrowd.freshnessWindow

    @Published private(set) var reports: [CrowdReport] = []

    private let remoteStore: FirebaseCrowdReportStore
    private var loadedPlaceIDs: Set<String> = []
    @Published private(set) var loadingPlaceIDs: Set<String> = []
    private var submittingKeys: Set<String> = []

    init(remoteStore: FirebaseCrowdReportStore = FirebaseCrowdReportStore()) {
        self.remoteStore = remoteStore
    }

    func reports(for spot: PhotoSpot) -> [CrowdReport] {
        reports.filter { $0.placeID == spot.id }
    }

    func isSubmitting(placeID: String, authorID: String) -> Bool {
        submittingKeys.contains(submissionKey(placeID: placeID, authorID: authorID))
    }

    func isLoading(placeID: String) -> Bool {
        loadingPlaceIDs.contains(placeID)
    }

    func load(for spot: PhotoSpot) async {
        guard !loadedPlaceIDs.contains(spot.id), !loadingPlaceIDs.contains(spot.id) else {
            return
        }
        loadingPlaceIDs.insert(spot.id)

        do {
            let remoteReports = try await remoteStore.fetch(placeID: spot.id)
            merge(remoteReports)
            loadedPlaceIDs.insert(spot.id)
        } catch {
            AppLog.persistence.error(
                "Crowd report fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        loadingPlaceIDs.remove(spot.id)
    }

    /// 같은 상태를 다시 누르면 기존 제보를 취소하고,
    /// 다른 상태를 누르면 같은 사용자+장소 문서를 갱신합니다.
    @discardableResult
    func toggle(
        placeID: String,
        crowd: CommunityPost.Crowd,
        authorID: String,
        source: CrowdReportSource
    ) -> Bool {
        let now = Date()
        if let existing = latestFreshReport(
            in: reports,
            placeID: placeID,
            authorID: authorID,
            now: now
        ), existing.crowd == crowd {
            return remove(placeID: placeID, authorID: authorID)
        }

        return submit(
            placeID: placeID,
            crowd: crowd,
            authorID: authorID,
            source: source
        )
    }

    /// 사용자의 장소별 active 제보를 즉시 로컬에서 제거한 뒤,
    /// Firestore에서도 canonical/레거시 문서를 함께 삭제합니다.
    @discardableResult
    func remove(placeID: String, authorID: String) -> Bool {
        guard !authorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let key = submissionKey(placeID: placeID, authorID: authorID)
        guard !submittingKeys.contains(key) else { return false }
        submittingKeys.insert(key)

        let removedReports = reports.filter {
            $0.placeID == placeID && $0.authorID == authorID
        }
        reports.removeAll {
            $0.placeID == placeID && $0.authorID == authorID
        }

        Task { [weak self, remoteStore] in
            do {
                try await remoteStore.deleteReports(placeID: placeID, authorID: authorID)
            } catch {
                AppLog.persistence.error(
                    "Crowd report removal failed: \(error.localizedDescription, privacy: .public)"
                )
                self?.restore(
                    removedReports,
                    submissionKey: key
                )
                return
            }

            self?.finishSubmission(for: key)
        }

        return true
    }

    @discardableResult
    func submit(
        placeID: String,
        crowd: CommunityPost.Crowd,
        authorID: String,
        source: CrowdReportSource,
        communityPostID: String? = nil
    ) -> Bool {
        guard !authorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let key = submissionKey(placeID: placeID, authorID: authorID)
        guard !submittingKeys.contains(key) else { return false }
        submittingKeys.insert(key)

        let now = Date()
        let localExisting = latestFreshReport(
            in: reports,
            placeID: placeID,
            authorID: authorID,
            now: now
        )
        let fallbackReportID = Self.deterministicReportID(placeID: placeID, authorID: authorID)
        let reportSource: CrowdReportSource = communityPostID == nil ? .placeDetail : .community
        let optimisticReport = CrowdReport(
            id: localExisting?.id ?? fallbackReportID,
            placeID: placeID,
            crowd: crowd,
            authorID: authorID,
            createdAt: localExisting?.createdAt ?? now,
            updatedAt: now,
            source: reportSource,
            communityPostID: communityPostID
        )
        merge([optimisticReport])

        Task { [weak self, remoteStore] in
            let lookupDate = Date()
            var remoteExisting: CrowdReport?
            do {
                remoteExisting = try await remoteStore.latestReport(
                    placeID: placeID,
                    authorID: authorID,
                    since: lookupDate.addingTimeInterval(-Self.freshnessWindow)
                )
            } catch {
                AppLog.persistence.error(
                    "Crowd report lookup failed: \(error.localizedDescription, privacy: .public)"
                )
            }

            let existing = [localExisting, remoteExisting]
                .compactMap { $0 }
                .max { $0.updatedAt < $1.updatedAt }
            let submissionDate = Date()
            // 기존 random ID 문서가 발견되어도 항상 canonical ID로 저장합니다.
            // 그래야 다음 상태 변경이 새 문서를 만들지 않고 같은 문서를 갱신합니다.
            let report = CrowdReport(
                id: fallbackReportID,
                placeID: placeID,
                crowd: crowd,
                authorID: authorID,
                createdAt: existing?.createdAt ?? submissionDate,
                updatedAt: submissionDate,
                source: reportSource,
                communityPostID: communityPostID
            )

            await self?.persist(report, submissionKey: key, remoteStore: remoteStore)
        }

        return true
    }

    func removeCommunityReport(postID: String) {
        reports.removeAll { $0.communityPostID == postID }
        Task { [weak self, remoteStore] in
            do {
                try await remoteStore.removeCommunityReport(postID: postID)
            } catch {
                AppLog.persistence.error(
                    "Crowd report removal failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            _ = self
        }
    }

    private func persist(
        _ report: CrowdReport,
        submissionKey: String,
        remoteStore: FirebaseCrowdReportStore
    ) async {
        // 화면은 서버 응답을 기다리지 않고 최신 선택을 즉시 보여줍니다.
        merge([report])

        do {
            // 새 report는 사용자+장소 기반의 결정적 ID를 사용하고,
            // 기존 freshness report는 같은 document ID로 덮어씁니다.
            try await remoteStore.upsert(report)
        } catch {
            AppLog.persistence.error(
                "Crowd report upload failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        submittingKeys.remove(submissionKey)
    }

    private func restore(
        _ reportsToRestore: [CrowdReport],
        submissionKey: String
    ) {
        merge(reportsToRestore)
        submittingKeys.remove(submissionKey)
    }

    private func finishSubmission(for submissionKey: String) {
        submittingKeys.remove(submissionKey)
    }

    private func latestFreshReport(
        in reports: [CrowdReport],
        placeID: String,
        authorID: String,
        now: Date
    ) -> CrowdReport? {
        let cutoff = now.addingTimeInterval(-Self.freshnessWindow)
        return reports
            .filter {
                $0.placeID == placeID
                    && $0.authorID == authorID
                    && $0.updatedAt >= cutoff
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func submissionKey(placeID: String, authorID: String) -> String {
        "\(placeID)\u{001F}\(authorID)"
    }

    private static func deterministicReportID(placeID: String, authorID: String) -> String {
        let encoded = Data("\(placeID)|\(authorID)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "user-\(encoded)"
    }

    private func merge(_ newReports: [CrowdReport]) {
        var merged = reports
        for report in newReports {
            if let index = merged.firstIndex(where: { $0.id == report.id }) {
                if report.updatedAt >= merged[index].updatedAt {
                    merged[index] = report
                }
            } else if let index = merged.firstIndex(where: {
                !$0.authorID.isEmpty
                    && $0.authorID == report.authorID
                    && $0.placeID == report.placeID
            }) {
                // 레거시 random ID 문서가 로컬에 남아 있어도
                // 같은 사용자+장소의 최신 문서 하나만 유지합니다.
                if report.updatedAt >= merged[index].updatedAt {
                    merged[index] = report
                }
            } else {
                merged.append(report)
            }
        }
        reports = merged.sorted { $0.updatedAt > $1.updatedAt }
    }
}
