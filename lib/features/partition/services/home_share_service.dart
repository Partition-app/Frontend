import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';

/// 귀가 공유 — 집 근처 도착 이벤트 전송 및 위치 공유 동의 관리
///
/// Spring API: `POST /households/location-consent`, `home-location`,
/// `location-events/near-home` ([AppConfig] baseUrl에 `/api` 포함).
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
    if (result is! Map<String, dynamic>) return null;
    final agreed = result['agreed'];
    if (agreed is bool) return agreed;
    return null;
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

  /// GET `/households/home-location` — 서버에 저장된 집 좌표.
  Future<({double lat, double lng, double radius})?> fetchHomeLocation() async {
    try {
      final response = await _apiClient.get(AppConfig.homeLocationEndpoint);
      return _parseHomeLocation(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioError(e);
    }
  }

  ({double lat, double lng, double radius})? _parseHomeLocation(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['isSuccess'] != true) return null;
    final result = data['result'];
    if (result is! Map<String, dynamic>) return null;
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final radius = (result['radius'] as num?)?.toDouble() ?? 300.0;
    return (lat: lat, lng: lng, radius: radius);
  }
}
