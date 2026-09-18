# Home 위치 기반 추천 변경 보고

## 원인

- 기존 추천 캐시에 지역 식별자가 없어 이전 지역 결과를 재사용할 수 있었습니다.
- 위치의 timestamp/freshness와 foreground 갱신이 충분히 연결되지 않았습니다.
- 새 결과가 비어 있으면 이전 추천을 유지하는 경로가 있었습니다.
- Home 테마/인기 후보에 전역 검색 데이터가 섞이고, 확장 추천에서 전체 seed를 다시 사용하는 경로가 있었습니다.
- 추천 서비스의 고정 seed만으로는 새로 등록한 장소를 즉시 반영하기 어려웠습니다.
- 날씨 요청 및 시간 해석에 서울 시간대가 고정되어 있었습니다.

## 최종 정책

- 위치 원본: CoreLocation의 현재 위치 또는 timestamp가 검증된 최근 위치.
- Home 지역: 위도/경도 0.25도 단위로 양자화한 중심점 기준 50km 후보군. 기존 중심에서 30km 이내 이동이면 context 유지.
- 키: `home-v2-50km-<latitudeBucket>-<longitudeBucket>`. 행정구역/국경 경계가 아니라 도시권 반경 정책입니다.
- 후보를 먼저 지역으로 제한한 뒤 기존 날씨/시간/인기/테마 scoring을 적용합니다.
- 캐시: 기존 파일 구조를 확장해 contextKey와 cachedAt을 저장. 동일 context이고 30분 이내인 경우만 복원. 키 없는 legacy, 미래 timestamp, 만료, 다른 지역 캐시는 거부합니다.
- 초기 위치 확인 전 캐시를 무조건 노출하지 않습니다. 지역이 확인되면 일치하는 캐시를 복원하고 재계산합니다.
- 새 결과는 후보군과 함께 한 번에 교체합니다. 빈 결과도 이전 국가 추천을 대체합니다.
- 지역 장소가 없으면 작은 지역 안내와 장소 추가/검색 진입을 표시합니다. 위치 미확보는 별도 중립 상태입니다.
- 장소가 적으면 있는 수만 표시하며 TOP 5 미만은 '인기 출사지'로 표시합니다. 다른 국가로 개수를 채우지 않습니다.

## 위치 및 갱신

- 최근 위치 유효기간 1시간, 새 위치 응답은 2분 이내 timestamp, 정확도 5km 이내.
- 위치 요청은 4초로 제한하고 진행 중 요청은 합칩니다. 오래된 위치로 한국을 기본값처럼 사용하지 않습니다.
- 앱 active/Home 진입 시 한 번 위치를 확인합니다. 작은 이동에서는 후보 filtering/scoring을 반복하지 않습니다.
- 같은 지역이어도 시간이 바뀐 뒤 앱에 복귀하면 시간 기반 추천을 갱신합니다(시간 단위 비교).
- 추천 생성 revision을 비교해 늦게 완료된 이전 지역 결과가 새 결과를 덮어쓰지 못하게 합니다.
- 날씨는 현재 사용자 위치 기준입니다. 15km 이동 또는 30분 freshness 기준으로 필요한 경우 갱신하고 진행 중 요청/이전 응답을 관리합니다.
- 날씨 API에 timezone=auto를 요청하고 응답 timezone/UTC offset으로 시간과 일출/일몰을 해석합니다. 날씨 응답이 없는 경우 기기 timezone fallback은 남아 있습니다.

## Home / Map / 저장 데이터

- Home 후보는 로컬 seed + 공개 등록 장소를 합친 카탈로그에서 지역 제한합니다. 외부 검색 결과 자체를 자동 추천 후보로 넣지 않습니다.
- Map은 전체 seed/등록 장소/기존 검색 데이터와 기존 viewport 필터를 유지합니다. Home 지역 필터를 Map에 적용하지 않습니다.
- foreground GPS 갱신만으로 사용자가 pan한 지도 카메라를 되돌리지 않습니다. 최초 배치와 현재 위치 액션은 유지합니다.
- 새 장소 POST 성공 결과를 즉시 Home 카탈로그에 합칩니다. 후속 목록 GET이나 캐시 만료를 기다리지 않습니다.
- Firestore collection/schema 변경, migration, 전체 데이터 삭제는 없습니다. 위치 업데이트마다 전체 목록을 다시 읽는 요청도 추가하지 않았습니다.
- 네트워크 비용/프레임 시간의 실측 수치는 이번 검증에 포함되지 않습니다.

## 변경 파일

- Viewfinder/Models/HomeRecommendationsViewModel.swift
- Viewfinder/Services/RecommendationLocationReader.swift
- Viewfinder/Services/LocalSeedDataService.swift
- Viewfinder/Services/WeatherService.swift
- Viewfinder/Views/Weather/WeatherViews.swift
- Viewfinder/ContentView.swift
- Viewfinder/Views/Home/HomeFeedView.swift
- Viewfinder/Views/Map/KoreaMapBackdropView.swift
- Tools/HomeContextRegression.swift
- Tools/run_home_context_regression.sh
- Tools/HomeLocationChanges.md

## 검증

23개 회귀 검사 통과: 서울/도쿄/부산 분리, 도쿄 20km 후보, 지역 0개, 새 등록 반영, nil 위치, 실제 위치 freshness 판정, matching/cross-region/expired/legacy 캐시, 늦은 generation 차단, 작은 이동 억제, 시간 경과 재계산, 도쿄 및 런던 DST 시간대.

테스트는 실제 Home ViewModel, 위치 유효성 함수, 시간 컨텍스트 코드를 사용합니다. 추천 scoring/network는 fixture로 대체하므로 실제 API·GPS·지도 gesture의 end-to-end 검증은 아닙니다. Map 전역 데이터 및 카메라 경로는 코드 검토로 확인했습니다.

최종 iOS Simulator 대상 xcodebuild 성공(exit 0). git diff --check 통과. 실제 iPhone의 해외 GPS 전환, 지도 pan/foreground 동작은 별도 실기기 확인이 필요합니다.

## 역할

Astra: 정책/통합 검토. Sol: 위치·후보군·캐시 및 날씨 구현 분담(사용량 제한으로 중단된 부분은 메인 에이전트가 완료). Luna: Home empty/partial UI. Terra는 사용하지 않았습니다.
