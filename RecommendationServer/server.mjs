import { createServer } from "node:http";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";
const serverDirectory = dirname(fileURLToPath(import.meta.url));
const submittedSpotsPath = join(serverDirectory, "submitted-spots.json");

loadLocalEnvironment();

const provider = (process.env.AI_PROVIDER ?? (process.env.GEMINI_API_KEY ? "gemini" : "openai"))
  .trim()
  .toLowerCase();
const openAIModel = process.env.OPENAI_MODEL ?? "gpt-5.4-nano";
const geminiModel = process.env.GEMINI_MODEL ?? "gemini-2.5-flash-lite";
const openAIApiKey = process.env.OPENAI_API_KEY;
const geminiApiKey = process.env.GEMINI_API_KEY;
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

const photoSpotAestheticInstruction =
  "관광지가 아니라 사진 찍었을 때 결과물이 예쁜 출사지를 추천해줘. 서울 서래섬처럼 노을, 꽃, 강변, 골목, 필름감성, 산책로, 오래된 거리, 조용한 로컬 분위기, 사진 구도가 좋은 장소를 우선 추천해줘. 여행 명소나 랜드마크보다 산책하면서 찍기 좋은 곳, 강변 포인트, 꽃길, 철길, 시장, 카페거리, 오래된 건물, 한강 포인트처럼 분위기와 구도가 살아나는 장소를 고른다. 지역별 분위기 조합을 이해해서 성수는 카페+골목+저녁빛, 문래는 빈티지+철골목+야간출사, 연남은 산책+감성카페+골목, 한강은 노을+야경+산책처럼 추천한다. 필름감성+산책, 조용한 야경, 노을+한강, 빈티지+골목 같은 분위기 조합을 우선한다. 좋은 예시는 보라매공원, 연남동 골목, 경의선숲길, 문래창작촌, 선유도공원, 망원한강공원, 서울숲, 안양천 산책길, 성수 골목, 해방촌, 을지로 골목, 항동철길, 북촌 뒷골목이다. 나쁜 예시는 남산타워, 경복궁, 롯데월드타워, 명동, 스타벅스, 두물머리, 일산호수공원처럼 유명 관광지만 나열하거나 실제로 붐비는 장소다. 사람 적은 명소는 유명 관광지, 주말 평균 혼잡도가 높은 곳, SNS 초대형 핫플을 제외하고 조용한 공원/산책길/골목을 우선한다.";

const systemPrompt =
  `너는 한국 출사 앱의 추천 엔진이다. AI 단독으로 새 장소를 만들지 말고 앱이 준 로컬 출사지 후보를 지역, 태그, 카테고리, 커뮤니티 신호로 보강해 고른다. ${photoSpotAestheticInstruction} 현재 위치, 시간대, 날씨, 후보 장소별 거리와 출사 특징을 보고 오늘 가기 좋은 출사지 3~6개를 고른다. 가까운 곳만 고르지 말고 산책성, 빛/노을/야경, 필름/로컬 감성, 사진 구도, 계절감, 혼잡도를 함께 판단한다. 감성카페는 문래, 성수, 을지로, 연남 같은 로컬 카페 지역과 독립 카페 감성을 우선하고 체인형 카페는 피한다. 반드시 후보 장소의 spotID만 사용하고, 이유는 왜 사진이 예쁘게 나오는지와 어떤 분위기인지가 드러나게 한국어 한 문장으로 짧게 쓴다.`;

