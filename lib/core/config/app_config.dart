class AppConfig {
  static const String appName = 'Partition App';
  static const String appVersion = '1.0.0';
  
  // 백엔드 API (Spring)
  static const String baseUrl = 'https://api.partition.site/api';
  /// Swagger UI (API 문서)
  static const String swaggerUiUrl =
      'https://api.partition.site/swagger-ui/index.html';
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // API 엔드포인트
  static const String loginEndpoint = '/auth/login';
  static const String logoutEndpoint = '/auth/logout';
  static const String registerEndpoint = '/auth/register';
  static const String kakaoLoginEndpoint = '/auth/kakao';
  static const String householdsEndpoint = '/households';
  /// 현재 로그인 사용자 그룹 — GET 조회 · DELETE 그룹 나가기·탈퇴
  static const String householdsMeEndpoint = '/households/me';
  /// 그룹 이름 변경
  static const String householdsNameEndpoint = '/households/name';
  static const String householdsJoinEndpoint = '/households/join';
  /// 그룹(가구) 멤버 목록 (정산 시 참여자 선택용)
  static const String householdMembersEndpoint = '/households/members';
  /// 그룹 리더 위임 (방장만). 본문 예: `{ "targetUserId": number }`
  static const String householdsLeaderEndpoint = '/households/leader';
  /// PATCH 등에 사용. GET 내 정보 조회는 앱에서 호출하지 않음(백엔드 미구현).
  static const String updateUserNameEndpoint = '/users/me';
  /// FCM 디바이스 토큰 등록·갱신 (PATCH JSON `fcmToken`)
  static const String userFcmTokenEndpoint = '/users/me/fcm-token';
  static const String userPreferencesEndpoint = '/users/me/preferences';
  static const String monthlyCalendarEndpoint = '/calendars/monthly';
  static const String dailyCalendarEndpoint = '/calendars/daily';
  static const String schedulesEndpoint = '/schedules';
  static const String scheduleDetailEndpoint = '/schedules/{scheduleId}';
  static const String choresAutoAssignEndpoint = '/chores/auto-assign';
  /// 내 알림 목록 (GET)
  static const String alarmsEndpoint = '/alarms';
  /// 특정 알림 읽음 (PATCH)
  static String alarmsReadPath(int alarmId) => '/alarms/$alarmId/read';
  /// 특정 알림 삭제 (DELETE)
  static String alarmsItemPath(int alarmId) => '/alarms/$alarmId';
  /// 집안일 완료 처리 (`PATCH`, Path Variable `choreId`, 본문 없음)
  static const String choreCompleteEndpoint = '/chores/{choreId}/complete';
  /// 집안일 완료 해제 등 (본문 `{ isCompleted: false }`) — 백엔드 명세에 따라 유지·변경
  static const String choreDetailEndpoint = '/chores/{choreId}';
  /// 공동 구매(공용 소비) 물품 카테고리 — household 생성 시 시드된 대·소분류
  static const String suppliesCategoriesEndpoint = '/supplies/categories';
  /// 공동 구매 물품 수동 등록
  static const String suppliesPurchasesEndpoint = '/supplies/purchases';
  /// 영수증 이미지 AI 분석 (POST multipart `image`)
  static const String suppliesPurchasesImageEndpoint = '/supplies/purchases/image';
  /// 공용 구매 물품 정산 **목록** 조회 (GET `startDate`·`endDate`)
  static const String suppliesPurchasesSettlementListEndpoint =
      '/supplies/settlement/purchases';
  /// 공용 구매 물품 정산 **요청** — `purchaseIds`, `memberIds`
  static const String suppliesSettlementRequestEndpoint = '/supplies/settlement';

  /// 정산 완료 처리 (PATCH, Path: settlementId)
  static String suppliesSettlementConfirmPath(int settlementId) =>
      '/supplies/settlement/$settlementId/confirm';

  /// 정산 상세 조회 (GET)
  static String suppliesSettlementDetailPath(int settlementId) =>
      '/supplies/settlement/$settlementId';

  /// 공과금 **종류** 조회 (`GET`)
  static const String billsCategoriesEndpoint = '/bills/categories';
  /// 공과금 목록(GET `startDate`·`endDate`) · 수동 추가(POST)
  static const String billsEndpoint = '/bills';
  /// 공과금 **납부 기록** 조회 (GET `startDate`, `endDate`)
  static const String billsPaymentsEndpoint = '/bills/payments';
  /// 공과금 정산 대상 목록 (GET `startDate`·`endDate`)
  static const String billsSettlementListEndpoint = '/bills/settlement/list';
  /// 공과금 정산 요청 (POST `{ paymentIds, memberIds }`)
  static const String billsSettlementRequestEndpoint = '/bills/settlement';
  /// 정산 상세 조회 (GET)
  static String billsSettlementDetailPath(int settlementId) =>
      '/bills/settlement/$settlementId';
  /// 정산 완료 처리 (PATCH, Path: settlementId)
  static String billsSettlementConfirmPath(int settlementId) =>
      '/bills/settlement/$settlementId/confirm';
  /// 정산 요청된 공과금 목록 (GET, 본문 없음)
  static const String billsSettlementRequestedEndpoint =
      '/bills/settlement/requested';
  /// 수정(PATCH)·삭제(DELETE) — `{billId}` 치환
  static String billsBillPath(int billId) => '/bills/$billId';
  /// 변동 공과금 이번 달 금액 입력 PATCH
  static String billsBillPaymentAmountPath(int billId, String yearMonth) =>
      '/bills/$billId/payments/$yearMonth/amount';
  /// 납부 기록 정산 상태 토글 PATCH
  static String billsPaymentSettlementStatusPath(int paymentId) =>
      '/bills/payments/$paymentId/settlement-status';

  /// 예약 목록 조회·예약 등록 (`GET`·`POST`, 쿼리 `startDate`·`endDate` / 본문 `itemId`·시간)
  static const String reservationsEndpoint = '/reservations';

  /// PARTITION_AI (FastAPI). Spring에서 받은 액세스 토큰을 그대로 Bearer로 전달합니다.
  /// Swagger: https://ai.partition.site/docs
  static const String insightsAiBaseUrl = 'https://ai.partition.site';

  /// `POST /api/insights/query` — 절대 URL (Dio가 [baseUrl]과 합치지 않음)
  static String get insightsAiQueryUrl =>
      '$insightsAiBaseUrl/api/insights/query';

  /// `POST /api/insights/query-voice` (FastAPI 경로가 다르면 여기만 수정)
  static String get insightsAiQueryVoiceUrl =>
      '$insightsAiBaseUrl/api/insights/query-voice';

  /// Spring 전용(레거시). 인사이트는 [insightsAiQueryUrl] 사용.
  static const String insightsQueryEndpoint = '/insights/query';

  /// Spring 전용(레거시).
  static const String insightsQueryVoiceEndpoint = '/insights/query-voice';

  /// 기간별 집안일·공용소비·예약 리포트·공과금 변동 (GET `startDate`·`endDate`)
  static const String reportsEndpoint = '/reports';

  /// 정산 완료 공용물품·공과금 리포트 (GET `startDate`·`endDate`, yyyy-MM-dd)
  static const String reportsSettlementEndpoint = '/reports/settlement';

  /// 예약 대상 — GET 목록, POST 추가, DELETE 시 본문 `{ itemIds: [...] }`
  static const String reservationsItemsEndpoint = '/reservations/items';
  /// PATCH — `{ name }` 로 단일 예약 대상 수정
  static String reservationsItemPath(int itemId) => '/reservations/items/$itemId';

  // ── 카카오 지도 REST API ──────────────────────────────────────────────────
  /// 카카오 Local API REST 키 (주소 검색·역지오코딩 HTTP 호출용)
  /// https://developers.kakao.com → 내 애플리케이션 → 앱 설정 → 앱 키 → REST API 키
  ///
  /// 빌드 시 덮어쓰기: `flutter run --dart-define=KAKAO_REST_API_KEY=본인키`
  static const String kakaoRestApiKey = String.fromEnvironment(
    'KAKAO_REST_API_KEY',
    defaultValue: '6b6d3822b9ffb4d757eef35051d729d3',
  );

  // ── 귀가 공유 (위치 기반 알림) ────────────────────────────────────────────
  /// 위치 공유 동의 저장/조회 (POST `{ agreed: bool }` · GET)
  static const String locationConsentEndpoint = '/households/location-consent';
  /// 집 위치 저장(POST)·조회(GET). 조회 명세 경로 `/api/households/home-loc`
  static const String homeLocationEndpoint = '/households/home-loc';
  /// 집 근처 진입 이벤트 — POST 전송 · GET 룸메이트 귀가 현황 조회
  static const String nearHomeEventEndpoint = '/households/location-events/near-home';

  // 로컬 저장소 키
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String userRoleKey = 'user_role';
  static const String themeKey = 'theme_mode';
}

