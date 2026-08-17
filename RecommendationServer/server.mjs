import { createServer } from "node:http";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";
const serverDirectory = dirname(fileURLToPath(import.meta.url));
const submittedSpotsPath = join(serverDirectory, "submitted-spots.json");

loadLocalEnvironment();

const kakaoRestApiKey = process.env.KAKAO_REST_API_KEY ?? process.env.KAKAO_API_KEY;
const naverClientId = process.env.NAVER_CLIENT_ID;
const naverClientSecret = process.env.NAVER_CLIENT_SECRET;
const adminReviewToken = process.env.VIEWFINDER_ADMIN_REVIEW_TOKEN?.trim();
const reviewableSubmissionStatuses = new Set(["pending_review", "approved", "rejected"]);

class ServiceConfigurationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ServiceConfigurationError";
    this.code = code;
  }
}
const franchiseCafeKeywords = [
  "런던베이글뮤지엄",
  "런던베이글",
  "스타벅스",
  "투썸",
  "투썸플레이스",
  "이디야",
  "메가커피",
  "컴포즈",
  "컴포즈커피",
  "블루보틀",
  "노티드",
  "랜디스도넛",
  "아우어베이커리",
  "파리바게뜨",
  "뚜레쥬르",
];

const overexposedPhotoSpotKeywords = [
  "남산타워",
  "N서울타워",
  "경복궁",
  "롯데월드타워",
  "명동",
  "두물머리",
  "일산호수공원",
  "고척스카이돔",
  "고척스카이돔 외부",
  "오류동역 주변 골목",
];

