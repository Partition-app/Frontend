# Partition App - 프로젝트 구조 및 기능 설계서

## 목차

1. [프로젝트 개요](#프로젝트-개요)
2. [전체 파일 구조](#전체-파일-구조)
3. [아키텍처 패턴](#아키텍처-패턴)
4. [핵심 모듈 상세 설계](#핵심-모듈-상세-설계)
5. [데이터 흐름도](#데이터-흐름도)
6. [API 연동 구조](#api-연동-구조)
7. [상태 관리 구조](#상태-관리-구조)

---

## 프로젝트 개요

**Partition App**은 룸메이트 간 공간 관리 및 일정 공유를 위한 Flutter 기반 모바일 애플리케이션입니다.

### 주요 기능

- 사용자 인증 (이메일/비밀번호, 카카오 로그인)
- 그룹(가구) 생성 및 참여
- 일정 관리 및 캘린더 조회
- 파티션(공간) 관리
- 집안일 선호도 설문

### 기술 스택

- **프레임워크**: Flutter (Dart)
- **상태 관리**: Provider
- **HTTP 클라이언트**: Dio
- **로컬 저장소**: SharedPreferences, Flutter Secure Storage
- **인증**: 카카오 SDK
- **JSON 직렬화**: json_serializable

---

## 전체 파일 구조

```
Frontend/lib/
├── main.dart                          # 앱 진입점
│
├── core/                              # 핵심 설정 및 공통 기능
│   ├── config/
│   │   └── app_config.dart           # 앱 설정 및 API 엔드포인트
│   ├── network/
│   │   ├── api_client.dart           # HTTP 클라이언트 (Dio 기반)
│   │   └── api_exception.dart        # API 예외 처리
│   ├── platform/
│   │   └── platform_config.dart      # 플랫폼별 설정
│   ├── providers/
│   │   └── app_providers.dart        # 전역 Provider 설정
│   ├── router/
│   │   └── app_router.dart           # 라우팅 설정
│   ├── storage/
│   │   └── storage_service.dart      # 로컬 저장소 관리
│   └── theme/
│       └── app_theme.dart             # 앱 테마 설정
│
├── features/                          # 기능별 모듈
│   ├── auth/                         # 인증 기능
│   │   ├── models/                   # 데이터 모델
│   │   │   ├── auth_response_model.dart
│   │   │   ├── user_model.dart
│   │   │   ├── kakao_auth_response_model.dart
│   │   │   ├── household_response_model.dart
│   │   │   ├── preference_response_model.dart
│   │   │   └── update_name_response_model.dart
│   │   ├── providers/
│   │   │   └── auth_provider.dart    # 인증 상태 관리
│   │   ├── screens/                  # UI 화면
│   │   │   ├── login_screen.dart
│   │   │   ├── onboarding_survey_screen.dart
│   │   │   ├── group_selection_screen.dart
│   │   │   ├── enter_group_code_screen.dart
│   │   │   ├── create_group_screen.dart
│   │   │   ├── confirm_group_name_screen.dart
│   │   │   ├── group_created_screen.dart
│   │   │   └── preference_survey_screen.dart
│   │   └── services/                 # 비즈니스 로직
│   │       ├── auth_service.dart
│   │       └── kakao_auth_service.dart
│   │
│   ├── partition/                    # 파티션 관리 기능
│   │   ├── models/
│   │   │   ├── partition_model.dart
│   │   │   ├── calendar_response_model.dart
│   │   │   ├── daily_calendar_response_model.dart
│   │   │   └── schedule_response_model.dart
│   │   ├── providers/
│   │   │   └── partition_provider.dart
│   │   ├── screens/
│   │   │   ├── partition_main_screen.dart
│   │   │   ├── partition_home_screen.dart
│   │   │   ├── partition_list_screen.dart
│   │   │   ├── partition_detail_screen.dart
│   │   │   ├── partition_board_screen.dart
│   │   │   ├── partition_management_screen.dart
│   │   │   ├── partition_report_screen.dart
│   │   │   └── partition_shared_expense_screen.dart
│   │   └── services/
│   │       ├── partition_service.dart
│   │       └── calendar_service.dart
│   │
│   └── settings/                      # 설정 기능
│       └── screens/
│           └── settings_screen.dart
│
└── shared/                            # 공통 위젯 및 유틸리티
    ├── utils/
    │   ├── constants.dart
    │   ├── validators.dart
    │   ├── debug_helper.dart
    │   └── app_colors.dart
    └── widgets/
        ├── schedule_registration_modal.dart
        ├── home_calendar_widget.dart
        ├── glassmorphism_button.dart
        ├── glassmorphism_widget.dart
        ├── frosted_panel.dart
        ├── chore_assignment_modal.dart
        ├── ios_loading_indicator.dart
        ├── primary_button.dart
        └── not_found_screen.dart
```

---

## 아키텍처 패턴

### Feature-First 구조

각 기능을 독립적인 모듈로 구성하여 유지보수성과 확장성을 높였습니다.

### 레이어 구조

```
┌─────────────────────────────────────┐
│         Presentation Layer           │  (Screens, Widgets)
├─────────────────────────────────────┤
│         Business Logic Layer         │  (Providers, Services)
├─────────────────────────────────────┤
│         Data Layer                   │  (Models, API Client)
├─────────────────────────────────────┤
│         Infrastructure Layer        │  (Storage, Network, Config)
└─────────────────────────────────────┘
```

---

## 핵심 모듈 상세 설계

### 1. Core 모듈

#### 1.1 AppConfig (`core/config/app_config.dart`)

**역할**: 앱 전역 설정 및 API 엔드포인트 관리

**주요 상수**:

```dart
- baseUrl: 백엔드 API 기본 URL
- connectTimeout: 연결 타임아웃 (30초)
- receiveTimeout: 수신 타임아웃 (30초)
- loginEndpoint: '/auth/login'
- registerEndpoint: '/auth/register'
- kakaoLoginEndpoint: '/auth/kakao'
- partitionsEndpoint: '/partitions'
- householdsEndpoint: '/households'
- monthlyCalendarEndpoint: '/calendars/monthly'
- dailyCalendarEndpoint: '/calendars/daily'
- schedulesEndpoint: '/schedules'
- userPreferencesEndpoint: '/users/me/preferences'
```

#### 1.2 ApiClient (`core/network/api_client.dart`)

**역할**: HTTP 통신을 위한 Dio 기반 클라이언트

**주요 함수**:

```dart
ApiClient()
  - 생성자: Dio 인스턴스 초기화 및 인터셉터 설정
  - onRequest: 요청 전 토큰 자동 추가, 로깅
  - onResponse: 응답 로깅
  - onError: 에러 로깅

Future<Response> get(String path, {queryParameters, options})
  - GET 요청 처리
  - 파라미터: path, queryParameters, options
  - 반환: Response 객체

Future<Response> post(String path, {data, queryParameters, options})
  - POST 요청 처리
  - 파라미터: path, data, queryParameters, options
  - 반환: Response 객체

Future<Response> put(String path, {data, queryParameters, options})
  - PUT 요청 처리

Future<Response> patch(String path, {data, queryParameters, options})
  - PATCH 요청 처리

Future<Response> delete(String path, {data, queryParameters, options})
  - DELETE 요청 처리
```

**동작 흐름**:

1. 요청 전: 공개 엔드포인트 확인 → 인증 필요 시 토큰 추가
2. 요청 로깅
3. Dio 요청 실행
4. 응답/에러 로깅
5. 결과 반환

#### 1.3 StorageService (`core/storage/storage_service.dart`)

**역할**: 로컬 저장소 관리 (SharedPreferences + Flutter Secure Storage)

**주요 함수**:

```dart
// 초기화
static Future<void> init()
  - SharedPreferences 인스턴스 초기화

// 토큰 관리 (Secure Storage)
static Future<bool> setToken(String token)
static Future<String?> getToken()
static Future<bool> removeToken()
static Future<bool> setRefreshToken(String refreshToken)
static Future<String?> getRefreshToken()
static Future<bool> removeRefreshToken()

// 사용자 정보 (SharedPreferences)
static Future<bool> setUserId(String userId)
static Future<String?> getUserId()
static Future<bool> setUserName(String name)
static Future<String?> getUserName()

// 온보딩 상태
static Future<bool> setOnboardingCompleted(bool completed)
static Future<bool> isOnboardingCompleted()

// 그룹 정보
static Future<bool> setHouseholdId(String householdId)
static Future<String?> getHouseholdId()

// 전체 삭제
static Future<bool> clear()
  - Secure Storage와 SharedPreferences 모두 삭제
```

**저장소 전략**:

- **Secure Storage**: 토큰 등 민감한 정보
- **SharedPreferences**: 사용자 ID, 이름, 온보딩 상태 등 일반 정보

#### 1.4 AppRouter (`core/router/app_router.dart`)

**역할**: 화면 라우팅 및 네비게이션 관리

**주요 라우트**:

```dart
- '/login': LoginScreen
- '/onboarding-survey': OnboardingSurveyScreen
- '/group-selection': GroupSelectionScreen
- '/enter-group-code': EnterGroupCodeScreen
- '/create-group': CreateGroupScreen
- '/confirm-group-name': ConfirmGroupNameScreen
- '/group-created': GroupCreatedScreen
- '/preference-survey': PreferenceSurveyScreen
- '/partitions': PartitionMainScreen (AuthGuard 적용)
- '/settings': SettingsScreen (AuthGuard 적용)
```

**주요 함수**:

```dart
static Route<dynamic> generateRoute(RouteSettings settings)
  - 라우트 이름에 따라 적절한 화면 반환
  - 인증이 필요한 화면은 _AuthGuard로 보호

class _AuthGuard extends StatefulWidget
  - 인증 상태 확인
  - 미인증 시 로그인 화면으로 리다이렉트
```

---

### 2. Auth 모듈 (인증)

#### 2.1 AuthService (`features/auth/services/auth_service.dart`)

**역할**: 인증 관련 API 호출 및 토큰 관리

**주요 함수**:

```dart
Future<AuthResponseModel> login(String email, String password)
  - 이메일/비밀번호 로그인
  - API: POST /auth/login
  - 응답: AuthResponseModel (token, user 정보)
  - 토큰 자동 저장

Future<AuthResponseModel> register({email, password, name})
  - 회원가입
  - API: POST /auth/register
  - 응답: AuthResponseModel
  - 토큰 자동 저장

Future<KakaoAuthResponseModel> loginWithKakao({kakaoAccessToken})
  - 카카오 로그인
  - API: POST /auth/kakao
  - 요청: { "kakaoAccessToken": string }
  - 응답: KakaoAuthResponseModel (accessToken, refreshToken, userRole)
  - 토큰 자동 저장

Future<UpdateNameResponseModel> updateUserName({name})
  - 사용자 이름 업데이트
  - API: PATCH /users/me
  - 요청: { "name": string }

Future<HouseholdResponseModel> createHousehold({name})
  - 그룹(가구) 생성
  - API: POST /households
  - 요청: { "name": string }
  - 응답: HouseholdResponseModel (code, name, id, role)

Future<PreferenceResponseModel> registerPreferences({preferences})
  - 선호도 등록
  - API: POST /users/me/preferences
  - 요청: { "preferences": [PreferenceItem] }

Future<UserModel?> getUserInfo()
  - 사용자 정보 조회
  - API: GET /users/me
  - 응답: UserModel 또는 null (에러 시)

Future<void> logout()
  - 로그아웃
  - StorageService.clear() 호출

Future<bool> isAuthenticated()
  - 인증 상태 확인
  - 토큰 존재 여부 확인
```

#### 2.2 KakaoAuthService (`features/auth/services/kakao_auth_service.dart`)

**역할**: 카카오 SDK를 통한 로그인 처리

**주요 함수**:

```dart
static Future<OAuthToken?> login()
  - 카카오 로그인 실행
  - 카카오톡 설치 여부 확인
  - 설치됨: 카카오톡 로그인 시도
  - 설치 안됨: 카카오계정 로그인
  - 실패 시 카카오계정 로그인으로 fallback
  - 반환: OAuthToken (accessToken 포함)

static Future<User?> getUserInfo()
  - 카카오 사용자 정보 조회
  - 카카오 SDK UserApi 사용
  - 반환: User 객체 (이메일, ID 등)
```

#### 2.3 AuthProvider (`features/auth/providers/auth_provider.dart`)

**역할**: 인증 상태 관리 (Provider 패턴)

**상태 변수**:

```dart
- UserModel? _user: 현재 로그인한 사용자
- bool _isLoading: 로딩 상태
- String? _errorMessage: 에러 메시지
```

**주요 함수**:

```dart
Future<bool> login(String email, String password)
  - 로그인 처리
  - AuthService.login() 호출
  - 성공 시 _user 업데이트
  - 반환: 성공 여부

Future<({bool success, String? userRole})> loginWithKakao({kakaoAccessToken})
  - 카카오 로그인 처리
  - AuthService.loginWithKakao() 호출
  - userRole 추출 및 반환
  - 반환: (success, userRole)

Future<bool> register({email, password, name})
  - 회원가입 처리
  - AuthService.register() 호출
  - 성공 시 _user 업데이트

Future<void> logout()
  - 로그아웃 처리
  - AuthService.logout() 호출
  - _user 초기화

Future<void> checkAuthStatus()
  - 인증 상태 확인
  - 토큰 존재 여부 확인
  - 없으면 _user 초기화
```

**데이터 흐름**:

```
Screen → AuthProvider → AuthService → ApiClient → Backend
                ↓
         상태 업데이트 (notifyListeners)
                ↓
         Screen 리빌드
```

---

### 3. Partition 모듈

#### 3.1 PartitionService (`features/partition/services/partition_service.dart`)

**역할**: 파티션 관련 API 호출

**주요 함수**:

```dart
Future<List<PartitionModel>> getPartitions()
  - 파티션 목록 조회
  - API: GET /partitions
  - 반환: PartitionModel 리스트

Future<PartitionModel> getPartitionById(String id)
  - 파티션 상세 조회
  - API: GET /partitions/{id}
  - 반환: PartitionModel

Future<PartitionModel> createPartition({name, description, type, size, status})
  - 파티션 생성
  - API: POST /partitions
  - 요청: { name, description, type, size, status }
  - 반환: 생성된 PartitionModel

Future<PartitionModel> updatePartition(String id, {name, description, type, size, usedSize, status})
  - 파티션 수정
  - API: PUT /partitions/{id}
  - 요청: 수정할 필드들
  - 반환: 수정된 PartitionModel

Future<void> deletePartition(String id)
  - 파티션 삭제
  - API: DELETE /partitions/{id}
```

#### 3.2 CalendarService (`features/partition/services/calendar_service.dart`)

**역할**: 캘린더 및 일정 관련 API 호출

**주요 함수**:

```dart
Future<CalendarResponseModel> getMonthlyCalendar({year, month})
  - 월간 캘린더 조회
  - API: GET /calendars/monthly?year={year}&month={month}
  - 반환: CalendarResponseModel
  - 결과: 날짜별 집안일/일정/공과금 개수

Future<DailyCalendarResponseModel> getDailyCalendar({date})
  - 일간 캘린더 상세 조회
  - API: GET /calendars/daily?date={YYYY-MM-DD}
  - 반환: DailyCalendarResponseModel
  - 결과: 해당 날짜의 상세 일정 목록

Future<ScheduleResponseModel> registerSchedule({content, date})
  - 일정 등록
  - API: POST /schedules
  - 요청: { "content": string, "date": "YYYY-MM-DD" }
  - 반환: ScheduleResponseModel
```

---

### 4. 주요 화면 (Screens)

#### 4.1 LoginScreen (`features/auth/screens/login_screen.dart`)

**역할**: 로그인 화면

**주요 함수**:

```dart
Future<void> _handleKakaoLogin()
  - 카카오 로그인 처리
  - KakaoAuthService.login() 호출
  - AuthProvider.loginWithKakao() 호출
  - userRole에 따라 라우팅:
    * LEADER/MEMBER → partitionMain
    * GUEST → onboardingSurvey
    * 없음 → _getTargetRoute() 사용

Future<String> _getTargetRoute()
  - 사용자 상태에 따른 라우트 결정
  - 1. 닉네임 확인 → 없으면 onboardingSurvey
  - 2. 그룹 확인 → 없으면 groupSelection
  - 3. 선호도 확인 → 없으면 preferenceSurvey
  - 4. 모두 완료 → partitionMain
```

**라우팅 로직**:

```
카카오 로그인 성공
  ↓
userRole 확인
  ↓
LEADER/MEMBER → 홈 화면
GUEST → 온보딩 화면
없음 → 기존 로직 (닉네임/그룹/선호도 확인)
```

#### 4.2 OnboardingSurveyScreen (`features/auth/screens/onboarding_survey_screen.dart`)

**역할**: 온보딩 설문 (닉네임 입력)

**주요 기능**:

- 사용자 이름 입력
- AuthService.updateUserName() 호출
- 다음 화면으로 이동

#### 4.3 PreferenceSurveyScreen (`features/auth/screens/preference_survey_screen.dart`)

**역할**: 집안일 선호도 설문

**주요 기능**:

- 집안일 타입별 선호도 점수 입력 (1-5점)
- AuthService.registerPreferences() 호출
- 온보딩 완료 처리

#### 4.4 PartitionHomeScreen (`features/partition/screens/partition_home_screen.dart`)

**역할**: 파티션 홈 화면

**주요 기능**:

- 캘린더 위젯 표시
- 일정 등록 모달 호출
- CalendarService를 통한 일정 등록

---

### 5. 공통 위젯 (Shared Widgets)

#### 5.1 ScheduleRegistrationModal (`shared/widgets/schedule_registration_modal.dart`)

**역할**: 일정 등록 모달

**주요 함수**:

```dart
Future<void> _handleRegister()
  - 일정 등록 처리
  - 입력 검증 (내용 비어있으면 에러)
  - CalendarService.registerSchedule() 호출
  - 성공 시 모달 닫기 및 스낵바 표시
  - 실패 시 에러 메시지 표시

String _formatDateToApi(DateTime date)
  - 날짜를 "YYYY-MM-DD" 형식으로 변환
```

**데이터 흐름**:

```
사용자 입력 → 검증 → CalendarService.registerSchedule()
                              ↓
                        API 호출 (POST /schedules)
                              ↓
                        성공/실패 처리
                              ↓
                        UI 업데이트
```

#### 5.2 HomeCalendarWidget (`shared/widgets/home_calendar_widget.dart`)

**역할**: 홈 화면 캘린더 위젯

**주요 기능**:

- 월간 캘린더 표시
- 날짜별 집안일/일정/공과금 개수 표시
- 날짜 선택 시 일정 등록 모달 호출

---

## 데이터 흐름도

### 로그인 플로우

```
[LoginScreen]
    ↓
[KakaoAuthService.login()]
    ↓ (카카오 SDK)
[OAuthToken 획득]
    ↓
[AuthProvider.loginWithKakao()]
    ↓
[AuthService.loginWithKakao()]
    ↓
[ApiClient.post('/auth/kakao')]
    ↓
[Backend API]
    ↓
[KakaoAuthResponseModel]
    ↓
[StorageService.setToken()]
    ↓
[userRole 확인]
    ↓
[라우팅 결정]
    ├─ LEADER/MEMBER → PartitionMainScreen
    └─ GUEST → OnboardingSurveyScreen
```

### 일정 등록 플로우

```
[ScheduleRegistrationModal]
    ↓ (사용자 입력)
[입력 검증]
    ↓
[CalendarService.registerSchedule()]
    ↓
[ApiClient.post('/schedules')]
    ↓
[Backend API]
    ↓
[ScheduleResponseModel]
    ↓
[성공 처리]
    ├─ 모달 닫기
    └─ 스낵바 표시
```

### 캘린더 조회 플로우

```
[HomeCalendarWidget]
    ↓
[CalendarService.getMonthlyCalendar()]
    ↓
[ApiClient.get('/calendars/monthly')]
    ↓
[Backend API]
    ↓
[CalendarResponseModel]
    ↓
[UI 업데이트]
```

---

## API 연동 구조

### API 엔드포인트 목록

#### 인증 (Auth)

- `POST /auth/login` - 이메일/비밀번호 로그인
- `POST /auth/register` - 회원가입
- `POST /auth/kakao` - 카카오 로그인
- `PATCH /users/me` - 사용자 정보 수정
- `GET /users/me` - 사용자 정보 조회

#### 그룹 (Household)

- `POST /households` - 그룹 생성
- `POST /users/me/preferences` - 선호도 등록

#### 캘린더 (Calendar)

- `GET /calendars/monthly?year={year}&month={month}` - 월간 캘린더
- `GET /calendars/daily?date={date}` - 일간 캘린더
- `POST /schedules` - 일정 등록

#### 파티션 (Partition)

- `GET /partitions` - 파티션 목록
- `GET /partitions/{id}` - 파티션 상세
- `POST /partitions` - 파티션 생성
- `PUT /partitions/{id}` - 파티션 수정
- `DELETE /partitions/{id}` - 파티션 삭제

### API 요청/응답 구조

#### 공통 응답 형식

```json
{
  "isSuccess": boolean,
  "code": string,
  "message": string,
  "result": object | array | null,
  "error": string | null
}
```

#### 인증 헤더

```
Authorization: Bearer {accessToken}
```

### 에러 처리

- `ApiException`: API 에러를 통일된 형식으로 변환
- `ApiClient.onError`: 모든 에러 로깅
- 각 Service에서 `ApiException.fromDioError()` 사용

---

## 상태 관리 구조

### Provider 패턴 사용

#### 전역 Provider

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => PartitionProvider()),
  ],
)
```

#### AuthProvider

- **상태**: `_user`, `_isLoading`, `_errorMessage`
- **메서드**: `login()`, `loginWithKakao()`, `register()`, `logout()`
- **사용 화면**: LoginScreen, 모든 인증 관련 화면

#### PartitionProvider

- **상태**: 파티션 목록, 선택된 파티션 등
- **메서드**: 파티션 CRUD 관련
- **사용 화면**: PartitionListScreen, PartitionDetailScreen 등

### 상태 업데이트 흐름

```
User Action
    ↓
Provider Method 호출
    ↓
Service 호출
    ↓
API 요청
    ↓
응답 처리
    ↓
Provider 상태 업데이트
    ↓
notifyListeners()
    ↓
UI 리빌드
```

---

## 주요 모델 (Models)

### AuthResponseModel

```dart
{
  token: string,
  user: UserModel
}
```

### KakaoAuthResponseModel

```dart
{
  isSuccess: boolean,
  code: string,
  message: string,
  result: {
    grantType: string,
    accessToken: string,
    refreshToken: string,
    accessTokenExpiresIn: number,
    userRole: "LEADER" | "MEMBER" | "GUEST"
  }
}
```

### CalendarResponseModel

```dart
{
  isSuccess: boolean,
  result: [
    {
      date: "YYYY-MM-DD",
      choreCount: number,
      scheduleCount: number,
      utilityBillsCount: number
    }
  ]
}
```

### ScheduleResponseModel

```dart
{
  isSuccess: boolean,
  code: string,
  message: string,
  result: object,
  error: string | null
}
```

---

## 보안 고려사항

### 토큰 관리

- Access Token: Flutter Secure Storage에 저장
- Refresh Token: Flutter Secure Storage에 저장
- 자동 토큰 추가: ApiClient 인터셉터에서 처리

### 공개 엔드포인트

- `/auth/login`
- `/auth/register`
- `/auth/kakao`

이 엔드포인트는 토큰 없이 접근 가능합니다.

---

## 향후 확장 계획

### 추가 예정 기능

1. 집안일 할당 기능
2. 공과금 관리
3. 알림 기능
4. 다크 모드 지원
5. 오프라인 모드

### 개선 사항

1. 토큰 갱신 자동화
2. 에러 핸들링 강화
3. 로딩 상태 개선
4. 캐싱 전략 도입

---

## 개발 가이드라인

### 파일 명명 규칙

- 화면: `*_screen.dart`
- 서비스: `*_service.dart`
- 프로바이더: `*_provider.dart`
- 모델: `*_model.dart`
- 위젯: `*_widget.dart` 또는 `*_modal.dart`

### 코드 구조

1. Import 문 (외부 → 내부 순서)
2. 클래스 정의
3. 생성자
4. Private 메서드
5. Public 메서드
6. Build 메서드 (위젯의 경우)

### 에러 처리

- 모든 API 호출은 try-catch로 감싸기
- ApiException으로 통일된 에러 처리
- 사용자에게 친화적인 에러 메시지 표시

---

## 참고 자료

### 주요 의존성

- `provider`: 상태 관리
- `dio`: HTTP 클라이언트
- `shared_preferences`: 로컬 저장소
- `flutter_secure_storage`: 보안 저장소
- `kakao_flutter_sdk_user`: 카카오 로그인
- `json_annotation`, `json_serializable`: JSON 직렬화
- `logger`: 로깅

### 개발 환경

- Flutter SDK: 최신 안정 버전
- Dart SDK: 3.0.0 이상
- iOS: 12.0 이상
- Android: API 21 이상

---

**작성일**: 2025년
**버전**: 1.0.0
**작성자**: Partition App 개발팀.
