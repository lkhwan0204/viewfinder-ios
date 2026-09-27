#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const SEED_URL = new URL("../Viewfinder/Data/photo_spots_seed.json", import.meta.url);
const SUBMITTED_URL = new URL("../RecommendationServer/submitted-spots.json", import.meta.url);
const EXPECTED_SEED_COUNT = 120;
const EXPECTED_APPROVED_SUBMITTED_COUNT = 1;
const EXPECTED_TOTAL_COUNT = EXPECTED_SEED_COUNT + EXPECTED_APPROVED_SUBMITTED_COUNT;
const SCHEMA_VERSION = 1;
const COLLECTION = "places";
const PROJECT_ENV = "VIEWFINDER_FIREBASE_PROJECT_ID";
let activeFirestore;

const CANONICAL_THEMES = new Map([
  ["cityarchitecture", "cityArchitecture"],
  ["landscape", "landscape"],
  ["retroalley", "retroAlley"],
  ["historytradition", "historyTradition"],
  ["viewpoint", "viewpoint"],
  ["cafeindoor", "cafeIndoor"],
]);

const LEGACY_THEMES = new Set([
  "indoor", "cafe", "flower", "healing", "water", "sunset", "night",
  "city", "history", "tradition", "heritage",
]);

const KNOWN_SEED_FIELDS = new Set([
  "id", "name", "region", "regions", "address", "description", "bestTime",
  "reason", "tags", "latitude", "longitude", "source", "theme", "imageURL",
  "category", "season", "weather", "mood", "crowdLevel", "imageName",
  "imageCredit", "imageLicense", "imageSourceURL", "openingHours", "feeInfo",
  "parkingInfo", "nearbyParkingInfo", "isHiddenSpot", "provider",
  "providerPlaceID",
]);
const KNOWN_SUBMITTED_FIELDS = new Set([
  "id", "name", "region", "latitude", "longitude", "category", "mapQuery",
  "photoDataBase64", "photoDataBase64s", "provider", "providerPlaceID", "imageURL",
  "photoURLs", "source", "status", "submittedAt", "submittedByID",
  "submittedByName", "summary", "tags",
]);

const REQUIRED_TEXT_FIELDS = ["id", "name", "address", "description", "theme"];
const STRING_ARRAY_FIELDS = ["regions", "tags", "season", "weather", "mood"];
const OPTIONAL_TEXT_FIELDS = [
  "region", "category", "crowdLevel", "imageURL", "imageName", "imageCredit",
  "imageLicense", "imageSourceURL", "openingHours", "feeInfo", "parkingInfo",
  "nearbyParkingInfo", "provider", "providerPlaceID",
];

function normalizeThemeText(value) {
  return value
    .replaceAll("#", "")
    .replaceAll(" ", "")
    .trim()
    .toLowerCase();
}

function containsAny(text, terms) {
  return terms.some((term) => text.includes(normalizeThemeText(term)));
}

