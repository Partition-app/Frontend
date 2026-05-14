import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/partition/services/geocoding_service.dart';
import 'package:partition_app/features/partition/services/home_share_service.dart';

/// 귀가 공유 상태 및 위치 감시 로직을 관리합니다.
///
/// 동작 흐름:
///   1. [initialize] — 앱 시작 시 저장된 설정 복원 및 위치 감시 재개
///   2. [enableSharing] — 위치 권한 요청 후 실시간 위치 스트림 시작
///   3. [disableSharing] — 위치 스트림 중단
///   4. [setHomeFromCurrentLocation] — 현재 GPS 좌표를 집 위치로 저장
class HomeShareProvider extends ChangeNotifier {
  static const Duration _cooldown = Duration(minutes: 30);
  static const Duration _roommateNearHomeTtl = Duration(minutes: 30);
  static const Duration _roommateNearHomePollInterval = Duration(seconds: 60);
  static const double _defaultRadius = 300.0;

  bool _isEnabled = false;
  bool _isNearHome = false;
  bool _roommateNearHome = false;
  List<String> _nearHomeRoommateNames = const [];
  bool _isLoading = false;

  ({double lat, double lng, double radius})? _homeLocation;
  String? _homeAddress;
  DateTime? _lastNotifiedAt;
  StreamSubscription<Position>? _positionSub;
  Timer? _roommateNearHomeExpiryTimer;
  Timer? _roommateNearHomePollTimer;

  final HomeShareService _service = HomeShareService();

  /// 서버 연동 실패 시 화면에서 스낵바 등으로 표시할 메시지 (한 번 소비 권장).
  String? _serverNotice;
  String? get serverNotice => _serverNotice;

  void clearServerNotice() {
    if (_serverNotice == null) return;
    _serverNotice = null;
    notifyListeners();
  }

  void _setServerNotice(String message) {
    if (_serverNotice == message) return;
    _serverNotice = message;
    notifyListeners();
  }

  bool get isEnabled => _isEnabled;
  bool get isNearHome => _isNearHome;
  /// 다른 룸메이트의 집 근처 진입 여부 (FCM·서버 조회)
  bool get roommateNearHome => _roommateNearHome;
  /// 집 근처에 있는 룸메이트 이름 (본인 제외)
  List<String> get nearHomeRoommateNames => _nearHomeRoommateNames;
  String get roommateNearHomeBannerText {
    if (!_roommateNearHome) return '룸메이트가 집 근처에 없어요.';
    if (_nearHomeRoommateNames.isEmpty) return '룸메이트가 집 근처에 있어요.';
    return '${_nearHomeRoommateNames.join(', ')}님이 집 근처에 있어요.';
  }
  bool get isLoading => _isLoading;
  ({double lat, double lng, double radius})? get homeLocation => _homeLocation;
  String? get homeAddress => _homeAddress;

  /// 저장된 상태를 로드하고 필요 시 위치 감시를 재개합니다.
  Future<void> initialize() async {
    _isEnabled = StorageService.getSharingEnabled();
    _homeLocation = StorageService.getHomeLocation();
    _homeAddress = StorageService.getHomeAddress();
    _lastNotifiedAt = StorageService.getLastNearHomeNotification();

    // 주소가 없지만 좌표가 있으면 역지오코딩으로 주소 복원
    if (_homeAddress == null && _homeLocation != null) {
      final loc = _homeLocation!;
      final address = await GeocodingService.reverseGeocode(loc.lat, loc.lng);
      if (address != null) {
        _homeAddress = address;
        await StorageService.setHomeAddress(address);
      }
    }

    if (_isEnabled && _homeLocation != null) {
      await _startLocationWatch();
    }
    _restoreRoommateNearHomeFromStorage();
    await refreshRoommateNearHomeFromServer();
    _startRoommateNearHomePolling();
    notifyListeners();
  }

