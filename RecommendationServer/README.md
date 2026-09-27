# Viewfinder Backend

앱에 넣을 수 없는 API 키를 대신 들고 있는 작은 서버입니다.
네이버·카카오 장소검색 키는 클라이언트에 넣으면 노출되므로 이 서버를 거칩니다.

## AI 가 빠졌습니다

전에는 이 서버가 AI 로 출사지를 추천하고 새 장소를 발굴했습니다. 그 코드를
전부 제거했습니다. 이유는 두 가지입니다.

**앱에서 아무도 부르지 않았습니다.** `GPTRecommendationService`,
`GeminiRecommendationService`, `AIPhotoSpotResolver` 세 파일 모두 앱에서
참조가 없었습니다. 홈 추천은 `HomeRecommendationService`(로컬 규칙)가
131곳 시드를 거리·시간대·날씨·혼잡도로 골라 만들고 있었습니다.

**품질 문제가 구조적이었습니다.** AI 에게 "사진 예쁜 곳을 추천해"라고
시키면 관광지만 나왔습니다. 프롬프트에 남산타워·경복궁·롯데월드타워 같은
금지 목록을 길게 넣어도 마찬가지였습니다. LLM 은 어떤 장소를 "그에 관한
글이 얼마나 존재하는지"만큼 압니다. 출사지의 품질(빛 방향, 배경 정리,
삼각대 가능 여부)은 글로 존재하지 않고 유명함은 존재합니다. 그래서 항상
유명함으로 회귀하고, 금지 목록은 상위 몇 개만 지웁니다. 21번째가 올라옵니다.

사용자 장소 제보는 Firebase Authentication과 Firestore로 처리합니다.
이 서버의 `submitted-spots.json`은 이전 데이터 확인용 읽기 전용 백업입니다.

그래서 **OpenAI·Gemini 키가 더 이상 필요하지 않습니다.**

## 로컬 설정

```sh
cp RecommendationServer/.env.example RecommendationServer/.env.local
```

```env
NAVER_CLIENT_ID=your-naver-client-id-here
NAVER_CLIENT_SECRET=your-naver-client-secret-here

KAKAO_REST_API_KEY=your-kakao-rest-api-key-here
```

| 변수 | 쓰임 | 없으면 |
|---|---|---|
| `NAVER_CLIENT_ID` / `NAVER_CLIENT_SECRET` | `POST /search-places` 장소 검색 | 홈·지도·제보의 장소 검색이 동작하지 않습니다 |
| `KAKAO_REST_API_KEY` | `POST /verify-spots` 장소 검증 | 검증 경로만 막힙니다 |

`PORT`(기본 8787)와 `HOST`(기본 0.0.0.0)도 환경변수로 바꿀 수 있습니다.

## 실행

```sh
node RecommendationServer/server.mjs
```

## 설정이 됐는지 확인

```sh
curl http://localhost:8787/health
```

```json
{ "ok": true, "placeSearch": { "naver": true, "kakao": true }, "submittedSpotCount": 0 }
```

`naver` 가 `false` 면 장소 검색이 동작하지 않습니다. 배포한 뒤 가장 먼저
확인할 곳입니다. 키가 없으면 앱에서는 검색 결과가 조용히 비어 보이고,
그때 원인을 찾는 것은 훨씬 어렵습니다.

## 엔드포인트

```text
GET   /health
POST  /search-places                     네이버 장소검색. 앱의 모든 장소 검색
POST  /verify-spots                      카카오/네이버로 장소 확인
GET   /submitted-spots                   이전 사용자 장소 데이터(읽기 전용)
POST  /submitted-spots                   410 Gone — 새 제보는 Firestore 사용
GET   /submitted-spots/:id/photo         이전 장소 사진(읽기 전용)
```

`POST /search-places` 는 네이버 지역검색 결과만 돌려줍니다. Apple MapKit 이나
카카오 검색은 쓰지 않습니다.

## 기존 사용자 장소 백업

새 장소는 앱에서 Firestore `places/{placeID}`에 저장됩니다. 이전 데이터와
사진을 보존하기 위해 `RecommendationServer/submitted-spots.json` 및
`GET /submitted-spots`는 읽기 전용으로 남겨두었습니다. 서버 시작 시 파일을
정규화하거나 다시 쓰지 않으며, 이전 `POST /submitted-spots` 요청에는
`410 Gone`을 반환합니다. Firebase Storage 사진 업로드는 별도 작업입니다.

## 출시 전에 반드시 할 일

앱은 서버 주소를 `VIEWFINDER_RECOMMENDATION_ENDPOINT` Xcode 빌드 설정에서
읽습니다.

```
Debug    http://gyuhyeons-MacBook-Pro.local:8787/recommendations
Release  ""      <- 비어 있습니다
```

**Release 가 비어 있으면 RecommendationServer를 사용하는 외부 장소 검색과
장소 검증이 동작하지 않습니다.** Firestore를 통한 새 장소 저장·수정·삭제는
Firebase 설정과 인증을 사용하며 이 endpoint와 별개입니다.
릴리스 빌드는 HTTPS 가 아닌 주소를 의도적으로 무시하므로
(`AppInfrastructure.swift`), 로컬 주소를 넣어도 소용없습니다.

이 서버를 HTTPS 로 배포하고 Release 값을 그 주소로 설정해야 합니다.
경로 이름(`/recommendations`)은 AI 를 쓰던 시절의 흔적입니다. 앱은 이 값에서
마지막 경로만 떼어내 `/search-places` 같은 실제 경로를 만들기 때문에
(`AppBackendConfiguration.endpoint(named:)`) 값 자체는 그대로 두어도
동작합니다.
