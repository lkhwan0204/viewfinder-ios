import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { after, before, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "demo-viewfinder-rules";
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

function makePost(id, authorID, overrides = {}) {
  return {
    id,
    authorID,
    authorName: "ViewFinder 사용자",
    message: "빛이 좋은 장소였어요.",
    tags: [],
    hasStatusInfo: false,
    likeCount: 0,
    createdAt: Timestamp.fromDate(new Date(Date.now() - 30_000)),
    attachments: [],
    ...overrides,
  };
}

function makeAttachment(index) {
  return {
    id: `attachment-${index}`,
    downloadURL: `https://firebasestorage.googleapis.com/v0/b/test/o/${index}`,
  };
}

function makePlacePhoto(id, uploaderID, overrides = {}) {
  return {
    id,
    placeID: "place-123",
    source: "placeContribution",
    imageURL: "https://firebasestorage.googleapis.com/v0/b/test/o/photo.jpg",
    uploaderID,
    uploaderName: "ViewFinder 사용자",
    createdAt: Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)),
    ...overrides,
  };
}

function makeUserPlace(ownerID, overrides = {}) {
  return {
    name: "사용자 출사지",
    address: "서울특별시 영등포구 문래동",
    summary: "저녁빛이 좋은 장소예요.",
    tags: ["야경", "골목"],
    latitude: 37.517,
    longitude: 126.895,
    primaryTheme: "retroAlley",
    source: "user-submitted",
    schemaVersion: 1,
    createdBy: ownerID,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    status: "active",
    reason: "저녁 시간 추천",
    bestTime: "해 질 무렵",
    ...overrides,
  };
}

function makeCrowdReport(id, authorID, overrides = {}) {
  const now = Timestamp.fromDate(new Date(Date.now() - 60_000));
  return {
    id,
    placeID: "place-123",
    crowd: "여유",
    authorID,
    createdAt: now,
    updatedAt: now,
    source: "placeDetail",
    ...overrides,
  };
}

function canonicalCrowdReportID(placeID, uid) {
  const encoded = Buffer.from(`${placeID}|${uid}`, "utf8").toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `user-${encoded}`;
}