// Mirrors SpotTheme.resolve for the canonical and legacy values present in the
// seed. Unknown theme tokens are rejected instead of silently defaulting.
function resolvePrimaryTheme(spot) {
  const legacy = normalizeThemeText(spot.theme);
  const directTheme = CANONICAL_THEMES.get(legacy);
  if (directTheme) return directTheme;
  if (!LEGACY_THEMES.has(legacy)) return null;

  const name = normalizeThemeText(spot.name ?? "");
  const category = normalizeThemeText(spot.category ?? "");
  const tags = (spot.tags ?? []).map(normalizeThemeText);
  const searchable = [spot.name ?? "", spot.description ?? "", spot.category ?? "", ...(spot.tags ?? [])]
    .map(normalizeThemeText)
    .join(" ");

  if (["북촌한옥마을", "익선동한옥거리", "수원화성화홍문", "집옥재", "대구불로동고분군", "청운문학도서관"]
    .some((needle) => name.includes(normalizeThemeText(needle)))) {
    return "historyTradition";
  }

  if (["창작촌", "카페거리", "카페골목", "문화의거리", "한옥마을", "한옥거리", "철길", "건널목", "골목", "신흥시장", "캠프마켓"]
    .some((needle) => name.includes(normalizeThemeText(needle)))) {
    return "retroAlley";
  }

  const cafeTagTerms = ["카페", "실내", "미술관", "박물관", "도서관", "전시", "라이브러리", "베이커리", "다방"]
    .map(normalizeThemeText);
  const isCafeOrIndoor = ["cafe", "카페", "실내", "indoor"].includes(category)
    || tags.some((tag) => cafeTagTerms.includes(tag));
  if (isCafeOrIndoor) return "cafeIndoor";

  const viewpointSignals = [
    "전망", "전망대", "스카이워크", "뷰포인트", "스카이라인", "능선", "조망",
    "내려다", "팔각정", "남산타워뷰", "서울시티뷰", "한강뷰", "호수뷰", "산뷰", "바다뷰",
  ];
  if (category === "viewpoint" || containsAny(searchable, viewpointSignals)) return "viewpoint";

  const naturalSignals = [
    "공원", "숲", "수목원", "식물원", "정원", "꽃밭", "호수", "한강", "강변", "바다",
    "해수욕장", "목장", "들판", "초원", "생태", "습지", "산책로",
  ];
  const isNaturalPlace = ["park", "trail", "water"].includes(category)
    || containsAny(searchable, naturalSignals);
  const architectureSignals = [
    "ddp", "건축물", "건축", "다리", "대교", "육교", "교량", "스카이돔", "성곽", "고궁",
    "정자", "철골", "콘크리트구조물", "구조물", "마천루", "빌딩",
  ];
  const isStrongArchitecturePlace = containsAny(name, architectureSignals)
    || (containsAny(searchable, architectureSignals) && !isNaturalPlace);
  if (isStrongArchitecturePlace) return "cityArchitecture";
  if (isNaturalPlace) return "landscape";

  const retroSignals = [
    "골목", "레트로", "빈티지", "오래된거리", "철도", "한옥", "시장", "서촌", "북촌",
    "을지로", "문래", "익선동", "해방촌", "행궁동",
  ];
  if (containsAny(searchable, retroSignals)) return "retroAlley";

  switch (legacy) {
    case "indoor":
    case "cafe": return "cafeIndoor";
    case "flower":
    case "healing":
    case "water":
    case "sunset": return "landscape";
    case "night":
    case "city": return "cityArchitecture";
    case "history":
    case "tradition":
    case "heritage": return "historyTradition";
    default: return null;
  }
}

function resolveHiddenSpot(spot) {
  if (typeof spot.isHiddenSpot === "boolean") return spot.isHiddenSpot;
  const searchable = [
    spot.crowdLevel ?? "", spot.description ?? "", spot.reason ?? "",
    ...(spot.tags ?? []), ...(spot.mood ?? []),
  ].join(" ");
  return spot.crowdLevel === "low"
    || searchable.includes("숨은")
    || searchable.includes("한적")
    || searchable.toLowerCase().includes("hidden");
}

function isFirestoreValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === "number") return Number.isFinite(value);
  if (["string", "boolean"].includes(typeof value)) return true;
  if (Array.isArray(value)) return value.every(isFirestoreValue);
  if (typeof value === "object") {
    return Object.values(value).every(isFirestoreValue);
  }
  return false;
}

function addError(errors, field, message) {
  errors.push(`${field}: ${message}`);
}