const discoverySystemPrompt =
  `너는 한국 출사 앱의 AI 장소 발굴 엔진이다. 현재 시간대, 사용자 위치, 검색 지역, 날씨, 사람들이 많이 찾는 출사지 경향을 함께 보고 실제 지도 검색이 가능한 한국 출사지 후보를 새로 추천한다. ${photoSpotAestheticInstruction} 앱 첫 실행처럼 검색 지역이 없으면 사용자 현재 위치 주변의 유명 관광지가 아니라 사진 결과물이 예쁘게 나오는 장소를 우선 추천한다. moodCategory가 있으면 해당 분위기/목적에 맞는 장소만 5~8개 추천하고, 다른 섹션과 같은 장소를 반복하지 않도록 구체적인 촬영 포인트를 다양하게 고른다. 기존 후보 장소가 들어와도 그대로 순서만 바꾸지 말고 참고만 하며, 검색 지역이 있으면 그 주변에서 사용자가 고를 수 있는 장소 5~8개를 만든다. 수원시, 강서구, 부산처럼 행정구역만 쓰지 말고 서래섬, 선유도공원, 문래창작촌처럼 지도에 핀을 찍을 수 있는 정확한 장소명만 쓴다. 폐장, 출입 제한, 사유지, 일반 교회/학교/병원/호텔처럼 출사지로 부적절한 장소는 제외한다. 감성 카페를 추천해야 하는 경우 런던베이글뮤지엄, 스타벅스, 투썸, 이디야, 메가커피, 컴포즈, 블루보틀, 노티드, 랜디스도넛, 아우어베이커리, 파리바게뜨, 뚜레쥬르 같은 프랜차이즈/대형 체인/유명 지점형 카페는 제외하고 독립 카페, 로컬 카페, 뷰 좋은 카페, 공간이 독특한 카페만 고른다. mapQuery는 Apple 지도, 네이버 지도, 카카오맵에서 잘 검색되는 한국어 장소명으로 쓴다. 좌표나 가짜 주소는 만들지 않는다. 이용 가능시간은 확인 가능한 범위에서 짧게 쓰고, 불확실하면 '이용 가능시간 확인 필요'라고 쓴다. summary에는 왜 사진이 예쁘게 나오는지, reason에는 현재 시간대/날씨/거리감/인기 포인트 중 최소 2가지를 반영한 추천 이유, bestTime에는 추천 촬영 시간대, lensSuggestion과 weatherFit에는 실제 출사 준비에 필요한 정보를 짧고 구체적인 한국어로 쓴다.`;

const photoSpotSearchSystemPrompt =
  `너는 한국 출사 앱의 장소 후보 생성 엔진이다. 사용자가 입력한 지역명, 현재 위치, 시간대, 날씨를 참고해 그 지역에서 실제로 지도 검색이 가능한 출사지 후보를 5~8개 만든다. ${photoSpotAestheticInstruction} 토큰을 아끼기 위해 장소명, 왜 사진이 예쁘게 나오는지 한 줄 설명, 추천 촬영 시간대, 사진 포인트, 태그, isFranchise만 생성한다. 주소, 좌표, 지도 링크, 긴 설명, 존재 여부 검증은 절대 만들지 않는다. 장소명은 카카오맵이나 네이버 지도에서 검색될 가능성이 높은 한국어 공식명 또는 통용명을 사용한다. 수원시, 강서구, 부산처럼 행정구역만 쓰지 말고 서래섬, 선유도공원, 항동철길처럼 지도에 핀을 찍을 수 있는 정확한 장소명만 쓴다. 남산타워, 경복궁, 롯데월드타워, 명동처럼 유명 관광지만 나열하는 추천은 피하고, 검색 지역 안의 골목, 강변, 꽃길, 산책로, 철길, 시장, 오래된 거리, 로컬 분위기 장소를 우선한다. 폐장, 출입 제한, 사유지, 일반 교회/학교/병원/호텔처럼 출사지로 부적절한 장소는 제외한다. 검색 지역 바깥의 장소는 넣지 않는다. 감성 카페를 추천해야 하는 경우 프랜차이즈, 대형 체인, 유명 지점형 카페는 제외한다. 제외 예시: 런던베이글뮤지엄, 스타벅스, 투썸, 이디야, 메가커피, 컴포즈, 블루보틀, 노티드, 랜디스도넛, 아우어베이커리, 파리바게뜨, 뚜레쥬르. 감성 카페는 독립 카페, 로컬 카페, 뷰 좋은 카페, 공간이 독특한 카페만 추천한다. 모든 추천 항목에는 isFranchise를 넣고, 프랜차이즈/체인/유명 지점형 카페라면 true로 표시한다. description은 왜 사진이 예쁘게 나오는지, reason은 왜 지금 추천하는지, bestTime은 추천 촬영 시간대, photoPoint는 실제로 어디를 어떻게 찍으면 좋은지 짧게 쓴다.`;

const recommendationSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    recommendations: {
      type: "array",
      minItems: 3,
      maxItems: 6,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          spotID: {
            type: "string",
            description: "추천할 후보 장소의 spotID",
          },
          reason: {
            type: "string",
            description: "오늘 이 장소를 추천하는 짧은 한국어 이유",
          },
          scoreLabel: {
            type: "string",
            description: "추천 점수나 분위기를 나타내는 짧은 라벨",
          },
        },
        required: ["spotID", "reason", "scoreLabel"],
      },
    },
  },
  required: ["recommendations"],
};

const discoverySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    spots: {
      type: "array",
      minItems: 5,
      maxItems: 8,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          name: {
            type: "string",
            description: "지도와 앱에 보여줄 실제 장소 이름",
          },
          region: {
            type: "string",
            description: "시/구/동 정도의 짧은 지역명",
          },
          mapQuery: {
            type: "string",
            description: "지도 검색에 넣기 좋은 한국어 검색어",
          },
          summary: {
            type: "string",
            description: "어떤 사진을 찍기 좋은지 설명하는 한 문장",
          },
          hashtags: {
            type: "array",
            minItems: 2,
            maxItems: 4,
            items: {
              type: "string",
            },
          },
          reason: {
            type: "string",
            description: "현재 시간대, 위치, 날씨, 인기 요소를 반영한 추천 이유",
          },
          scoreLabel: {
            type: "string",
            description: "예: 근처 인기, 오늘 빛 좋음, 실내 추천",
          },
          theme: {
            type: "string",
            enum: ["city", "healing", "night", "flower", "indoor", "water"],
          },
          parkingInfo: {
            type: "string",
            description: "주차장 유무를 짧게 안내",
          },
          nearbyParkingInfo: {
            type: "string",
            description: "근처 주차장 추천 또는 확인 안내",
          },
          openingHours: {
            type: "string",
            description: "이용 가능시간. 모르면 이용 가능시간 확인 필요",
          },
          bestTime: {
            type: "string",
            description: "추천 촬영 시간대",
          },
          crowdLevel: {
            type: "string",
            description: "사람이 많을 시간대와 피하기 좋은 시간",
          },
          lensSuggestion: {
            type: "string",
            description: "추천 렌즈나 화각",
          },
          weatherFit: {
            type: "string",
            description: "오늘 날씨와 어울리는 촬영 궁합",
          },
        },
        required: [
          "name",
          "region",
          "mapQuery",
          "summary",
          "hashtags",
          "reason",
          "scoreLabel",
          "theme",
          "parkingInfo",
          "nearbyParkingInfo",
          "openingHours",
          "bestTime",
          "crowdLevel",
          "lensSuggestion",
          "weatherFit",
        ],
      },
    },
  },
  required: ["spots"],
};

const photoSpotRecommendationSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    recommendations: {
      type: "array",
      minItems: 5,
      maxItems: 8,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: {
            type: "string",
            description: "장소명 기반의 짧은 고유 ID",
          },
          name: {
            type: "string",
            description: "카카오맵이나 네이버 지도에서 검색 가능한 실제 장소명",
          },
          description: {
            type: "string",
            description: "왜 사진 결과물이 예쁘게 나오는지 설명하는 한 문장",
          },
          bestTime: {
            type: "string",
            description: "추천 촬영 시간대. 예: 해질녘 30분 전, 오전 9시 전후, 비 온 뒤 저녁",
          },
          reason: {
            type: "string",
            description: "현재 시간대, 날씨, 지역 분위기를 반영한 추천 이유",
          },
          photoPoint: {
            type: "string",
            description: "실제로 어디를 어떻게 찍으면 좋은지 알려주는 짧은 사진 포인트",
          },
          tags: {
            type: "array",
            minItems: 2,
            maxItems: 5,
            items: {
              type: "string",
            },
          },
          isFranchise: {
            type: "boolean",
            description: "프랜차이즈, 대형 체인, 유명 지점형 카페이면 true. 독립/로컬 카페나 일반 출사지이면 false",
          },
        },
        required: ["id", "name", "description", "bestTime", "reason", "photoPoint", "tags", "isFranchise"],
      },
    },
  },
  required: ["recommendations"],
};

const geminiRecommendationSchema = removeGeminiUnsupportedSchemaFields(recommendationSchema);
const geminiDiscoverySchema = removeGeminiUnsupportedSchemaFields(discoverySchema);
const geminiPhotoSpotRecommendationSchema = removeGeminiUnsupportedSchemaFields(photoSpotRecommendationSchema);

function removeGeminiUnsupportedSchemaFields(value) {
  if (Array.isArray(value)) {
    return value.map(removeGeminiUnsupportedSchemaFields);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== "additionalProperties")
        .map(([key, nestedValue]) => [key, removeGeminiUnsupportedSchemaFields(nestedValue)]),
    );
  }

  return value;
}

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

