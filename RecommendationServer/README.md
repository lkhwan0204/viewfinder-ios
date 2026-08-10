# Viewfinder AI Recommendation Server

This tiny server keeps AI API keys out of the iPhone app.

## Local Setup

```sh
cp RecommendationServer/.env.example RecommendationServer/.env.local
```

For a free-tier-friendly setup, open `RecommendationServer/.env.local` and put your Google Gemini API key after `GEMINI_API_KEY=`.
Gemini only creates candidate spot names and descriptions. Place search from the add-place sheet uses Naver Local Search, so `NAVER_CLIENT_ID` and `NAVER_CLIENT_SECRET` are required for that flow. Kakao can still be used by the recommendation verification flow.

```env
AI_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-api-key-here
GEMINI_MODEL=gemini-2.5-flash-lite

KAKAO_REST_API_KEY=your-kakao-rest-api-key-here

NAVER_CLIENT_ID=your-naver-client-id-here
NAVER_CLIENT_SECRET=your-naver-client-secret-here

# 승인 대기 중인 장소 제보를 검토하는 관리자 API 토큰
VIEWFINDER_ADMIN_REVIEW_TOKEN=replace-with-a-long-random-value
```

Gemini is the default recommendation provider when `AI_PROVIDER=gemini`.
OpenAI is still supported if you later want to switch back:

```env
AI_PROVIDER=openai
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-5.4-nano
```

## Run

```sh
node RecommendationServer/server.mjs
```

The app currently calls this Mac Wi-Fi address from `Viewfinder/Supporting/App-Info.plist`:

```text
http://172.30.1.47:8787/recommendations
```

The search flow uses these extra endpoints from the same base URL:

```text
POST /spot-recommendations
POST /verify-spots
POST /search-places
GET /submitted-spots
POST /submitted-spots
GET /admin/submitted-spots
PATCH /admin/submitted-spots/:id
GET /admin/submitted-spots/:id/photo
```

`POST /search-places` returns Naver Local Search results only. It does not use Apple MapKit or Kakao search.

## 장소 제보 검토

사용자가 `POST /submitted-spots`로 제보한 장소는 기본적으로 `pending_review` 상태로 저장됩니다.
공개 앱이 호출하는 `GET /submitted-spots`와 사진 URL은 `approved` 상태인 장소만 반환하므로,
관리자가 승인하기 전에는 홈, 지도, 검색에 노출되지 않습니다.

서버의 `.env.local`에 `VIEWFINDER_ADMIN_REVIEW_TOKEN`을 설정한 뒤, 아래처럼 검토 API를 사용하세요.
토큰은 앱 코드나 클라이언트에 넣지 않습니다.

```sh
# 승인 대기 및 기존 제보 전체 조회
curl \
  -H "X-Viewfinder-Admin-Token: $VIEWFINDER_ADMIN_REVIEW_TOKEN" \
  http://localhost:8787/admin/submitted-spots

# 승인
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Viewfinder-Admin-Token: $VIEWFINDER_ADMIN_REVIEW_TOKEN" \
  -d '{"status":"approved"}' \
  http://localhost:8787/admin/submitted-spots/SPOT_ID

# 반려 또는 보완 요청
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Viewfinder-Admin-Token: $VIEWFINDER_ADMIN_REVIEW_TOKEN" \
  -d '{"status":"rejected","reviewNote":"장소 또는 사진 정보를 보완해 주세요."}' \
  http://localhost:8787/admin/submitted-spots/SPOT_ID
```

`GET /admin/submitted-spots` 응답에는 관리자 전용 `reviewPhotoURL`이 포함됩니다.
이 URL은 같은 관리자 토큰 헤더를 넣어야 열리며, 승인 전 사진도 검토할 수 있습니다.

The app reads the server URL from the `VIEWFINDER_RECOMMENDATION_ENDPOINT`
Xcode build setting. Debug currently points to the local development server.

For a real iPhone or App Store build, deploy this server behind HTTPS and set
the Release value of `VIEWFINDER_RECOMMENDATION_ENDPOINT` to that hosted
`/recommendations` URL. Release builds intentionally ignore non-HTTPS URLs.
