import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';

/// 귀가 공유 — 집 근처 도착 이벤트 전송 및 위치 공유 동의 관리
///
/// Spring API: `POST·GET /households/location-consent`, `POST·GET /households/home-location`,
/// `POST·GET /households/location-events/near-home` ([AppConfig] baseUrl에 `/api` 포함).
class HomeShareService {
  final ApiClient _apiClient = ApiClient();

  void _ensureSuccess(dynamic data, String fallbackMessage) {
    if (data is! Map<String, dynamic>) {
      throw ApiException(message: fallbackMessage);
    }
    if (data['isSuccess'] != true) {
      throw ApiException(
        message: data['message']?.toString() ?? fallbackMessage,
      );
    }
  }

  /// 집 근처 진입 이벤트를 서버로 전송합니다.
  /// 서버는 같은 가구(household) 룸메이트에게 FCM 푸시를 발송합니다.
  Future<void> sendNearHomeEvent() async {
    try {
      final response = await _apiClient.post(
        AppConfig.nearHomeEventEndpoint,
        data: {'eventType': 'entered_home_area'},
      );
      _ensureSuccess(response.data, '집 근처 알림 전송에 실패했습니다.');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 위치 공유 동의 여부를 서버에 저장합니다.
  Future<void> saveLocationConsent({required bool agreed}) async {
    try {
      final response = await _apiClient.post(
        AppConfig.locationConsentEndpoint,
        data: {'agreed': agreed},
      );
      _ensureSuccess(response.data, '위치 공유 동의 저장에 실패했습니다.');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET `/households/location-consent` — 서버에 저장된 동의 여부.
  /// 미가입·미구현 등 404는 `null` (로컬 설정 유지용).
  Future<bool?> fetchLocationConsent() async {
    try {
      final response = await _apiClient.get(AppConfig.locationConsentEndpoint);
      return _parseAgreed(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioError(e);
    }
  }

  bool? _parseAgreed(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['isSuccess'] != true) return null;
    final result = data['result'];
    if (result == null) return null;
    if (result is! Map<String, dynamic>) return null;
    final agreed = result['agreed'];
    if (agreed is bool) return agreed;
    return null;
  }

  static bool _isHouseholdNoHomeLoc(dynamic data) {
    if (data is! Map<String, dynamic>) return false;
    final code = data['code']?.toString();
    return code == 'HOUSEHOLD_4005';
  }

  static bool _isHouseholdNotFound(dynamic data) {
    if (data is! Map<String, dynamic>) return false;
    return data['code']?.toString() == 'HOUSEHOLD_4001';
  }

  /// GET `/households/location-events/near-home` — 룸메이트별 집 근처 여부.
  Future<List<RoommateNearHomeStatus>> fetchRoommateNearHomeStatus() async {
    try {
      final response = await _apiClient.get(AppConfig.nearHomeEventEndpoint);
      return RoommateNearHomeStatus.listFromResponseBody(response.data);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 404 || _isHouseholdNotFound(body)) {
        return const [];
      }
      throw ApiException.fromDioError(e);
    }
  }

  /// 집 위치(위도·경도·반경 m)를 서버에 저장합니다.
  Future<void> saveHomeLocation({
    required double lat,
    required double lng,
    int radiusMeters = 300,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.homeLocationEndpoint,
        data: {
          'lat': lat,
          'lng': lng,
          'radius': radiusMeters,
        },
      );
      _ensureSuccess(response.data, '집 위치 저장에 실패했습니다.');
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET `/households/home-location`
  ///
  /// - [coordinates] 가 null이 아니면 등록 좌표
  /// - [coordinates] 가 null이면 서버 미등록(`result: null` 또는 404/`HOUSEHOLD_4005` 등)
  Future<HouseLocServerSnapshot> fetchHomeLocationSnapshot() async {
    try {
      final response = await _apiClient.get(AppConfig.homeLocationEndpoint);
      return HouseLocServerSnapshot.fromResponseBody(response.data);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 404 ||
          HomeShareService._isHouseholdNoHomeLoc(body)) {
        return const HouseLocServerSnapshot(coordinates: null);
      }
      throw ApiException.fromDioError(e);
    }
  }

  /// 서버 저장 좌표만 필요할 때 사용 (미등록·조회 실패는 null).
  Future<({double lat, double lng, double radius})?> fetchHomeLocation() async {
    try {
      final snap = await fetchHomeLocationSnapshot();
      return snap.coordinates;
    } on ApiException {
      return null;
    }
  }

}

/// 룸메이트 귀가 현황 GET 응답 항목.
class RoommateNearHomeStatus {
  const RoommateNearHomeStatus({
    required this.userId,
    required this.name,
    required this.isNearHome,
  });

  final int userId;
  final String name;
  final bool isNearHome;

  static List<RoommateNearHomeStatus> listFromResponseBody(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException(message: '룸메이트 귀가 현황 응답 형식이 올바르지 않습니다.');
    }
    if (data['isSuccess'] != true) {
      if (HomeShareService._isHouseholdNotFound(data)) return const [];
      throw ApiException(
        message:
            data['message']?.toString() ?? '룸메이트 귀가 현황 조회에 실패했습니다.',
      );
    }
    final items = _extractStatusItems(data['result']);
    final out = <RoommateNearHomeStatus>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final userId = _parseUserId(item);
      if (userId == null) continue;
      out.add(
        RoommateNearHomeStatus(
          userId: userId,
          name: _parseDisplayName(item),
          isNearHome: _parseNearHomeFlag(
            item['isNearHome'] ?? item['nearHome'] ?? item['near_home'],
          ),
        ),
      );
    }
    return out;
  }

  static List<dynamic> _extractStatusItems(dynamic result) {
    if (result == null) return const [];
    if (result is List) return result;
    if (result is Map<String, dynamic>) {
      final nested = result['members'] ??
          result['memberList'] ??
          result['roommates'] ??
          result['users'] ??
          result['userList'] ??
          result['statuses'] ??
          result['nearHomeMembers'];
      if (nested is List) return nested;
    }
    return const [];
  }

  static int? _parseUserId(Map<String, dynamic> item) {
    for (final key in ['userId', 'memberId', 'id']) {
      final id = (item[key] as num?)?.toInt();
      if (id != null && id > 0) return id;
    }
    return null;
  }

  static String _parseDisplayName(Map<String, dynamic> item) {
    for (final key in ['name', 'nickname', 'userName', 'memberName']) {
      final value = item[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _parseNearHomeFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'y';
  }
}

/// 집 위치 GET 응답을 로컬 동기화용으로 줄인 결과.
///
/// 서버 명세:
/// 등록 `{ householdId, lat, lng, radius }`, 미등록 `result: null` (HTTP 200)
/// 또는 `HOUSEHOLD_4005` 등록 없음 (HTTP 404).
class HouseLocServerSnapshot {
  const HouseLocServerSnapshot({required this.coordinates});

  /// null ⇒ 서버에 집 위치 없음 · 조회 불가 처리 시에도 호출측 로직에 맞게 사용.
  final ({double lat, double lng, double radius})? coordinates;

  static HouseLocServerSnapshot fromResponseBody(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException(message: '집 위치 조회 응답 형식이 올바르지 않습니다.');
    }
    if (data['isSuccess'] != true) {
      if (HomeShareService._isHouseholdNoHomeLoc(data)) {
        return const HouseLocServerSnapshot(coordinates: null);
      }
      throw ApiException(
        message:
            data['message']?.toString() ?? '집 위치 조회에 실패했습니다.',
      );
    }
    final dynamic result = data['result'];
    if (result == null) {
      return const HouseLocServerSnapshot(coordinates: null);
    }
    if (result is! Map<String, dynamic>) {
      throw ApiException(message: '집 위치 조회 결과 형식이 올바르지 않습니다.');
    }
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return const HouseLocServerSnapshot(coordinates: null);
    }
    final radius = (result['radius'] as num?)?.toDouble() ?? 300.0;
    return HouseLocServerSnapshot(
      coordinates: (lat: lat, lng: lng, radius: radius),
    );
  }
}