function validateSpot(spot) {
  const errors = [];
  if (!spot || typeof spot !== "object" || Array.isArray(spot)) {
    return ["document must be an object"];
  }

  for (const key of Object.keys(spot)) {
    if (!KNOWN_SEED_FIELDS.has(key)) addError(errors, key, "unmapped source field");
  }

  for (const field of REQUIRED_TEXT_FIELDS) {
    if (typeof spot[field] !== "string" || !spot[field].trim()) {
      addError(errors, field, "required non-empty string is missing");
    }
  }

  if (typeof spot.id === "string"
      && (!spot.id.trim() || spot.id.includes("/") || spot.id === "." || spot.id === "..")) {
    addError(errors, "id", "not a valid Firestore document ID");
  }

  for (const field of ["latitude", "longitude"]) {
    const value = spot[field];
    const min = field === "latitude" ? -90 : -180;
    const max = field === "latitude" ? 90 : 180;
    if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
      addError(errors, field, `must be a finite number in ${min}...${max}`);
    }
  }

  for (const field of STRING_ARRAY_FIELDS) {
    if (spot[field] === undefined || spot[field] === null) continue;
    if (!Array.isArray(spot[field]) || spot[field].some((value) => typeof value !== "string" || !value.trim())) {
      addError(errors, field, "must be an array of non-empty strings");
    }
  }

  for (const field of OPTIONAL_TEXT_FIELDS) {
    if (spot[field] !== undefined && spot[field] !== null && typeof spot[field] !== "string") {
      addError(errors, field, "must be a string when present");
    }
  }

  if (spot.isHiddenSpot !== undefined && typeof spot.isHiddenSpot !== "boolean") {
    addError(errors, "isHiddenSpot", "must be a boolean when present");
  }

  if (!["local", "user-submitted"].includes(spot.source)) {
    addError(errors, "source", "must be 'local' or 'user-submitted'");
  }
  if (typeof spot.theme === "string" && !resolvePrimaryTheme(spot)) {
    addError(errors, "theme", `unsupported theme token '${spot.theme}'`);
  }

  for (const field of ["imageURL", "imageSourceURL"]) {
    if (typeof spot[field] !== "string") continue;
    try {
      const url = new URL(spot[field]);
      if (!["http:", "https:"].includes(url.protocol)) addError(errors, field, "must be an HTTP(S) URL");
    } catch {
      addError(errors, field, "must be a valid URL");
    }
  }

  return errors;
}

function toPlaceDocument(spot) {
  const data = {
    name: spot.name,
    address: spot.address,
    summary: spot.description,
    tags: [...spot.tags],
    latitude: spot.latitude,
    longitude: spot.longitude,
    primaryTheme: resolvePrimaryTheme(spot),
    source: spot.source,
    schemaVersion: SCHEMA_VERSION,
  };

  for (const field of ["region", "regions", "bestTime", "reason", "category", "season", "weather", "mood"]) {
    if (spot[field] !== undefined && spot[field] !== null) {
      data[field] = Array.isArray(spot[field]) ? [...spot[field]] : spot[field];
    }
  }

  if (spot.crowdLevel) data.crowdLevelCode = spot.crowdLevel;
  data.isHiddenSpot = resolveHiddenSpot(spot);

  for (const field of [
    "imageURL", "imageName", "imageCredit", "imageLicense", "imageSourceURL",
    "openingHours", "feeInfo", "parkingInfo", "nearbyParkingInfo", "provider", "providerPlaceID",
  ]) {
    if (typeof spot[field] === "string" && spot[field].trim()) data[field] = spot[field];
  }

  return data;
}

function normalizeSubmittedSpot(spot) {
  if (!spot || typeof spot !== "object" || Array.isArray(spot)) {
    return { normalized: null, errors: ["submitted entry must be an object"] };
  }

  const errors = [];
  for (const key of Object.keys(spot)) {
    if (!KNOWN_SUBMITTED_FIELDS.has(key)) errors.push(`${key}: unmapped submitted-place field`);
  }
  if (spot.status !== "approved") errors.push("status: only approved submissions can migrate");
  if (spot.source !== "user-submitted") errors.push("source: expected 'user-submitted'");

  const normalized = {
    id: spot.id,
    name: spot.name,
    address: spot.region,
    description: spot.summary,
    tags: spot.tags,
    latitude: spot.latitude,
    longitude: spot.longitude,
    source: "user-submitted",
    theme: spot.category,
    category: spot.category,
  };

  // Preserve only explicit, stable public fields. Runtime server photo URLs
  // are host-derived; base64 photo payloads and submitter identity are never
  // copied into the public places document.
  for (const field of ["provider", "providerPlaceID", "imageURL"]) {
    if (typeof spot[field] === "string" && spot[field].trim()) normalized[field] = spot[field];
  }

  return { normalized, errors };
}

function duplicateIDs(spots) {
  const seen = new Set();
  const duplicates = new Set();
  for (const spot of spots) {
    if (typeof spot?.id !== "string") continue;
    if (seen.has(spot.id)) duplicates.add(spot.id);
    seen.add(spot.id);
  }
  return [...duplicates];
}