function loadLocalEnvironment() {
  const envPath = join(serverDirectory, ".env.local");

  try {
    const envFile = readFileSync(envPath, "utf8");

    for (const line of envFile.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;

      const separatorIndex = trimmed.indexOf("=");
      if (separatorIndex === -1) continue;

      const key = trimmed.slice(0, separatorIndex).trim();
      const value = trimmed.slice(separatorIndex + 1).trim().replace(/^["']|["']$/g, "");
      if (key && process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  } catch {
    // The file is optional. Use shell environment variables if it is missing.
  }
}

function sendJSON(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(payload));
}

function readJSON(request) {
  return new Promise((resolve, reject) => {
    let rawBody = "";

    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      rawBody += chunk;
    });
    request.on("end", () => {
      try {
        resolve(rawBody ? JSON.parse(rawBody) : {});
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

async function readResponsePayload(response) {
  const rawText = await response.text();

  try {
    return rawText ? JSON.parse(rawText) : {};
  } catch {
    return { rawText };
  }
}

function payloadErrorMessage(payload, fallback) {
  return payload.error?.message ?? payload.error?.status ?? payload.rawText ?? fallback;
}

function loadSubmittedSpots() {
  try {
    const file = JSON.parse(readFileSync(submittedSpotsPath, "utf8"));
    return Array.isArray(file.spots) ? file.spots : [];
  } catch {
    return [];
  }
}

function saveSubmittedSpots(spots) {
  writeFileSync(
    submittedSpotsPath,
    JSON.stringify(
      {
        updatedAt: new Date().toISOString(),
        spots,
      },
      null,
      2,
    ),
  );
}

function normalizedSubmittedSpot(payload) {
  const name = String(payload?.name ?? "").trim();
  const latitude = Number(payload?.latitude);
  const longitude = Number(payload?.longitude);

  if (!name) {
    throw new Error("name is required");
  }

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error("valid coordinates are required");
  }

  const region = String(payload?.region ?? "").trim();
  const mapQuery = String(payload?.mapQuery ?? `${name} ${region}`).trim();
  const tags = Array.isArray(payload?.tags)
    ? uniqueValues(payload.tags.map((tag) => String(tag ?? "").replace(/^#+/, "").trim()).filter(Boolean))
    : [];
  const photoDataBase64 =
    typeof payload?.photoDataBase64 === "string" && payload.photoDataBase64.length < 8_000_000
      ? payload.photoDataBase64
      : undefined;
  const submittedByID = String(payload?.submittedByID ?? "").trim().slice(0, 128) || "anonymous";
  const submittedByName = String(payload?.submittedByName ?? "").trim().slice(0, 64) || "익명";

  return {
    id: String(payload?.id ?? verifiedSpotID("submitted", name, latitude, longitude)),
    name,
    region,
    summary: String(payload?.summary ?? "").trim(),
    tags,
    mapQuery,
    latitude,
    longitude,
    category: String(payload?.category ?? "spot").trim() || "spot",
    imageURL: typeof payload?.imageURL === "string" ? payload.imageURL : undefined,
    photoDataBase64,
    submittedByID,
    submittedByName,
    submittedAt: String(payload?.submittedAt ?? new Date().toISOString()),
    status: "pending_review",
    source: "user-submitted",
  };
}

function createSubmittedSpot(payload) {
  const spot = normalizedSubmittedSpot(payload);
  const spots = loadSubmittedSpots();
  const normalizedKey = `${spot.name}-${spot.region}-${spot.mapQuery}`.replace(/\s+/g, "").toLowerCase();
  const existingIndex = spots.findIndex((existing) => {
    const existingKey = `${existing?.name ?? ""}-${existing?.region ?? ""}-${existing?.mapQuery ?? ""}`
      .replace(/\s+/g, "")
      .toLowerCase();
    return existing?.id === spot.id || existingKey === normalizedKey;
  });

  if (existingIndex >= 0) {
    const existingSpot = spots[existingIndex];

    if (existingSpot?.status === "approved") {
      return {
        ok: true,
        spot: existingSpot,
        count: spots.length,
        alreadyApproved: true,
      };
    }

    spots[existingIndex] = {
      ...existingSpot,
      ...spot,
      id: existingSpot.id,
      submittedAt: existingSpot.submittedAt ?? spot.submittedAt,
      resubmittedAt: new Date().toISOString(),
      status: "pending_review",
      reviewedAt: undefined,
      reviewNote: undefined,
      updatedAt: new Date().toISOString(),
    };
  } else {
    spots.unshift(spot);
  }

  saveSubmittedSpots(spots);
  return { ok: true, spot, count: spots.length };
}

function hasAdminReviewAccess(request) {
  if (!adminReviewToken) {
    return false;
  }

  return request.headers["x-viewfinder-admin-token"] === adminReviewToken;
}

function reviewSubmittedSpot(id, payload) {
  const status = String(payload?.status ?? "").trim();
  if (!reviewableSubmissionStatuses.has(status) || status === "pending_review") {
    throw new Error("status must be approved or rejected");
  }

  const spots = loadSubmittedSpots();
  const index = spots.findIndex((spot) => spot?.id === id);
  if (index < 0) {
    throw new Error("Submitted spot not found");
  }

  spots[index] = {
    ...spots[index],
    status,
    reviewedAt: new Date().toISOString(),
    reviewNote: String(payload?.reviewNote ?? "").trim().slice(0, 400) || undefined,
  };
  saveSubmittedSpots(spots);
  return spots[index];
}

function submittedSpotPhotoContentType(buffer) {
  if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return "image/jpeg";
  }

  if (
    buffer.length >= 8
    && buffer[0] === 0x89
    && buffer[1] === 0x50
    && buffer[2] === 0x4e
    && buffer[3] === 0x47
  ) {
    return "image/png";
  }

  if (buffer.length >= 12 && buffer.subarray(0, 4).toString("ascii") === "RIFF"
      && buffer.subarray(8, 12).toString("ascii") === "WEBP") {
    return "image/webp";
  }

  if (buffer.length >= 12 && buffer.subarray(4, 8).toString("ascii") === "ftyp") {
    const brand = buffer.subarray(8, 12).toString("ascii");
    if (brand === "avif" || brand === "avis") {
      return "image/avif";
    }
    return "image/heic";
  }

  return "application/octet-stream";
}

function requestBaseURL(request) {
  const forwardedProtocol = String(request.headers["x-forwarded-proto"] ?? "")
    .split(",")[0]
    .trim();
  const forwardedHost = String(request.headers["x-forwarded-host"] ?? "")
    .split(",")[0]
    .trim();
  const protocol = forwardedProtocol || (request.socket.encrypted ? "https" : "http");
  const hostName = forwardedHost || request.headers.host;
  return hostName ? `${protocol}://${hostName}` : null;
}

function submittedSpotResponse(spot, request) {
  const {
    photoDataBase64,
    submittedByID,
    submittedByName,
    reviewNote,
    ...publicSpot
  } = spot;
  const baseURL = requestBaseURL(request);

  if (!publicSpot.imageURL && photoDataBase64 && baseURL) {
    publicSpot.imageURL = `${baseURL}/submitted-spots/${encodeURIComponent(spot.id)}/photo`;
  }

  return publicSpot;
}

function adminSubmittedSpotResponse(spot, request) {
  const response = submittedSpotResponse(spot, request);
  const baseURL = requestBaseURL(request);

  if (spot.photoDataBase64 && baseURL) {
    response.reviewPhotoURL = `${baseURL}/admin/submitted-spots/${encodeURIComponent(spot.id)}/photo`;
  }

  return response;
}

function coordinateFromLocation(location) {
  const latitude = Number(location?.latitude);
  const longitude = Number(location?.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return { latitude, longitude };
}

function normalizedSearchQuery(context) {
  return String(context?.query ?? context?.region ?? context?.searchText ?? "").trim();
}

function slug(value) {
  const normalized = String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^0-9a-z가-힣]+/gu, "-")
    .replace(/^-+|-+$/g, "");

  return normalized || "spot";
}

function uniqueValues(values) {
  return [...new Set(values.map((value) => String(value ?? "").trim()).filter(Boolean))];
}

function normalizedKeyword(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/^#+/, "")
    .replace(/\s+/g, "");
}

function isBlacklistedCafeCandidate(item) {
  if (item?.isFranchise === true) return true;

  const searchable = [
    item?.name,
    item?.description,
    item?.reason,
    ...(Array.isArray(item?.tags) ? item.tags : []),
  ]
    .map(normalizedKeyword)
    .join(" ");

  return franchiseCafeKeywords.map(normalizedKeyword).some((keyword) => searchable.includes(keyword));
}

function isOverexposedPhotoSpotCandidate(item) {
  const searchable = [
    item?.name,
    item?.description,
    item?.summary,
    item?.reason,
    item?.photoPoint,
    item?.region,
    item?.category,
    item?.crowdLevel,
    ...(Array.isArray(item?.tags) ? item.tags : []),
    ...(Array.isArray(item?.hashtags) ? item.hashtags : []),
    ...(Array.isArray(item?.mood) ? item.mood : []),
  ]
    .map(normalizedKeyword)
    .join(" ");

  return overexposedPhotoSpotKeywords.map(normalizedKeyword).some((keyword) => searchable.includes(keyword));
}

function normalizedPhotoSpotRecommendations(payload, region) {
  const rawRecommendations = Array.isArray(payload?.recommendations) ? payload.recommendations : [];

  return rawRecommendations
    .filter((item) => !isBlacklistedCafeCandidate(item) && !isOverexposedPhotoSpotCandidate(item))
    .map((item, index) => {
      const name = String(item?.name ?? "").trim();
      if (!name) return null;

      const tags = uniqueValues(Array.isArray(item?.tags) ? item.tags : [])
        .map((tag) => tag.replace(/^#+/, ""))
        .slice(0, 5);

      return {
        id: slug(item?.id ?? `${region}-${name}-${index + 1}`),
        name,
        description: String(item?.description ?? "사진 찍기 좋은 출사지입니다.").trim(),
        bestTime: String(item?.bestTime ?? "빛이 좋은 시간대 확인 추천").trim(),
        reason: String(item?.reason ?? item?.description ?? "지역과 분위기를 고려한 추천입니다.").trim(),
        photoPoint: String(item?.photoPoint ?? item?.description ?? "구도와 빛을 살려 촬영하기 좋아요.").trim(),
        tags: tags.length ? tags : ["출사지", "AI추천"],
        isFranchise: item?.isFranchise === true,
      };
    })
    .filter(Boolean)
    .slice(0, 8);
}

function strippedHTML(value) {
  return String(value ?? "").replace(/<[^>]*>/g, "").trim();
}

function verificationQueries(recommendation, region) {
  const placeName = String(recommendation?.name ?? "").trim();
  const searchRegion = String(region ?? "").trim();

  if (!placeName) return [];

  return uniqueValues([searchRegion ? `${searchRegion} ${placeName}` : "", placeName]);
}

function verifiedSpotID(source, name, latitude, longitude) {
  const latitudePart = Number.isFinite(latitude) ? Math.round(latitude * 100000) : 0;
  const longitudePart = Number.isFinite(longitude) ? Math.round(longitude * 100000) : 0;
  return slug(`${source}-${name}-${latitudePart}-${longitudePart}`);
}

function makeVerifiedSpot(recommendation, place, source) {
  const latitude = Number(place.latitude);
  const longitude = Number(place.longitude);

  if (!place.name || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return {
    id: verifiedSpotID(source, place.name, latitude, longitude),
    name: place.name,
    description: recommendation.description,
    bestTime: recommendation.bestTime,
    reason: recommendation.reason,
    tags: recommendation.tags,
    address: place.address,
    latitude,
    longitude,
    source,
  };
}

async function verifyWithKakao(recommendation, context) {
  if (!kakaoRestApiKey) return null;

  for (const query of verificationQueries(recommendation, context.region)) {
    const url = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
    url.searchParams.set("query", query);
    url.searchParams.set("size", "5");
    url.searchParams.set("sort", "accuracy");

    const kakaoResponse = await fetch(url, {
      headers: {
        authorization: `KakaoAK ${kakaoRestApiKey}`,
      },
    });
    const payload = await readResponsePayload(kakaoResponse);

    if (!kakaoResponse.ok) {
      throw new Error(`Kakao Local API request failed: ${payloadErrorMessage(payload, "unknown error")}`);
    }

    const document = Array.isArray(payload.documents) ? payload.documents[0] : null;
    if (!document) continue;

    return makeVerifiedSpot(
      recommendation,
      {
        name: String(document.place_name ?? recommendation.name).trim(),
        address: String(document.road_address_name || document.address_name || "주소 확인 필요").trim(),
        latitude: document.y,
        longitude: document.x,
      },
      "kakao",
    );
  }

  return null;
}

async function verifyWithNaver(recommendation, context) {
  if (!naverClientId || !naverClientSecret) return null;

  for (const query of verificationQueries(recommendation, context.region)) {
    const url = new URL("https://openapi.naver.com/v1/search/local.json");
    url.searchParams.set("query", query);
    url.searchParams.set("display", "5");
    url.searchParams.set("start", "1");
    url.searchParams.set("sort", "random");

    const naverResponse = await fetch(url, {
      headers: {
        "X-Naver-Client-Id": naverClientId,
        "X-Naver-Client-Secret": naverClientSecret,
      },
    });
    const payload = await readResponsePayload(naverResponse);

    if (!naverResponse.ok) {
      throw new Error(`Naver Local API request failed: ${payloadErrorMessage(payload, "unknown error")}`);
    }

    const item = Array.isArray(payload.items) ? payload.items[0] : null;
    if (!item) continue;

    const latitude = Number(item.mapy) / 10000000;
    const longitude = Number(item.mapx) / 10000000;

    return makeVerifiedSpot(
      recommendation,
      {
        name: strippedHTML(item.title) || recommendation.name,
        address: strippedHTML(item.roadAddress || item.address || "주소 확인 필요"),
        latitude,
        longitude,
      },
      "naver",
    );
  }

  return null;
}

function makePlaceSearchSpot(place, source, query) {
  const latitude = Number(place.latitude);
  const longitude = Number(place.longitude);
  const name = String(place.name ?? "").trim();
  const address = String(place.address ?? "주소 확인 필요").trim();

  if (!name || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  const tags = uniqueValues(
    String(place.category ?? "")
      .split(/[>,/]/)
      .map((value) => value.trim())
      .filter(Boolean),
  ).slice(0, 4);

  return {
    id: verifiedSpotID(source, name, latitude, longitude),
    name,
    description: `${address}에 있는 실제 장소 검색 결과`,
    bestTime: "방문 목적과 현장 상황에 맞춰 확인",
    reason: `"${query}" 장소 검색 결과`,
    tags: tags.length > 0 ? tags : ["장소"],
    address,
    latitude,
    longitude,
    source,
    imageURL: null,
  };
}

async function searchPlacesWithKakao(query, userLocation) {
  if (!kakaoRestApiKey) return [];

  const url = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
  url.searchParams.set("query", query);
  url.searchParams.set("size", "12");

  if (userLocation) {
    url.searchParams.set("x", String(userLocation.longitude));
    url.searchParams.set("y", String(userLocation.latitude));
    url.searchParams.set("sort", "distance");
  } else {
    url.searchParams.set("sort", "accuracy");
  }

  const kakaoResponse = await fetch(url, {
    headers: {
      authorization: `KakaoAK ${kakaoRestApiKey}`,
    },
  });
  const payload = await readResponsePayload(kakaoResponse);

  if (!kakaoResponse.ok) {
    throw new Error(`Kakao Local API request failed: ${payloadErrorMessage(payload, "unknown error")}`);
  }

  return (Array.isArray(payload.documents) ? payload.documents : [])
    .map((document) =>
      makePlaceSearchSpot(
        {
          name: document.place_name,
          address: document.road_address_name || document.address_name,
          latitude: document.y,
          longitude: document.x,
          category: document.category_name,
        },
        "kakao",
        query,
      ),
    )
    .filter(Boolean);
}

async function searchPlacesWithNaver(query) {
  if (!naverClientId || !naverClientSecret) return [];

  const url = new URL("https://openapi.naver.com/v1/search/local.json");
  url.searchParams.set("query", query);
  url.searchParams.set("display", "5");
  url.searchParams.set("start", "1");
  url.searchParams.set("sort", "random");

  const naverResponse = await fetch(url, {
    headers: {
      "X-Naver-Client-Id": naverClientId,
      "X-Naver-Client-Secret": naverClientSecret,
    },
  });
  const payload = await readResponsePayload(naverResponse);

  if (!naverResponse.ok) {
    throw new Error(`Naver Local API request failed: ${payloadErrorMessage(payload, "unknown error")}`);
  }

  return (Array.isArray(payload.items) ? payload.items : [])
    .map((item) =>
      makePlaceSearchSpot(
        {
          name: strippedHTML(item.title),
          address: strippedHTML(item.roadAddress || item.address),
          latitude: Number(item.mapy) / 10000000,
          longitude: Number(item.mapx) / 10000000,
          category: strippedHTML(item.category),
        },
        "naver",
        query,
      ),
    )
    .filter(Boolean);
}

async function createPlaceSearchResults(context) {
  if (!naverClientId || !naverClientSecret) {
    throw new ServiceConfigurationError(
      "naver_place_search_unconfigured",
      "네이버 실제 장소검색 설정이 아직 완료되지 않았어요.",
    );
  }

  const query = String(context.query ?? "").trim();
  if (!query) return { spots: [] };

  const results = await searchPlacesWithNaver(query);

  const seen = new Set();
  const spots = results.filter((spot) => {
    const key = `${spot.name}-${spot.address}`.replace(/\s+/g, "").toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  return { spots: spots.slice(0, 12) };
}

async function verifyRecommendation(recommendation, context) {
  let kakaoError = null;
  try {
    const kakaoSpot = await verifyWithKakao(recommendation, context);
    if (kakaoSpot) return kakaoSpot;
  } catch (error) {
    kakaoError = error;
  }

  try {
    const naverSpot = await verifyWithNaver(recommendation, context);
    if (naverSpot) return naverSpot;
  } catch (error) {
    if (!kakaoError) throw error;
  }

  if (kakaoError && (!naverClientId || !naverClientSecret)) {
    throw kakaoError;
  }

  return null;
}

async function createVerifiedSpots(context) {
  if (!kakaoRestApiKey && (!naverClientId || !naverClientSecret)) {
    throw new Error("KAKAO_REST_API_KEY or NAVER_CLIENT_ID/NAVER_CLIENT_SECRET is required");
  }

  const recommendations = Array.isArray(context.recommendations)
    ? normalizedPhotoSpotRecommendations({ recommendations: context.recommendations }, normalizedSearchQuery(context))
    : [];
  const verificationContext = {
    region: normalizedSearchQuery(context),
    userLocation: coordinateFromLocation(context.userLocation),
  };
  const spots = [];
  const seen = new Set();

  for (const recommendation of recommendations) {
    const verifiedSpot = await verifyRecommendation(recommendation, verificationContext);
    if (!verifiedSpot || seen.has(verifiedSpot.id)) continue;

    seen.add(verifiedSpot.id);
    spots.push(verifiedSpot);
  }

  return { spots };
}

createServer(async (request, response) => {
  const requestPath = new URL(request.url ?? "/", "http://localhost").pathname;
  const adminSubmittedPhotoMatch = requestPath.match(/^\/admin\/submitted-spots\/([^/]+)\/photo$/);
  if (request.method === "GET" && adminSubmittedPhotoMatch) {
    if (!adminReviewToken) {
      sendJSON(response, 503, { error: "Admin review is not configured" });
      return;
    }

    if (!hasAdminReviewAccess(request)) {
      sendJSON(response, 401, { error: "Admin review access is required" });
      return;
    }

    const submittedSpotID = decodeURIComponent(adminSubmittedPhotoMatch[1]);
    const submittedSpot = loadSubmittedSpots().find((spot) => spot?.id === submittedSpotID);
    const encodedPhoto = submittedSpot?.photoDataBase64;

    if (!encodedPhoto) {
      sendJSON(response, 404, { error: "Submitted photo not found" });
      return;
    }

    const photoBuffer = Buffer.from(encodedPhoto, "base64");
    response.writeHead(200, {
      "Content-Type": submittedSpotPhotoContentType(photoBuffer),
      "Content-Length": photoBuffer.length,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    });
    response.end(photoBuffer);
    return;
  }

  const submittedPhotoMatch = requestPath.match(/^\/submitted-spots\/([^/]+)\/photo$/);
  if (request.method === "GET" && submittedPhotoMatch) {
    const submittedSpotID = decodeURIComponent(submittedPhotoMatch[1]);
    const submittedSpot = loadSubmittedSpots().find((spot) => spot?.id === submittedSpotID);
    const encodedPhoto = submittedSpot?.photoDataBase64;

    if (submittedSpot?.status !== "approved" || !encodedPhoto) {
      sendJSON(response, 404, { error: "Submitted photo not found" });
      return;
    }

    const photoBuffer = Buffer.from(encodedPhoto, "base64");
    response.writeHead(200, {
      "Content-Type": submittedSpotPhotoContentType(photoBuffer),
      "Content-Length": photoBuffer.length,
      "Cache-Control": "public, max-age=86400",
      "X-Content-Type-Options": "nosniff",
    });
    response.end(photoBuffer);
    return;
  }

  // 서버가 실제로 하는 일을 보고합니다.
  //
  // 전에는 AI 공급자와 모델 이름을 돌려줬습니다. AI 를 걷어냈으므로
  // 그 값은 사라졌고, 그대로 두면 지워진 변수를 참조해서 이 엔드포인트가
  // 500 으로 터집니다.
  //
  // 대신 장소 검색 키가 실제로 설정됐는지를 돌려줍니다.
  // 배포한 뒤 curl https://호스트/health 한 번으로 키 누락을 잡을 수
  // 있어야 합니다. 키가 없으면 앱에서 장소 검색이 조용히 빈 결과가 되고,
  // 그때 원인을 찾는 것은 훨씬 어렵습니다.
  if (request.method === "GET" && requestPath === "/health") {
    sendJSON(response, 200, {
      ok: true,
      placeSearch: {
        naver: Boolean(naverClientId && naverClientSecret),
        kakao: Boolean(kakaoRestApiKey),
      },
      submittedSpotCount: loadSubmittedSpots().length,
    });
    return;
  }

  if (request.method === "GET" && requestPath === "/submitted-spots") {
    sendJSON(response, 200, {
      spots: loadSubmittedSpots()
        .filter((spot) => spot?.status === "approved")
        .map((spot) => submittedSpotResponse(spot, request)),
    });
    return;
  }

  const reviewSpotMatch = requestPath.match(/^\/admin\/submitted-spots\/([^/]+)$/);
  if (requestPath === "/admin/submitted-spots" || reviewSpotMatch) {
    if (!adminReviewToken) {
      sendJSON(response, 503, { error: "Admin review is not configured" });
      return;
    }

    if (!hasAdminReviewAccess(request)) {
      sendJSON(response, 401, { error: "Admin review access is required" });
      return;
    }

    if (request.method === "GET" && requestPath === "/admin/submitted-spots") {
      sendJSON(response, 200, {
        spots: loadSubmittedSpots().map((spot) => adminSubmittedSpotResponse(spot, request)),
      });
      return;
    }

    if (request.method === "PATCH" && reviewSpotMatch) {
      try {
        const reviewedSpot = reviewSubmittedSpot(
          decodeURIComponent(reviewSpotMatch[1]),
          await readJSON(request),
        );
        sendJSON(response, 200, { spot: adminSubmittedSpotResponse(reviewedSpot, request) });
      } catch (error) {
        sendJSON(response, 400, {
          error: error instanceof Error ? error.message : "Unable to review submitted spot",
        });
      }
      return;
    }

    sendJSON(response, 405, { error: "Method not allowed" });
    return;
  }

  const postEndpoints = [
    "/verify-spots",
    "/search-places",
    "/submitted-spots",
  ];
  if (request.method !== "POST" || !postEndpoints.includes(requestPath)) {
    sendJSON(response, 404, { error: "Not found" });
    return;
  }

  try {
    const context = await readJSON(request);
    if (requestPath === "/verify-spots") {
      const verifiedSpots = await createVerifiedSpots(context);
      sendJSON(response, 200, verifiedSpots);
      return;
    }

    if (requestPath === "/search-places") {
      const places = await createPlaceSearchResults(context);
      sendJSON(response, 200, places);
      return;
    }

    if (requestPath === "/submitted-spots") {
      const submittedSpotResult = createSubmittedSpot(context);
      sendJSON(response, 201, {
        ...submittedSpotResult,
        spot: submittedSpotResponse(submittedSpotResult.spot, request),
      });
      return;
    }

    sendJSON(response, 404, { error: "Not found" });
  } catch (error) {
    if (error instanceof ServiceConfigurationError) {
      sendJSON(response, 503, {
        code: error.code,
        error: error.message,
      });
      return;
    }

    sendJSON(response, 500, {
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
}).listen(port, host, () => {
  console.log(`Viewfinder recommendation server listening on http://${host}:${port}`);
  console.log(`Place verification endpoint: http://172.30.1.47:${port}/verify-spots`);
  console.log(`Place search endpoint: http://172.30.1.47:${port}/search-places`);
  console.log(`Submitted spots endpoint: http://172.30.1.47:${port}/submitted-spots`);

  if (!naverClientId || !naverClientSecret) {
    console.warn("Naver Local Search is disabled: set NAVER_CLIENT_ID and NAVER_CLIENT_SECRET in RecommendationServer/.env.local");
  }
});