function openAIResponseText(payload) {
  if (typeof payload.output_text === "string") {
    return payload.output_text;
  }

  return (payload.output ?? [])
    .flatMap((item) => item.content ?? [])
    .map((content) => content.text ?? "")
    .join("");
}

function geminiResponseText(payload) {
  return (payload.candidates ?? [])
    .flatMap((candidate) => candidate.content?.parts ?? [])
    .map((part) => part.text ?? "")
    .join("");
}

function coordinateFromLocation(location) {
  const latitude = Number(location?.latitude);
  const longitude = Number(location?.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return { latitude, longitude };
}

function distanceInKilometers(from, to) {
  const earthRadiusKilometers = 6371;
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const latitudeDelta = toRadians(to.latitude - from.latitude);
  const longitudeDelta = toRadians(to.longitude - from.longitude);
  const fromLatitude = toRadians(from.latitude);
  const toLatitude = toRadians(to.latitude);

  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(fromLatitude) * Math.cos(toLatitude) * Math.sin(longitudeDelta / 2) ** 2;

  return 2 * earthRadiusKilometers * Math.asin(Math.sqrt(haversine));
}

function timeOfDayLabel(hour) {
  if (hour >= 5 && hour < 9) return "아침";
  if (hour >= 9 && hour < 12) return "오전";
  if (hour >= 12 && hour < 17) return "오후";
  if (hour >= 17 && hour < 20) return "노을/매직아워";
  if (hour >= 20 || hour < 1) return "야경";
  return "심야";
}

function weatherCodeDescription(code) {
  if ([0].includes(code)) return "맑음";
  if ([1, 2].includes(code)) return "대체로 맑음";
  if ([3].includes(code)) return "흐림";
  if ([45, 48].includes(code)) return "안개";
  if ([51, 53, 55, 56, 57].includes(code)) return "이슬비";
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return "비";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "눈";
  if ([95, 96, 99].includes(code)) return "뇌우";
  return "날씨 정보 있음";
}

async function fetchCurrentWeather(location) {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.search = new URLSearchParams({
    latitude: String(location.latitude),
    longitude: String(location.longitude),
    current: [
      "temperature_2m",
      "relative_humidity_2m",
      "apparent_temperature",
      "precipitation",
      "rain",
      "weather_code",
      "cloud_cover",
      "wind_speed_10m",
      "wind_gusts_10m",
      "is_day",
    ].join(","),
    timezone: "auto",
    forecast_days: "1",
  }).toString();

  const weatherResponse = await fetch(url);
  const payload = await readResponsePayload(weatherResponse);

  if (!weatherResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "Weather request failed"));
  }

  const current = payload.current ?? {};
  const units = payload.current_units ?? {};
  const weatherCode = Number(current.weather_code);

  return {
    source: "Open-Meteo",
    time: current.time,
    descriptionKo: weatherCodeDescription(weatherCode),
    weatherCode,
    temperature: current.temperature_2m,
    temperatureUnit: units.temperature_2m,
    apparentTemperature: current.apparent_temperature,
    humidity: current.relative_humidity_2m,
    humidityUnit: units.relative_humidity_2m,
    precipitation: current.precipitation,
    precipitationUnit: units.precipitation,
    rain: current.rain,
    cloudCover: current.cloud_cover,
    cloudCoverUnit: units.cloud_cover,
    windSpeed: current.wind_speed_10m,
    windSpeedUnit: units.wind_speed_10m,
    windGusts: current.wind_gusts_10m,
    isDay: current.is_day,
  };
}

async function buildRecommendationContext(rawContext) {
  const userLocation = coordinateFromLocation(rawContext.userLocation);
  const searchLocation = coordinateFromLocation(rawContext.searchRegion);
  const now = new Date();
  const hour = Number.isFinite(Number(rawContext.hour)) ? Number(rawContext.hour) : now.getHours();
  const weatherLocation = searchLocation ?? userLocation;

  let weather = null;
  if (weatherLocation) {
    try {
      weather = await fetchCurrentWeather(weatherLocation);
    } catch (error) {
      weather = {
        source: "Open-Meteo",
        unavailableReason: error instanceof Error ? error.message : "Weather request failed",
      };
    }
  }

  const spots = Array.isArray(rawContext.spots)
    ? rawContext.spots
        .map((spot) => {
          const spotLocation = coordinateFromLocation(spot);
          const distanceKilometers =
            userLocation && spotLocation
              ? Number(distanceInKilometers(userLocation, spotLocation).toFixed(1))
              : null;

          return {
            ...spot,
            distanceKilometers,
          };
        })
        .sort((left, right) => {
          if (left.distanceKilometers === null) return 1;
          if (right.distanceKilometers === null) return -1;
          return left.distanceKilometers - right.distanceKilometers;
        })
    : [];

  return {
    ...rawContext,
    serverTimeISO: now.toISOString(),
    hour,
    timeOfDay: timeOfDayLabel(hour),
    userLocation,
    searchRegion: rawContext.searchRegion
      ? {
          ...rawContext.searchRegion,
          latitude: searchLocation?.latitude ?? rawContext.searchRegion.latitude,
          longitude: searchLocation?.longitude ?? rawContext.searchRegion.longitude,
        }
      : null,
    weather,
    spots,
  };
}

