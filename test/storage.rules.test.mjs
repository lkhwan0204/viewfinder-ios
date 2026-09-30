import { readFile } from "node:fs/promises";
import { after, before, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteObject,
  getBytes,
  listAll,
  ref,
  uploadBytes,
} from "firebase/storage";

// storage.rules 를 Storage 대역(에뮬레이터)에서 확인합니다. (npm run test:rules)

const projectId = "demo-viewfinder-rules";
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    storage: {
      rules: await readFile(new URL("../storage.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

const photoID = "9164B446-1355-47C0-8563-EE8E5A429B3D";
const jpeg = { contentType: "image/jpeg" };
const bytes = (size) => new Uint8Array(size).fill(0xff);
const maxSize = 2 * 1024 * 1024;

test("Storage: community post photos and place contributions", async (t) => {
  await testEnvironment.clearStorage();

  const aliceStorage = testEnvironment.authenticatedContext("alice").storage();
  const bobStorage = testEnvironment.authenticatedContext("bob").storage();
  const guestStorage = testEnvironment.unauthenticatedContext().storage();

  const postPhoto = `communityPosts/alice/post-1/${photoID}.jpg`;
  const placePhoto = `communityPosts/alice/place-contributions/place-123/place-${photoID}-0.jpg`;

  await t.test("owner uploads a reduced JPEG to their own post folder", async () => {
    await assertSucceeds(uploadBytes(ref(aliceStorage, postPhoto), bytes(300 * 1024), jpeg));
  });

  await t.test("anyone can read one photo, nobody can list a folder", async () => {
    await assertSucceeds(getBytes(ref(guestStorage, postPhoto)));
    await assertSucceeds(getBytes(ref(bobStorage, postPhoto)));
    await assertFails(listAll(ref(guestStorage, "communityPosts/alice/post-1")));
    await assertFails(listAll(ref(aliceStorage, "communityPosts/alice/post-1")));
  });

  await t.test("guests and other users cannot upload into alice's folder", async () => {
    await assertFails(uploadBytes(ref(guestStorage, `communityPosts/alice/post-1/${photoID}-guest.jpg`), bytes(1024), jpeg));
    await assertFails(uploadBytes(ref(bobStorage, `communityPosts/alice/post-1/${photoID}-bob.jpg`), bytes(1024), jpeg));
  });

  await t.test("only JPEG, not empty, up to 2MB", async () => {
    await assertSucceeds(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-2/max.jpg"), bytes(maxSize), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-2/too-big.jpg"), bytes(maxSize + 1), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-2/empty.jpg"), bytes(0), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-2/png.jpg"), bytes(1024), { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-2/no-type.jpg"), bytes(1024)));
  });

  await t.test("file names must look like the app's (photo-library IDs split into folders are rejected)", async () => {
    // 예전처럼 보관함 ID("…/L0/001")를 그대로 쓰면 폴더가 더 생겨서 어느 규칙에도 맞지 않아요.
    await assertFails(uploadBytes(ref(aliceStorage, `communityPosts/alice/post-3/${photoID}/L0/001.jpg`), bytes(1024), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-3/photo.png"), bytes(1024), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/post-3/사진.jpg"), bytes(1024), jpeg));
  });

  await t.test("owner can upload the same name again (retry), others cannot overwrite", async () => {
    await assertSucceeds(uploadBytes(ref(aliceStorage, postPhoto), bytes(200 * 1024), jpeg));
    await assertFails(uploadBytes(ref(bobStorage, postPhoto), bytes(200 * 1024), jpeg));
  });

  await t.test("place contribution path follows the same rules", async () => {
    await assertSucceeds(uploadBytes(ref(aliceStorage, placePhoto), bytes(300 * 1024), jpeg));
    await assertSucceeds(getBytes(ref(guestStorage, placePhoto)));
    await assertFails(uploadBytes(ref(bobStorage, placePhoto), bytes(1024), jpeg));
    await assertFails(uploadBytes(
      ref(aliceStorage, "communityPosts/alice/place-contributions/place-123/cover.jpg"),
      bytes(1024),
      jpeg,
    ));
    await assertFails(uploadBytes(
      ref(aliceStorage, "communityPosts/alice/place-contributions/place-123/place-big.jpg"),
      bytes(maxSize + 1),
      jpeg,
    ));
  });

  await t.test("only the owner can delete", async () => {
    await assertFails(deleteObject(ref(bobStorage, postPhoto)));
    await assertFails(deleteObject(ref(guestStorage, placePhoto)));
    await assertSucceeds(deleteObject(ref(aliceStorage, postPhoto)));
    await assertSucceeds(deleteObject(ref(aliceStorage, placePhoto)));
  });

  await t.test("every other path is closed", async () => {
    await assertFails(uploadBytes(ref(aliceStorage, "places/place-123/cover.jpg"), bytes(1024), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "communityPosts/alice/loose.jpg"), bytes(1024), jpeg));
    await assertFails(uploadBytes(ref(aliceStorage, "alice/photo.jpg"), bytes(1024), jpeg));
    await assertFails(getBytes(ref(guestStorage, "private/secret.jpg")));
  });
});