function normalizeIdentityText(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, "");
}

function identityTextMatches(lhs, rhs) {
  const left = normalizeIdentityText(lhs);
  const right = normalizeIdentityText(rhs);
  return Boolean(left && right && (left === right || left.includes(right) || right.includes(left)));
}

function identityMatches(lhs, rhs) {
  if (!lhs || !rhs) return false;
  const lhsProvider = normalizeIdentityText(lhs.provider);
  const rhsProvider = normalizeIdentityText(rhs.provider);
  const lhsProviderID = normalizeIdentityText(lhs.providerPlaceID);
  const rhsProviderID = normalizeIdentityText(rhs.providerPlaceID);
  if (lhsProvider && rhsProvider && lhsProvider === rhsProvider
      && lhsProviderID && lhsProviderID === rhsProviderID) return true;
  const lhsID = normalizeIdentityText(lhs.id);
  const rhsID = normalizeIdentityText(rhs.id);
  if (lhsID && rhsID && lhsID === rhsID) return true;

  const nameMatches = identityTextMatches(lhs.name, rhs.name);
  const addressMatches = identityTextMatches(lhs.address, rhs.address);
  const lhsMapQuery = lhs.mapQuery || `${lhs.name ?? ""} ${lhs.address ?? ""}`;
  const rhsMapQuery = rhs.mapQuery || `${rhs.name ?? ""} ${rhs.address ?? ""}`;
  const mapQueryMatches = identityTextMatches(lhsMapQuery, rhsMapQuery);
  if (nameMatches && (addressMatches || mapQueryMatches)) return true;

  const validCoordinate = (spot) => typeof spot.latitude === "number"
    && typeof spot.longitude === "number"
    && spot.latitude >= -90 && spot.latitude <= 90
    && spot.longitude >= -180 && spot.longitude <= 180
    && (Math.abs(spot.latitude) > 0.000001 || Math.abs(spot.longitude) > 0.000001);
  if (!validCoordinate(lhs) || !validCoordinate(rhs)) return false;

  const radians = (value) => value * Math.PI / 180;
  const latitudeDelta = radians(rhs.latitude - lhs.latitude);
  const longitudeDelta = radians(rhs.longitude - lhs.longitude);
  const lhsLatitude = radians(lhs.latitude);
  const rhsLatitude = radians(rhs.latitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(lhsLatitude) * Math.cos(rhsLatitude) * Math.sin(longitudeDelta / 2) ** 2;
  const distanceMeters = 6_371_000 * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
  return distanceMeters <= 60 && (nameMatches || addressMatches);
}

function identityDuplicatePairs(spots) {
  const pairs = [];
  for (let left = 0; left < spots.length; left += 1) {
    for (let right = left + 1; right < spots.length; right += 1) {
      // This check answers whether newly submitted records collide with the
      // curated seed; it must not reinterpret legacy seed-to-seed grouping.
      if (spots[left]?.source === spots[right]?.source) continue;
      if (identityMatches(spots[left], spots[right])) {
        pairs.push([spots[left].id, spots[right].id]);
      }
    }
  }
  return pairs;
}

function validateFirestoreValue(value, prefix, errors) {
  if (!isFirestoreValue(value)) errors.push(`${prefix}: contains an unsupported Firestore value`);
}

function compareExpectedFields(actual, expected) {
  const keys = Object.keys(expected);
  return keys.filter((key) => JSON.stringify(actual?.[key]) !== JSON.stringify(expected[key]));
}

function isAlreadyExistsError(error) {
  return error?.code === 6
    || error?.code === "already-exists"
    || error?.code === "ALREADY_EXISTS"
    || /already exists|document already exists/i.test(error?.message ?? "");
}

async function initializeFirestore(projectId) {
  console.log(`[Migration] Firebase project: ${projectId}`);
  const [{ applicationDefault, initializeApp }, { getFirestore }] = await Promise.all([
    import("firebase-admin/app"),
    import("firebase-admin/firestore"),
  ]);
  const credential = applicationDefault();
  // Force ADC validation here so missing credentials are reported as a normal
  // preflight error instead of surfacing later as an unhandled gRPC rejection.
  await credential.getAccessToken();
  console.log("[Migration] ADC authenticated");
  const app = initializeApp({ credential, projectId }, `places-migration-${process.pid}`);
  activeFirestore = getFirestore(app);
  return activeFirestore;
}

async function closeActiveFirestore() {
  if (!activeFirestore) return;
  const db = activeFirestore;
  activeFirestore = undefined;
  await db.terminate();
}

async function readPlacesPreflight(db, records) {
  const snapshot = await db.collection(COLLECTION).get();
  const existing = new Map(snapshot.docs.map((document) => [document.id, document]));
  const existingCandidateIDs = records
    .filter(({ id }) => existing.has(id))
    .map(({ id }) => id);

  return {
    existing,
    remoteCount: snapshot.size,
    existingCandidateIDs,
  };
}

async function countPlaceDocuments(db) {
  const snapshot = await db.collection(COLLECTION).count().get();
  return snapshot.data().count;
}

async function readExistingDocuments(db, records) {
  const refs = records.map(({ id }) => db.collection(COLLECTION).doc(id));
  const chunks = [];
  for (let index = 0; index < refs.length; index += 100) {
    chunks.push(refs.slice(index, index + 100));
  }
  const snapshots = (await Promise.all(chunks.map((chunk) => db.getAll(...chunk)))).flat();
  return new Map(snapshots.map((snapshot) => [snapshot.id, snapshot]));
}

async function createWithoutOverwrite(db, records) {
  const outcome = { created: [], skipped: [], failed: [] };
  let cursor = 0;
  const workerCount = Math.min(8, records.length);

  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (cursor < records.length) {
      const record = records[cursor++];
      try {
        await db.collection(COLLECTION).doc(record.id).create(record.data);
        outcome.created.push(record.id);
      } catch (error) {
        if (isAlreadyExistsError(error)) outcome.skipped.push(record.id);
        else outcome.failed.push({ id: record.id, message: error.message });
      }
    }
  }));

  return outcome;
}