async function createOpenAIRecommendations(context) {
  if (!openAIApiKey) {
    throw new Error("OPENAI_API_KEY is required");
  }

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${openAIApiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      input: [
        {
          role: "system",
          content: systemPrompt,
        },
        {
          role: "user",
          content: JSON.stringify(context),
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "photo_shoot_recommendations",
          strict: true,
          schema: recommendationSchema,
        },
      },
    }),
  });

  const payload = await readResponsePayload(openAIResponse);
  if (!openAIResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "OpenAI request failed"));
  }

  return filterRecommendationPayload(JSON.parse(openAIResponseText(payload)), context);
}

async function createGeminiRecommendations(context) {
  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required");
  }

  const modelName = geminiModel.replace(/^models\//, "");
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelName)}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": geminiApiKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              {
                text: `${systemPrompt}\n\n후보와 사용자 정보(JSON):\n${JSON.stringify(context)}`,
              },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: geminiRecommendationSchema,
        },
      }),
    },
  );

  const payload = await readResponsePayload(geminiResponse);
  if (!geminiResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "Gemini request failed"));
  }

  const text = geminiResponseText(payload);
  if (!text) {
    throw new Error(payload.promptFeedback?.blockReason ?? "Gemini response was empty");
  }

  return filterRecommendationPayload(JSON.parse(text), context);
}

async function createOpenAISpotDiscoveries(context) {
  if (!openAIApiKey) {
    throw new Error("OPENAI_API_KEY is required");
  }

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${openAIApiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      input: [
        {
          role: "system",
          content: discoverySystemPrompt,
        },
        {
          role: "user",
          content: JSON.stringify(context),
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "photo_shoot_spot_discovery",
          strict: true,
          schema: discoverySchema,
        },
      },
    }),
  });

  const payload = await readResponsePayload(openAIResponse);
  if (!openAIResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "OpenAI request failed"));
  }

  return filterDiscoveryPayload(JSON.parse(openAIResponseText(payload)));
}

async function createGeminiSpotDiscoveries(context) {
  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required");
  }

  const modelName = geminiModel.replace(/^models\//, "");
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelName)}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": geminiApiKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              {
                text: `${discoverySystemPrompt}\n\n상황 정보(JSON):\n${JSON.stringify(context)}`,
              },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: geminiDiscoverySchema,
        },
      }),
    },
  );

  const payload = await readResponsePayload(geminiResponse);
  if (!geminiResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "Gemini request failed"));
  }

  const text = geminiResponseText(payload);
  if (!text) {
    throw new Error(payload.promptFeedback?.blockReason ?? "Gemini response was empty");
  }

  return filterDiscoveryPayload(JSON.parse(text));
}

async function createRecommendations(context) {
  const recommendationContext = await buildRecommendationContext(context);

  if (provider === "gemini") {
    return createGeminiRecommendations(recommendationContext);
  }

  if (provider === "openai") {
    return createOpenAIRecommendations(recommendationContext);
  }

  throw new Error("AI_PROVIDER must be 'gemini' or 'openai'");
}

