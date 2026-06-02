# Viewfinder AI Recommendation Server

This tiny server keeps AI API keys out of the iPhone app.

## Local Setup

```sh
cp RecommendationServer/.env.example RecommendationServer/.env.local
```

For a free-tier-friendly setup, open `RecommendationServer/.env.local` and put your Google Gemini API key after `GEMINI_API_KEY=`.
Gemini only creates candidate spot names and descriptions. Put either a Kakao REST API key or Naver Local Search keys below so the server can verify real places and coordinates.

```env
AI_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-api-key-here
GEMINI_MODEL=gemini-2.5-flash-lite

KAKAO_REST_API_KEY=your-kakao-rest-api-key-here

NAVER_CLIENT_ID=your-naver-client-id-here
NAVER_CLIENT_SECRET=your-naver-client-secret-here
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
```

For a real iPhone or App Store build, deploy this server behind HTTPS and put that HTTPS URL in `ViewfinderRecommendationEndpoint`.