function printValidationReport(spots, records, errorsByIndex, duplicateIDs, globalErrors, submittedPhotoCount) {
  const totalErrors = errorsByIndex.reduce((sum, errors) => sum + errors.length, 0);
  const validCount = errorsByIndex.filter((errors) => errors.length === 0).length;
  const missingRequired = errorsByIndex
    .flat()
    .filter((error) => error.includes("required non-empty string is missing")).length;
  const coordinateErrors = errorsByIndex.filter((errors) => errors.some((error) => /^(latitude|longitude):/.test(error))).length;
  const themeErrors = errorsByIndex.filter((errors) => errors.some((error) => /^theme:/.test(error))).length;
  const tagErrors = errorsByIndex.filter((errors) => errors.some((error) => /^tags:/.test(error))).length;
  const firestoreValueErrors = errorsByIndex.filter((errors) => errors.some((error) => error.includes("unsupported Firestore value"))).length;

  console.log(`Mode: ${process.argv.includes("--commit") ? "COMMIT" : "DRY RUN (no Firestore writes)"}`);
  console.log(`Seed source: ${path.resolve(fileURLToPath(SEED_URL))}`);
  console.log(`Approved submitted-place source: ${path.resolve(fileURLToPath(SUBMITTED_URL))}`);
  console.log(`Migration candidates: ${spots.length} (expected ${EXPECTED_TOTAL_COUNT}: ${EXPECTED_SEED_COUNT} seed + ${EXPECTED_APPROVED_SUBMITTED_COUNT} approved submission)`);
  console.log(`Approved submission photo payloads excluded from Firestore: ${submittedPhotoCount}`);
  console.log(`Valid places: ${validCount}`);
  console.log(`Places with validation errors: ${errorsByIndex.filter((errors) => errors.length > 0).length + globalErrors.length} (${totalErrors + globalErrors.length} errors)`);
  console.log(`Missing required fields: ${missingRequired}`);
  console.log(`Duplicate IDs: ${duplicateIDs.length}${duplicateIDs.length ? ` — ${duplicateIDs.join(", ")}` : ""}`);
  console.log(`Coordinate errors: ${coordinateErrors}`);
  console.log(`Theme errors: ${themeErrors}`);
  console.log(`Tags errors: ${tagErrors}`);
  console.log(`Firestore-unsafe values: ${firestoreValueErrors}`);
  const themeCounts = records.reduce((counts, record) => {
    const theme = record.data.primaryTheme;
    counts[theme] = (counts[theme] ?? 0) + 1;
    return counts;
  }, {});
  console.log(`Canonical primaryTheme distribution: ${JSON.stringify(themeCounts)}`);

  for (let index = 0; index < errorsByIndex.length; index += 1) {
    if (errorsByIndex[index].length) {
      console.log(`ERROR ${spots[index]?.id ?? `(record ${index + 1})`}: ${errorsByIndex[index].join("; ")}`);
    }
  }
  for (const error of globalErrors) console.log(`ERROR: ${error}`);

  console.log(`Expected Firestore document IDs (${records.length}):`);
  for (const record of records) console.log(`  places/${record.id}`);
}