  /// GET `/households/location-events/near-home`으로 룸메이트 귀가 배너를 갱신합니다.
  Future<void> refreshRoommateNearHomeFromServer() async {
    try {
      final statuses = await _service.fetchRoommateNearHomeStatus();
      final myId = int.tryParse(await StorageService.getUserId() ?? '');
      final nearOthers = statuses.where((s) {
        if (!s.isNearHome) return false;
        if (myId != null && myId > 0 && s.userId == myId) return false;
        return true;
      }).toList();
      _setRoommateNearHomeFromServer(
        near: nearOthers.isNotEmpty,
        names: nearOthers.map((s) => s.name).where((n) => n.isNotEmpty).toList(),
      );
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 룸메이트 귀가 현황 조회 실패: $e');
    }
  }

  void _startRoommateNearHomePolling() {
    _roommateNearHomePollTimer?.cancel();
    _roommateNearHomePollTimer = Timer.periodic(
      _roommateNearHomePollInterval,
      (_) => unawaited(refreshRoommateNearHomeFromServer()),
    );
  }

  void _setRoommateNearHomeFromServer({
    required bool near,
    required List<String> names,
  }) {
    final namesChanged = !_listEquals(_nearHomeRoommateNames, names);
    if (_roommateNearHome == near && !namesChanged) return;

    _roommateNearHome = near;
    _nearHomeRoommateNames = List.unmodifiable(names);

    if (near) {
      unawaited(StorageService.setRoommateNearHomeAt(DateTime.now()));
      _scheduleRoommateNearHomeExpiry();
    } else {
      _roommateNearHomeExpiryTimer?.cancel();
    }
    notifyListeners();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// FCM `NEAR_HOME_ARRIVAL` 수신 시 알림 패널 상단 배너를 갱신합니다.
  void applyRoommateNearHomeEvent() {
    _roommateNearHome = true;
    unawaited(StorageService.setRoommateNearHomeAt(DateTime.now()));
    _scheduleRoommateNearHomeExpiry();
    unawaited(refreshRoommateNearHomeFromServer());
    notifyListeners();
  }

  /// 위치 권한을 확인하고 귀가 공유를 활성화합니다.
  /// [true] 반환 시 성공, [false] 반환 시 권한 거부 등으로 실패.
  Future<bool> enableSharing() async {
    if (_isLoading || _isEnabled) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final bool granted = await _ensureLocationPermission();
      if (!granted) return false;

      await _startLocationWatch();
      _isEnabled = true;
      await StorageService.setSharingEnabled(true);

      try {
        await _service.saveLocationConsent(agreed: true);
      } on ApiException catch (e) {
        debugPrint('[HomeShare] 동의 서버 저장 실패: $e');
        _setServerNotice(e.message);
      }

      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 귀가 공유를 비활성화하고 위치 감시를 중단합니다.
  Future<void> disableSharing() async {
    _stopLocationWatch();
    _isEnabled = false;
    _isNearHome = false;
    await StorageService.setSharingEnabled(false);

    try {
      await _service.saveLocationConsent(agreed: false);
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 동의 해제 서버 저장 실패: $e');
      _setServerNotice(e.message);
    }

    notifyListeners();
  }

  /// 현재 GPS 위치를 집 위치로 설정하고 저장합니다.
  /// [true] 반환 시 성공.
  Future<bool> setHomeFromCurrentLocation() async {
    _isLoading = true;
    notifyListeners();
    try {
      final bool granted = await _ensureLocationPermission();
      if (!granted) return false;

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _homeLocation = (
        lat: pos.latitude,
        lng: pos.longitude,
        radius: _defaultRadius,
      );
      await StorageService.setHomeLocation(
        pos.latitude,
        pos.longitude,
        _defaultRadius,
      );

      // 역지오코딩으로 주소 저장 (실패 시 null 유지 — 다이얼로그에서 검색 유도)
      final address =
          await GeocodingService.reverseGeocode(pos.latitude, pos.longitude);
      if (address != null) {
        _homeAddress = address;
        await StorageService.setHomeAddress(address);
      }

      try {
        await _service.saveHomeLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          radiusMeters: _defaultRadius.round(),
        );
      } on ApiException catch (e) {
        debugPrint('[HomeShare] 집 위치 서버 저장 실패: $e');
        _setServerNotice(e.message);
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[HomeShare] 현재 위치 가져오기 실패: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 좌표와 주소를 지정해 집 위치를 설정합니다 (주소 검색 결과 선택 시 사용).
  Future<bool> setHomeFromCoordinates(
      double lat, double lng, String address) async {
    _isLoading = true;
    notifyListeners();
    try {
      _homeLocation = (lat: lat, lng: lng, radius: _defaultRadius);
      _homeAddress = address;
      await StorageService.setHomeLocation(lat, lng, _defaultRadius);
      await StorageService.setHomeAddress(address);

      try {
        await _service.saveHomeLocation(
          lat: lat,
          lng: lng,
          radiusMeters: _defaultRadius.round(),
        );
      } on ApiException catch (e) {
        debugPrint('[HomeShare] 집 위치 서버 저장 실패: $e');
        _setServerNotice(e.message);
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[HomeShare] setHomeFromCoordinates 실패: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 주소 문자열만 업데이트합니다 (좌표는 유지).
  Future<void> updateHomeAddress(String address) async {
    _homeAddress = address;
    await StorageService.setHomeAddress(address);
    notifyListeners();
  }

  /// 집 위치를 초기화합니다.
  Future<void> clearHomeLocation() async {
    _homeLocation = null;
    _homeAddress = null;
    await StorageService.clearHomeLocation();
    notifyListeners();
  }

  // ── 내부 메서드 ────────────────────────────────────────────────────────────

  void _restoreRoommateNearHomeFromStorage() {
    final at = StorageService.getRoommateNearHomeAt();
    if (at == null) {
      _roommateNearHome = false;
      return;
    }
    final elapsed = DateTime.now().difference(at);
    if (elapsed >= _roommateNearHomeTtl) {
      _roommateNearHome = false;
      return;
    }
    _roommateNearHome = true;
    _scheduleRoommateNearHomeExpiry(remaining: _roommateNearHomeTtl - elapsed);
  }

  void _scheduleRoommateNearHomeExpiry({Duration? remaining}) {
    _roommateNearHomeExpiryTimer?.cancel();
    final wait = remaining ?? _roommateNearHomeTtl;
    if (wait <= Duration.zero) {
      _roommateNearHome = false;
      return;
    }
    _roommateNearHomeExpiryTimer = Timer(wait, () {
      _roommateNearHome = false;
      notifyListeners();
    });
  }

  Future<bool> _ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _startLocationWatch() async {
    _positionSub?.cancel();

    // distanceFilter: 50m 이동 시에만 콜백 — 배터리 절약
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 50,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      _onPosition,
      onError: (Object e) {
        debugPrint('[HomeShare] 위치 스트림 오류: $e');
      },
    );
  }

  void _stopLocationWatch() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _onPosition(Position position) {
    final home = _homeLocation;
    if (home == null) return;

    final double dist = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      home.lat,
      home.lng,
    );

    final bool wasNear = _isNearHome;
    final bool isNear = dist <= home.radius;
    if (isNear == wasNear) return;

    _isNearHome = isNear;

    // 집 반경에 처음 진입할 때만 알림 전송
    if (_isNearHome) {
      _maybeNotify();
    }

    notifyListeners();
  }

  void _maybeNotify() {
    if (_lastNotifiedAt != null &&
        DateTime.now().difference(_lastNotifiedAt!) < _cooldown) {
      return;
    }
    _lastNotifiedAt = DateTime.now();
    StorageService.setLastNearHomeNotification(_lastNotifiedAt!);

    _service.sendNearHomeEvent().catchError((Object e) {
      debugPrint('[HomeShare] 집 근처 알림 전송 실패: $e');
    });
  }

  @override
  void dispose() {
    _roommateNearHomeExpiryTimer?.cancel();
    _roommateNearHomePollTimer?.cancel();
    _stopLocationWatch();
    super.dispose();
  }
}
