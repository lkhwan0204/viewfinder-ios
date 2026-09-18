# Home 초기 로딩 UX — 2026-09-15

## 표시 조건과 상태

기존 full skeleton 조건은 initialLoading + Hero 추천 없음이었습니다. 이제 Hero와 인기 후보 모두 없는 최초 로딩에만 표시합니다. 이미지 다운로드 여부는 이 조건에 포함하지 않습니다.

상태는 initialLoading / loaded / refreshing / empty / failed, 그리고 위치를 판단할 수 없는 locationUnavailable을 유지합니다. 기존 콘텐츠가 있으면 추천 재생성 중 refreshing으로 표시하되 콘텐츠를 제거하지 않습니다. 지역 등록 장소 조회가 실패한 경우에는 실제 0개라고 단정하지 않고 failed를 표시하며 재시도에서 목록 조회를 다시 시도합니다. 이미 사용 가능한 로컬 추천이 있으면 배경 조회 실패로 Home을 가리지 않습니다.

## 캐시

기존 30분 제한을 24시간 stale 표시 허용으로 조정했습니다. 매번 최신 추천을 배경에서 재생성하므로 24시간은 refresh 주기가 아닙니다. 지역 키 불일치, legacy 키 없음, 미래 timestamp, 24시간 초과 캐시는 계속 거부합니다.

앱 시작 시 신뢰 가능한 최근 CoreLocation 위치가 있으면 그 context로 캐시를 먼저 복원하고, 새 위치 요청을 이어갑니다. 신뢰할 위치가 전혀 없으면 국가를 추측하지 않고 기존의 제한 시간 내 위치 확인을 기다립니다. 따라서 지역이 확인되지 않은 cold start에서 무조건 오래된 Home을 즉시 표시하는 방식은 아닙니다. 캐시의 장소 ID는 현재 로드된 카탈로그에서 해결 가능한 데이터만 사용합니다.

## Skeleton geometry / motion

- Hero는 loaded 화면에서 전달하는 heroSize와 topInset 그대로 사용합니다.
- 날씨 pill / 검색 원형은 38pt, 상단/좌우 inset은 실제 컨트롤 기준입니다.
- Hero 장소명/metadata는 실제 display/mono typography를 사용하고 하단 inset을 56pt로 맞췄습니다.
- 페이지 점은 5pt, 선택 표시는 13×5pt, 예약 높이는 20pt입니다.
- 인기 제목 위 간격 12pt, 제목/카드 간격 12pt, 카드 폭 46%, 비율 4:5, 실제 photo corner radius를 사용합니다.
- 테마 챕터 간격 48pt, 제목/필터 8pt, 필터/카드 12pt로 맞췄습니다. 테마 rail placeholder 폭은 일반적인 다수 결과 상태의 42%입니다.
- 레일별 카드 2개, 필터 placeholder 3개만 표시합니다.
- 평평한 단색 대신 낮은 대비의 gradient 표면과 텍스트 redaction을 사용합니다.
- 빠른 shimmer 대신 opacity 1↔0.78, 편도 1.6초 easeInOut pulse입니다. Reduce Motion/앱 비활성 시 static, View 종료 시 task 취소입니다.
- 상태 전환은 기존 0.18초 opacity를 유지하고 Reduce Motion에서는 전환 애니메이션을 끕니다.

## 유지한 기능

Bottom Tab Bar는 skeleton 밖의 기존 정상 UI입니다. 버튼 비활성화나 redaction을 적용하지 않습니다. 초기 skeleton에서 탭바 숨김 drag를 시작하지 않도록 했습니다.

PhotoSpotImageView의 이미지별 placeholder → 0.18초 image reveal을 재사용하며 파일은 변경하지 않았습니다. Home 데이터가 준비되면 사진이 아직 없어도 텍스트와 구조를 표시합니다. loaded Hero / TOP5 / 테마 디자인과 추천 scoring은 변경하지 않았습니다.

## 이번 변경 파일

- Viewfinder/Views/Home/HomeFeedView.swift
- Viewfinder/Models/HomeRecommendationsViewModel.swift
- Viewfinder/Services/RecommendationLocationReader.swift
- Viewfinder/ContentView.swift
- Tools/HomeContextRegression.swift
- Tools/HomeLoadingUX.md

## 검증 범위

26개 코드 회귀 검사 통과: 기존 지역/위치/캐시 검사에 cached refreshing, 2시간 경과 캐시 우선 표시, refresh 완료 loaded 복귀를 추가했습니다. 실제 스크린샷 비교, VoiceOver 및 실기기 애니메이션 확인은 수행하지 않았습니다.