async function main() {
  const args = process.argv.slice(2);
  const unknownArgs = args.filter((arg) => arg !== "--commit");
  if (unknownArgs.length) {
    console.error(`Unknown argument(s): ${unknownArgs.join(" ")}`);
    console.error("Usage: npm run migrate:places [-- --commit]");
    process.exitCode = 2;
    return;
  }

  const commit = args.includes("--commit");
  const seedSpots = JSON.parse(await readFile(SEED_URL, "utf8"));
  const submittedRoot = JSON.parse(await readFile(SUBMITTED_URL, "utf8"));
  if (!Array.isArray(seedSpots) || !Array.isArray(submittedRoot?.spots)) {
    console.error("Migration stopped: expected a seed array and a submitted-spots object with a spots array.");
    process.exitCode = 1;
    return;
  }

  const approvedSubmissions = submittedRoot.spots.filter((spot) => spot?.status === "approved");
  const normalizedSubmissions = approvedSubmissions.map(normalizeSubmittedSpot);
  const spots = [...seedSpots, ...normalizedSubmissions.map(({ normalized }) => normalized)];
  const errorsByIndex = spots.map(validateSpot);
  normalizedSubmissions.forEach(({ errors }, index) => {
    errorsByIndex[seedSpots.length + index].push(...errors);
  });
  const duplicates = duplicateIDs(spots);
  const identityDuplicates = identityDuplicatePairs(spots);
  const globalErrors = [];
  if (seedSpots.length !== EXPECTED_SEED_COUNT) {
    globalErrors.push(`seed count must remain ${EXPECTED_SEED_COUNT} until the migration scope is reviewed`);
  }
  if (approvedSubmissions.length !== EXPECTED_APPROVED_SUBMITTED_COUNT) {
    globalErrors.push(`approved submitted-place count must remain ${EXPECTED_APPROVED_SUBMITTED_COUNT} until the migration scope is reviewed`);
  }

  const records = [];
  spots.forEach((spot, index) => {
    if (typeof spot?.id !== "string" || spot.id.includes("/")) return;
    try {
      const record = { id: spot.id, data: toPlaceDocument(spot) };
      validateFirestoreValue(record.data, `places/${record.id}`, errorsByIndex[index]);
      records.push(record);
    } catch (error) {
      errorsByIndex[index].push(`mapping: ${error.message}`);
    }
  });

  const submittedPhotoCount = approvedSubmissions.filter((spot) =>
    (typeof spot?.photoDataBase64 === "string" && spot.photoDataBase64.length > 0)
      || (Array.isArray(spot?.photoDataBase64s) && spot.photoDataBase64s.some((photo) => typeof photo === "string" && photo.length > 0))
  ).length;
  printValidationReport(spots, records, errorsByIndex, duplicates, globalErrors, submittedPhotoCount);
  console.log(`User-submission ↔ seed identity duplicate candidates (provider/ID, name+address/query, or <=60m plus matching name/address): ${identityDuplicates.length}`);
  for (const [leftID, rightID] of identityDuplicates) console.log(`  DUPLICATE CANDIDATE ${leftID} ↔ ${rightID}`);

  if (duplicates.length || identityDuplicates.length || globalErrors.length || errorsByIndex.some((errors) => errors.length > 0)) {
    console.error("Migration stopped: fix or review validation errors before any Firestore operation.");
    process.exitCode = 1;
    return;
  }

  const projectId = process.env[PROJECT_ENV];
  if (!projectId) {
    if (commit) {
      console.error(`Migration stopped: set ${PROJECT_ENV} before using --commit.`);
      process.exitCode = 1;
      return;
    }
    console.log(`Firestore conflict check: SKIPPED (set ${PROJECT_ENV} and configure Google ADC to perform a remote read-only check).`);
    console.log("Dry run complete. No Firestore data was written.");
    return;
  }

  let db;
  try {
    db = await initializeFirestore(projectId);
  } catch (error) {
    console.error(`Could not initialize Firebase Admin SDK: ${error.message}`);
    if (error?.stack) console.error(error.stack);
    process.exitCode = 1;
    if (!commit) console.log("Remote dry-run incomplete: no Firestore reads completed and no writes were attempted.");
    return;
  }

  let existing;
  let remoteCount;
  let existingIDs;
  try {
    ({ existing, remoteCount, existingCandidateIDs: existingIDs } = await readPlacesPreflight(db, records));
    console.log("[Migration] remote places read succeeded");
    console.log(`[Migration] remote places count: ${remoteCount}`);
  } catch (error) {
    console.error(`Firestore read-only preflight failed: ${error.message}`);
    if (error?.stack) console.error(error.stack);
    process.exitCode = 1;
    if (!commit) console.log("Remote dry-run incomplete: remote counts/conflicts are unknown and no writes were attempted.");
    await closeActiveFirestore();
    return;
  }

  console.log(`Remote places collection count: ${remoteCount}`);
  console.log(`Candidate ID conflicts: ${existingIDs.length}`);
  for (const id of existingIDs) console.log(`  SKIP / CONFLICT places/${id} (existing document will not be overwritten)`);

  if (!commit) {
    console.log(`Would skip: ${existingIDs.length}`);
    console.log(`Would create: ${records.length - existingIDs.length}`);
    console.log("Dry run complete. No Firestore data was written.");
    await closeActiveFirestore();
    return;
  }

  const missingRecords = records.filter((record) => !existing.get(record.id)?.exists);
  const outcome = await createWithoutOverwrite(db, missingRecords);
  console.log(`Create requests: ${missingRecords.length}`);
  console.log(`Created: ${outcome.created.length}`);
  console.log(`Skipped (pre-existing or created concurrently): ${existingIDs.length + outcome.skipped.length}`);
  console.log(`Failed: ${outcome.failed.length}`);
  for (const failure of outcome.failed) console.error(`FAILED places/${failure.id}: ${failure.message}`);

  const [postWriteCount, postWriteSnapshots] = await Promise.all([
    countPlaceDocuments(db),
    readExistingDocuments(db, records),
  ]);
  const mismatches = [];
  for (const record of records) {
    const snapshot = postWriteSnapshots.get(record.id);
    if (!snapshot?.exists) {
      mismatches.push({ id: record.id, fields: ["document missing"] });
      continue;
    }
    const fields = compareExpectedFields(snapshot.data(), record.data);
    if (fields.length) mismatches.push({ id: record.id, fields });
  }

  console.log(`Post-migration Firestore places document count: ${postWriteCount}`);
  console.log(`Local migration candidate count: ${records.length}`);
  console.log(`Firestore collection count matches candidate count: ${postWriteCount === records.length ? "yes" : "no (other/existing documents may be present)"}`);
  console.log(`Migrated document field checks: ${records.length - mismatches.length}/${records.length} (document ID and every migrated field)`);
  console.log(`Mismatches/missing candidate documents: ${mismatches.length}`);
  for (const mismatch of mismatches) console.error(`VERIFY FAILED places/${mismatch.id}: ${mismatch.fields.join(", ")}`);
  if (outcome.failed.length || mismatches.length) process.exitCode = 1;
  await closeActiveFirestore();
}

main().catch(async (error) => {
  await closeActiveFirestore().catch(() => {});
  console.error(`Migration aborted: ${error.message}`);
  process.exitCode = 1;
});
