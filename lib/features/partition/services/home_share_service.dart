import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';

/// 귀가 공유 — 집 근처 도착 이벤트 전송 및 위치 공유 동의 관리
///
/// Spring API: `POST·GET /households/location-consent`, `POST·GET /households/home-loc`,
/// `POST /households/location-events/near-home` ([AppConfig] baseUrl에 `/api` 포함).
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

  /// GET `/households/home-loc`
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