async function createSpotDiscoveries(context) {
  const discoveryContext = await buildRecommendationContext(context);

  if (provider === "gemini") {
    return createGeminiSpotDiscoveries(discoveryContext);
  }

  if (provider === "openai") {
    return createOpenAISpotDiscoveries(discoveryContext);
  }

  throw new Error("AI_PROVIDER must be 'gemini' or 'openai'");
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

function filterRecommendationPayload(payload, context) {
  const recommendations = Array.isArray(payload?.recommendations) ? payload.recommendations : [];
  if (!recommendations.length) return payload;

  const spotsByID = new Map(
    (Array.isArray(context?.spots) ? context.spots : []).map((spot) => [String(spot.id ?? ""), spot]),
  );

  return {
    ...payload,
    recommendations: recommendations.filter((recommendation) => {
      const spot = spotsByID.get(String(recommendation?.spotID ?? ""));
      return !isOverexposedPhotoSpotCandidate({
        ...spot,
        reason: recommendation?.reason,
        tags: spot?.hashtags ?? spot?.tags,
      });
    }),
  };
}

function filterDiscoveryPayload(payload) {
  const spots = Array.isArray(payload?.spots) ? payload.spots : [];
  if (!spots.length) return payload;

  return {
    ...payload,
    spots: spots.filter((spot) => !isOverexposedPhotoSpotCandidate(spot)),
  };
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

async function createOpenAIPhotoSpotRecommendations(context) {
  if (!openAIApiKey) {
    throw new Error("OPENAI_API_KEY is required");
  }

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${openAIApiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      input: [
        {
          role: "system",
          content: photoSpotSearchSystemPrompt,
        },
        {
          role: "user",
          content: JSON.stringify(context),
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "photo_spot_recommendation_candidates",
          strict: true,
          schema: photoSpotRecommendationSchema,
        },
      },
    }),
  });

  const payload = await readResponsePayload(openAIResponse);
  if (!openAIResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "OpenAI request failed"));
  }

  return {
    recommendations: normalizedPhotoSpotRecommendations(
      JSON.parse(openAIResponseText(payload)),
      normalizedSearchQuery(context),
    ),
  };
}

async function createGeminiPhotoSpotRecommendations(context) {
  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required");
  }

  const modelName = geminiModel.replace(/^models\//, "");
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelName)}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": geminiApiKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              {
                text: `${photoSpotSearchSystemPrompt}\n\n검색 상황(JSON):\n${JSON.stringify(context)}`,
              },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: geminiPhotoSpotRecommendationSchema,
        },
      }),
    },
  );

  const payload = await readResponsePayload(geminiResponse);
  if (!geminiResponse.ok) {
    throw new Error(payloadErrorMessage(payload, "Gemini request failed"));
  }

  const text = geminiResponseText(payload);
  if (!text) {
    throw new Error(payload.promptFeedback?.blockReason ?? "Gemini response was empty");
  }

  return {
    recommendations: normalizedPhotoSpotRecommendations(JSON.parse(text), normalizedSearchQuery(context)),
  };
}

async function createPhotoSpotRecommendations(context) {
  const recommendationContext = await buildRecommendationContext({
    ...context,
    searchQuery: normalizedSearchQuery(context),
  });

  if (provider === "gemini") {
    return createGeminiPhotoSpotRecommendations(recommendationContext);
  }

  if (provider === "openai") {
    return createOpenAIPhotoSpotRecommendations(recommendationContext);
  }

  throw new Error("AI_PROVIDER must be 'gemini' or 'openai'");
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

  if (request.method === "GET" && requestPath === "/health") {
    sendJSON(response, 200, {
      ok: true,
      provider,
      model: provider === "gemini" ? geminiModel : openAIModel,
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
    "/recommendations",
    "/discover-spots",
    "/spot-recommendations",
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
    if (requestPath === "/spot-recommendations") {
      const recommendations = await createPhotoSpotRecommendations(context);
      sendJSON(response, 200, recommendations);
      return;
    }

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

    if (requestPath === "/discover-spots") {
      const discoveries = await createSpotDiscoveries(context);
      sendJSON(response, 200, discoveries);
      return;
    }

    const recommendations = await createRecommendations(context);
    sendJSON(response, 200, recommendations);
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
  console.log(`For your iPhone on the same Wi-Fi, use http://172.30.1.47:${port}/recommendations`);
  console.log(`Spot discovery endpoint: http://172.30.1.47:${port}/discover-spots`);
  console.log(`Spot recommendation endpoint: http://172.30.1.47:${port}/spot-recommendations`);
  console.log(`Place verification endpoint: http://172.30.1.47:${port}/verify-spots`);
  console.log(`Place search endpoint: http://172.30.1.47:${port}/search-places`);
  console.log(`Submitted spots endpoint: http://172.30.1.47:${port}/submitted-spots`);

  if (!naverClientId || !naverClientSecret) {
    console.warn("Naver Local Search is disabled: set NAVER_CLIENT_ID and NAVER_CLIENT_SECRET in RecommendationServer/.env.local");
  }
});