test("Community, PlacePhoto, CrowdReport, Users allow/deny matrix", async (t) => {
  await testEnvironment.clearFirestore();

  const guestDB = testEnvironment.unauthenticatedContext().firestore();
  const aliceDB = testEnvironment.authenticatedContext("alice").firestore();
  const bobDB = testEnvironment.authenticatedContext("bob").firestore();

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "places/seed-public-place"), {
      name: "공개 출사지",
      latitude: 37.5,
      longitude: 126.9,
    });
  });

  await t.test("places are publicly readable; only an owner can create/edit/soft-delete their user place", async () => {
    await assertSucceeds(getDoc(doc(guestDB, "places/seed-public-place")));
    await assertSucceeds(getDoc(doc(aliceDB, "places/seed-public-place")));
    await assertSucceeds(getDocs(collection(guestDB, "places")));

    await assertFails(setDoc(doc(guestDB, "places/guest-created"), makeUserPlace("guest")));
    await assertSucceeds(setDoc(doc(aliceDB, "places/alice-place"), makeUserPlace("alice")));
    await assertFails(setDoc(doc(aliceDB, "places/forged-owner"), makeUserPlace("bob")));
    await assertFails(setDoc(doc(aliceDB, "places/local-source-create"), makeUserPlace("alice", {
      source: "local",
    })));
    await assertFails(setDoc(doc(aliceDB, "places/with-photo-url"), makeUserPlace("alice", {
      imageURL: "https://example.test/remote-image.jpg",
    })));

    const ownerReference = doc(aliceDB, "places/alice-place");
    await assertSucceeds(updateDoc(ownerReference, {
      summary: "수정한 소개예요.",
      primaryTheme: "cityArchitecture",
      tags: ["야경", "건축"],
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(bobDB, "places/alice-place"), {
      summary: "타인 장소 수정 시도",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ownerReference, {
      createdBy: "bob",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ownerReference, {
      name: "장소 식별명 변경 시도",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ownerReference, {
      source: "local",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ownerReference, {
      createdAt: Timestamp.fromMillis(Date.now() + 60_000),
      updatedAt: serverTimestamp(),
    }));

    await assertFails(updateDoc(doc(bobDB, "places/alice-place"), {
      status: "deleted",
      deletedAt: serverTimestamp(),
      deletedBy: "bob",
      updatedAt: serverTimestamp(),
    }));

    await assertSucceeds(updateDoc(ownerReference, {
      status: "deleted",
      deletedAt: serverTimestamp(),
      deletedBy: "alice",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ownerReference, {
      status: "active",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(deleteDoc(ownerReference));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "places/legacy-unowned"), {
        ...makeUserPlace("legacy-user", {
          createdAt: Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)),
          updatedAt: Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)),
        }),
      });
      await setDoc(doc(context.firestore(), "places/local-seed"), {
        name: "로컬 seed 장소",
        address: "서울",
        summary: "기존 seed",
        tags: [],
        latitude: 37.5,
        longitude: 126.9,
        primaryTheme: "landscape",
        source: "local",
        schemaVersion: 1,
      });
    });
    await assertFails(updateDoc(doc(aliceDB, "places/legacy-unowned"), {
      summary: "레거시 소유자를 임의로 주장",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(aliceDB, "places/local-seed"), {
      summary: "seed 수정 시도",
      updatedAt: serverTimestamp(),
    }));
  });

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "communityPosts/public-post"),
      makePost("public-post", "alice"));
  });

  await t.test("guest can read public Community, PlacePhoto and CrowdReport documents", async () => {
    await assertSucceeds(getDoc(doc(guestDB, "communityPosts/public-post")));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "placePhotos/public-photo"),
        makePlacePhoto("public-photo", "alice"));
      const guestReadPlaceID = "guest-read-place";
      const crowdID = canonicalCrowdReportID(guestReadPlaceID, "alice");
      await setDoc(doc(db, `crowdReports/${crowdID}`),
        makeCrowdReport(crowdID, "alice", { placeID: guestReadPlaceID }));
    });

    await assertSucceeds(getDoc(doc(guestDB, "placePhotos/public-photo")));
    await assertSucceeds(getDocs(collection(guestDB, "crowdReports")));
  });

  await t.test("guest cannot create a Community post", async () => {
    await assertFails(setDoc(
      doc(guestDB, "communityPosts/guest-post"),
      makePost("guest-post", "guest"),
    ));
  });

  await t.test("owner can create posts with zero and maximum eight photos", async () => {
    const noPhoto = makePost("alice-no-photo", "alice");
    await assertSucceeds(setDoc(doc(aliceDB, "communityPosts/alice-no-photo"), noPhoto));

    const attachments = Array.from({ length: 8 }, (_, index) => makeAttachment(index));
    attachments[0].metadata = {
      cameraMake: "Apple",
      cameraModel: "iPhone",
      focalLengthMillimeters: 6,
      capturedAt: Timestamp.fromDate(new Date(Date.now() - 60_000)),
    };
    const eightPhotos = makePost("alice-eight-photos", "alice", {
      attachments,
    });
    await assertSucceeds(
      setDoc(doc(aliceDB, "communityPosts/alice-eight-photos"), eightPhotos),
    );
    await assertSucceeds(updateDoc(doc(aliceDB, "communityPosts/alice-eight-photos"), {
      message: "8장 사진 게시물 수정",
      createdAt: eightPhotos.createdAt,
      updatedAt: Timestamp.fromDate(new Date(Date.now() - 10_000)),
      attachments,
    }));

    const ninePhotos = makePost("alice-nine-photos", "alice", {
      attachments: Array.from({ length: 9 }, (_, index) => makeAttachment(index)),
    });
    await assertFails(
      setDoc(doc(aliceDB, "communityPosts/alice-nine-photos"), ninePhotos),
    );
  });

  await t.test("Community optional crowd and edited payload is accepted", async () => {
    const post = makePost("alice-crowd-post", "alice", {
      title: "블루아워 촬영 기록",
      tags: ["야경", "블루아워"],
      hasStatusInfo: true,
      crowd: "많음",
    });
    const reference = doc(aliceDB, "communityPosts/alice-crowd-post");
    await assertSucceeds(setDoc(reference, post));
    await assertSucceeds(updateDoc(reference, {
      message: "업데이트된 촬영 후기입니다.",
      createdAt: post.createdAt,
      updatedAt: Timestamp.fromDate(new Date(Date.now() - 10_000)),
      crowd: "여유",
    }));
  });

  await t.test("Community related place and manual capture location are accepted", async () => {
    const post = makePost("alice-location-post", "alice", {
      relatedSpotID: "place-123",
      relatedSpotName: "문래창작촌",
      captureLocation: {
        name: "문래창작촌 안쪽 골목",
        placeID: "place-123",
        region: "서울 영등포구",
        address: "서울특별시 영등포구 문래동",
      },
    });
    await assertSucceeds(
      setDoc(doc(aliceDB, "communityPosts/alice-location-post"), post),
    );
  });

  await t.test("Community EXIF and place-gallery attachment payload is accepted", async () => {
    const post = makePost("alice-metadata-post", "alice", {
      relatedSpotID: "place-123",
      relatedSpotName: "문래창작촌",
      attachments: [{
        ...makeAttachment(20),
        metadata: { lensModel: "XF27mm F2.8", aperture: 2.8 },
        sharesToPlaceGallery: true,
      }],
    });
    await assertSucceeds(
      setDoc(doc(aliceDB, "communityPosts/alice-metadata-post"), post),
    );

    const gpsPost = makePost("alice-gps-post", "alice", {
      attachments: [{
        ...makeAttachment(21),
        metadata: { GPSLatitude: 37.5, GPSLongitude: 126.9 },
      }],
    });
    await assertFails(setDoc(doc(aliceDB, "communityPosts/alice-gps-post"), gpsPost));

    const insecureURLPost = makePost("alice-http-photo-post", "alice", {
      attachments: [{ id: "http-photo", downloadURL: "http://example.test/photo.jpg" }],
    });
    await assertFails(
      setDoc(doc(aliceDB, "communityPosts/alice-http-photo-post"), insecureURLPost),
    );
  });

  await t.test("authorID cannot be forged", async () => {
    const forged = makePost("forged-author", "bob");
    await assertFails(setDoc(doc(aliceDB, "communityPosts/forged-author"), forged));
  });

  await t.test("only the author can update/delete; legacy spot fields can only be removed", async () => {
    const createdAt = Timestamp.fromDate(new Date(Date.now() - 90_000));
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "communityPosts/legacy-post"),
        makePost("legacy-post", "alice", {
          createdAt,
          spotID: "legacy-place-id",
          spotName: "레거시 장소",
          photoURL: "https://firebasestorage.googleapis.com/v0/b/test/o/legacy.jpg",
        }));
    });

    await assertSucceeds(updateDoc(doc(aliceDB, "communityPosts/legacy-post"), {
      message: "수정된 본문입니다.",
      updatedAt: Timestamp.now(),
      createdAt,
      spotID: deleteField(),
      spotName: deleteField(),
    }));
    await assertSucceeds(deleteDoc(doc(aliceDB, "communityPosts/alice-no-photo")));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "communityPosts/legacy-fields-post"),
        makePost("legacy-fields-post", "alice", { createdAt, spotID: "old-id" }));
    });
    await assertFails(updateDoc(doc(aliceDB, "communityPosts/legacy-fields-post"), {
      spotID: "replacement-id",
      updatedAt: Timestamp.now(),
      createdAt,
    }));

    await assertFails(updateDoc(doc(bobDB, "communityPosts/legacy-post"), {
      message: "타인 글 수정 시도",
      updatedAt: Timestamp.now(),
      createdAt,
    }));
    await assertFails(deleteDoc(doc(bobDB, "communityPosts/legacy-post")));
  });

  await t.test("new Community posts cannot contain legacy photoURL", async () => {
    const legacyURL = makePost("legacy-url-create", "alice", {
      photoURL: "https://firebasestorage.googleapis.com/v0/b/test/o/old.jpg",
    });
    await assertFails(setDoc(doc(aliceDB, "communityPosts/legacy-url-create"), legacyURL));
  });

  await t.test("PlacePhoto owner can create/delete; a forged uploader is denied", async () => {
    const ownPhoto = makePlacePhoto("alice-photo", "alice");
    await assertSucceeds(setDoc(doc(aliceDB, "placePhotos/alice-photo"), ownPhoto));
    await assertSucceeds(updateDoc(doc(aliceDB, "placePhotos/alice-photo"), {
      uploaderName: "앨리스",
      createdAt: ownPhoto.createdAt,
    }));
    await assertFails(updateDoc(doc(bobDB, "placePhotos/alice-photo"), {
      uploaderName: "위조",
      createdAt: ownPhoto.createdAt,
    }));
    await assertSucceeds(deleteDoc(doc(aliceDB, "placePhotos/alice-photo")));

    const forgedPhoto = makePlacePhoto("forged-photo", "bob");
    await assertFails(setDoc(doc(aliceDB, "placePhotos/forged-photo"), forgedPhoto));

    const communityPhoto = makePlacePhoto("community-photo", "alice", {
      source: "communityContribution",
      communityPostID: "public-post",
    });
    await assertSucceeds(
      setDoc(doc(aliceDB, "placePhotos/community-photo"), communityPhoto),
    );
  });

  await t.test("CrowdReport requires canonical ID; owner can update/delete", async () => {
    const canonicalID = canonicalCrowdReportID("place-123", "alice");
    const report = makeCrowdReport(canonicalID, "alice");
    const reportRef = doc(aliceDB, `crowdReports/${canonicalID}`);
    try {
      await assertSucceeds(setDoc(reportRef, report));
    } catch (error) {
      throw new Error(`canonical create failed: ${error.message}`, { cause: error });
    }
    try {
      await assertSucceeds(updateDoc(reportRef, {
        crowd: "많음",
        updatedAt: Timestamp.fromDate(new Date(Date.now() - 10_000)),
      }));
    } catch (error) {
      throw new Error(`canonical update failed: ${error.message}`, { cause: error });
    }
    try {
      await assertSucceeds(deleteDoc(reportRef));
    } catch (error) {
      throw new Error(`canonical delete failed: ${error.message}`, { cause: error });
    }

    const arbitraryID = "random-report-id";
    await assertFails(setDoc(
      doc(aliceDB, `crowdReports/${arbitraryID}`),
      makeCrowdReport(arbitraryID, "alice"),
    ));

    const communityPlaceID = "community-crowd-place";
    const communityReportID = canonicalCrowdReportID(communityPlaceID, "alice");
    await assertSucceeds(setDoc(
      doc(aliceDB, `crowdReports/${communityReportID}`),
      makeCrowdReport(communityReportID, "alice", {
        placeID: communityPlaceID,
        source: "community",
        communityPostID: "alice-context-post",
      }),
    ));

    // Exercise Swift's Base64 substitutions and padding removal with inputs
    // that produce '+' / '/' and '=' in standard Base64.
    for (const [placeID, uid] of [["?", ">"], ["?", "?"], ["ab", "x"]]) {
      const edgeUserDB = testEnvironment.authenticatedContext(uid).firestore();
      const edgeID = canonicalCrowdReportID(placeID, uid);
      await assertSucceeds(setDoc(
        doc(edgeUserDB, `crowdReports/${edgeID}`),
        makeCrowdReport(edgeID, uid, { placeID }),
      ));
    }
  });

  await t.test("Community crowd upsert preserves canonical createdAt on retry", async () => {
    const placeID = "community-retry-place";
    const id = canonicalCrowdReportID(placeID, "alice");
    const reference = doc(aliceDB, `crowdReports/${id}`);
    const original = makeCrowdReport(id, "alice", { placeID });
    await assertSucceeds(setDoc(reference, original));
    await assertSucceeds(setDoc(reference, {
      ...original,
      crowd: "많음",
      source: "community",
      communityPostID: "retry-post-1",
      updatedAt: Timestamp.fromDate(new Date(Date.now() - 10_000)),
    }, { merge: true }));
    await assertSucceeds(setDoc(reference, {
      ...original,
      crowd: "보통",
      source: "community",
      communityPostID: "retry-post-1",
      updatedAt: Timestamp.fromDate(new Date(Date.now() - 5_000)),
    }, { merge: true }));
    assert.equal((await getDoc(reference)).data()?.createdAt.toMillis(), original.createdAt.toMillis());
  });

  await t.test("user can create/get/update only their own profile", async () => {
    const aliceProfile = doc(aliceDB, "users/alice");
    await assertSucceeds(setDoc(aliceProfile, {
      uid: "alice",
      provider: "apple",
      displayName: "앨리스",
      email: null,
      createdAt: serverTimestamp(),
      lastLoginAt: serverTimestamp(),
    }));
    await assertSucceeds(getDoc(aliceProfile));
    await assertSucceeds(updateDoc(aliceProfile, {
      displayName: "앨리스 업데이트",
      lastLoginAt: serverTimestamp(),
    }));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/bob"), {
        uid: "bob",
        provider: "google",
        displayName: "밥",
        email: null,
        createdAt: Timestamp.now(),
        lastLoginAt: Timestamp.now(),
      });
    });
    await assertFails(getDoc(doc(aliceDB, "users/bob")));
    await assertFails(updateDoc(doc(aliceDB, "users/bob"), {
      displayName: "위조",
      lastLoginAt: serverTimestamp(),
    }));
    await assertFails(getDocs(collection(aliceDB, "users")));
  });

  await t.test("unlisted collections remain denied", async () => {
    await assertFails(getDoc(doc(aliceDB, "privateData/secret")));
  });

  assert.equal(projectId, "demo-viewfinder-rules");
});
