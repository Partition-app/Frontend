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
  /// 집에 머무는 동안 주기적으로 POST를 재시도하는 체크 간격.
  /// 인스턴스 비용 절감을 위해 평소(앱 백그라운드 포함)에는 10분에 1번만 자기 위치를 보냄.
  static const Duration _atHomeRefreshInterval = Duration(minutes: 10);
  /// 마지막 전송 이후 이 시간이 지나면 서버 쿨다운(30분)이 끝났다고 보고 재전송.
  static const Duration _atHomeRefreshThreshold = Duration(minutes: 28);
  static const double _defaultRadius = 300.0;

  bool _isEnabled = false;
  bool _isNearHome = false;
  bool _roommateNearHome = false;
  List<RoommateNearHomeStatus> _nearHomeRoommates = const [];
  List<RoommateNearHomeStatus> _allRoommateStatuses = const [];
  bool _isLoading = false;

  ({double lat, double lng, double radius})? _homeLocation;
  String? _homeAddress;
  DateTime? _lastNotifiedAt;
  StreamSubscription<Position>? _positionSub;
  Timer? _roommateNearHomeExpiryTimer;
  /// 집에 머무는 동안 주기적으로 서버에 `entered_home_area`를 다시 보내는 타이머.
  Timer? _atHomeRefreshTimer;
  Future<void>? _ongoingInitialize;

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
  /// 집 근처에 있는 룸메이트 (본인 제외)
  List<RoommateNearHomeStatus> get nearHomeRoommates => _nearHomeRoommates;
  /// 본인 제외 전체 룸메이트 상태 (isNearHome 여부 포함)
  List<RoommateNearHomeStatus> get allRoommateStatuses => _allRoommateStatuses;
  /// 집 근처에 있는 룸메이트 이름 (본인 제외)
  List<String> get nearHomeRoommateNames =>
      _nearHomeRoommates.map((r) => r.name).where((n) => n.isNotEmpty).toList();

  String roommateNearHomeBannerText(RoommateNearHomeStatus roommate) {
    final name = roommate.name;
    if (name.isEmpty) {
      return roommate.isNearHome
          ? '룸메이트가 집 근처에 있어요.'
          : '룸메이트가 집 근처에 없어요.';
    }
    return roommate.isNearHome
        ? '$name 님이 집 근처에 있어요.'
        : '$name 님이 집 근처에 없어요.';
  }
  bool get isLoading => _isLoading;
  ({double lat, double lng, double radius})? get homeLocation => _homeLocation;
  String? get homeAddress => _homeAddress;

  /// 저장된 상태를 로드하고 서버와 동기화한 뒤 위치 감시를 재개합니다.
  Future<void> initialize() async {
    if (_ongoingInitialize != null) return _ongoingInitialize!;
    _ongoingInitialize = _initializeBody();
    try {
      await _ongoingInitialize;
    } finally {
      _ongoingInitialize = null;
    }
  }

  Future<void> _initializeBody() async {
    _isEnabled = StorageService.getSharingEnabled();
    _homeLocation = StorageService.getHomeLocation();
    _homeAddress = StorageService.getHomeAddress();
    _lastNotifiedAt = StorageService.getLastNearHomeNotification();

    await _syncFromServerIfPossible();

    // 주소가 없지만 좌표가 있으면 역지오코딩으로 주소 복원
    if (_homeAddress == null && _homeLocation != null) {
      final loc = _homeLocation!;
      final address = await GeocodingService.reverseGeocode(loc.lat, loc.lng);
      if (address != null) {
        _homeAddress = address;
        await StorageService.setHomeAddress(address);
      }
    }

    if (_isEnabled) {
      if (_homeLocation == null) {
        await _ensureHomeLocationFromServer();
      }
      if (_homeLocation != null) {
        // 다른 디바이스 동기화로 자동 ON된 경우, 이 디바이스는 위치 권한이 없을 수 있음.
        // 권한 다이얼로그를 갑자기 띄우지 않고 권한이 있을 때만 감시 시작 — 권한이 없는
        // 기기에서도 토글 ON 상태는 그대로 표시되며, 사용자가 직접 토글하거나 권한을
        // 부여한 뒤 다음 initialize·resume에서 자동으로 감시가 시작됨.
        final hasPermission = await _hasLocationPermission();
        if (hasPermission) {
          await _startLocationWatch();
          await _evaluateCurrentPosition();
        } else {
          debugPrint('[HomeShare] 위치 권한 없음 — 감시 보류 (토글 ON 표시는 유지)');
        }
      } else {
        debugPrint('[HomeShare] 귀가 공유 ON이지만 집 좌표 없음 — 위치 감시 대기');
      }
    }

    final refreshed = await refreshRoommateNearHomeFromServer();
    if (!refreshed) {
      _restoreRoommateNearHomeFromStorage();
    }
    notifyListeners();
  }

  /// 서버 GET으로 동의·집 위치를 보강합니다.
  ///
  /// 멀티 디바이스 동기화 정책 — 서버를 single source of truth로 사용합니다:
  /// - 서버 true → 로컬도 true (다른 디바이스에서 켰으면 이 디바이스도 따라감).
  /// - 서버 false → 로컬도 false (다른 디바이스에서 껐으면 이 디바이스도 끔).
  /// - 서버 null(미응답·미구현) → 로컬 ON 시 재등록 시도, OFF는 그대로 유지.
  Future<void> _syncFromServerIfPossible() async {
    final localEnabled = _isEnabled;

    try {
      final serverAgreed = await _service.fetchLocationConsent();
      if (serverAgreed == true) {
        // 서버 ON — 로컬이 OFF였다면 다른 디바이스에서 켠 것이므로 따라간다.
        if (!localEnabled) {
          debugPrint('[HomeShare] 서버 ON · 로컬 OFF → 다른 디바이스 동기화로 ON');
        }
        _isEnabled = true;
        await StorageService.setSharingEnabled(true);
      } else if (serverAgreed == false) {
        // 서버 OFF — 로컬이 ON이었다면 다른 디바이스에서 끈 것이므로 따라가서 OFF.
        if (localEnabled) {
          debugPrint('[HomeShare] 서버 OFF · 로컬 ON → 다른 디바이스 동기화로 OFF');
        }
        _isEnabled = false;
        await StorageService.setSharingEnabled(false);
        _isNearHome = false;
        _stopLocationWatch();
        _stopAtHomeRefreshTimer();
      } else if (localEnabled) {
        // 서버 null(404·미구현 등)인데 로컬 ON — 재등록 시도, UI는 ON 유지.
        _isEnabled = true;
        try {
          await _service.saveLocationConsent(agreed: true);
        } on ApiException catch (e) {
          debugPrint('[HomeShare] 동의 서버 재등록 실패: $e');
        }
      }
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 동의 서버 조회 실패(로컬 유지): $e');
    }

    try {
      final homeSnap = await _service.fetchHomeLocationSnapshot();
      if (homeSnap.coordinates != null) {
        final c = homeSnap.coordinates!;
        _homeLocation = c;
        await StorageService.setHomeLocation(c.lat, c.lng, c.radius);
      }
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 집 위치 서버 조회 실패(로컬 유지): $e');
    }
  }

  /// 서버에 이미 저장된 집 좌표를 로컬에 반영합니다(추가 POST 없음).
  Future<void> adoptServerHomeLocation({
    required double lat,
    required double lng,
    required double radius,
  }) async {
    _homeLocation = (lat: lat, lng: lng, radius: radius);
    await StorageService.setHomeLocation(lat, lng, radius);
    _homeAddress = null;
    await StorageService.clearHomeAddress();
    final address = await GeocodingService.reverseGeocode(lat, lng);
    if (address != null) {
      _homeAddress = address;
      await StorageService.setHomeAddress(address);
    }
    notifyListeners();
  }

  /// UI용 집 위치 스냅샷(최신 서버 상태).
  Future<HouseLocServerSnapshot> fetchHomeLocationSnapshot() async {
    return _service.fetchHomeLocationSnapshot();
  }

  /// 가구 공용 집 좌표를 서버에서 가져옵니다 (2번째 사용자 등 로컬 미설정 시).
  Future<bool> _ensureHomeLocationFromServer() async {
    if (_homeLocation != null) return true;
    try {
      final snap = await _service.fetchHomeLocationSnapshot();
      final c = snap.coordinates;
      if (c == null) return false;
      _homeLocation = c;
      await StorageService.setHomeLocation(c.lat, c.lng, c.radius);
      if (_homeAddress == null) {
        final address = await GeocodingService.reverseGeocode(c.lat, c.lng);
        if (address != null) {
          _homeAddress = address;
          await StorageService.setHomeAddress(address);
        }
      }
      return true;
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 집 좌표 서버 보강 실패: $e');
      return false;
    }
  }

  /// 가구에 등록된 집 좌표를 서버에서 받아옵니다. 성공 시 true.
  Future<bool> ensureHomeLocationFromServer() =>
      _ensureHomeLocationFromServer();

  /// GET `/households/location-events/near-home`으로 룸메이트 귀가 배너를 갱신합니다.
  /// 성공 시 [true], 네트워크·API 실패 시 [false] (로컬 캐시 폴백용).
  ///
  /// 새로고침은 사용자의 명시적 갱신 의도이므로, 룸메이트 GET과 함께 **자기 최신 위치도
  /// 다시 평가**해 서버에 반영합니다. 이로써 다른 사용자가 새로고침했을 때 내 최신 상태가
  /// 누락 없이 GET 응답에 들어가도록 보장합니다 (distanceFilter·GPS 떨림으로 인한
  /// `_onPosition` 콜백 누락 보완).
  Future<bool> refreshRoommateNearHomeFromServer() async {
    debugPrint('[HomeShare] GET /households/location-events/near-home 호출');

    // 다른 디바이스에서 토글·집 위치가 바뀌었을 수 있으니 동의·집 위치 상태도 같이 동기화.
    // 룸메이트 GET과 병렬로 진행되어 응답 대기 시간에는 영향 없음.
    unawaited(_syncFromServerIfPossible().then((_) {
      // sync 결과로 _isEnabled / _homeLocation이 바뀌었을 수 있으므로 UI 갱신.
      notifyListeners();
    }));

    // 자기 위치 재평가는 룸메이트 GET과 병렬로 진행 (응답 대기 시간에 영향 없음).
    // _isEnabled / 권한 / _homeLocation이 갖춰졌을 때만 실제 평가가 일어나며,
    // 새로고침 흐름에서 권한 다이얼로그가 갑자기 뜨지 않도록 silent 버전을 사용합니다.
    unawaited(_silentlyEvaluateCurrentPosition());

    try {
      final statuses = await _service.fetchRoommateNearHomeStatus();
      final myId = int.tryParse(await StorageService.getUserId() ?? '');
      final others = statuses.where((s) {
        if (myId != null && myId > 0 && s.userId == myId) return false;
        return true;
      }).toList()
        ..sort((a, b) => a.userId.compareTo(b.userId));
      final nearOthers =
          others.where((s) => s.isNearHome).toList(growable: false);
      debugPrint(
        '[HomeShare] 응답 — 본인 제외 ${others.length}명 / 집근처 ${nearOthers.length}명 '
        '(${others.map((s) => '${s.name}(${s.userId})=${s.isNearHome}').join(', ')})',
      );
      _setRoommateNearHomeFromServer(
        near: nearOthers.isNotEmpty,
        roommates: nearOthers,
        allRoommates: others,
      );
      return true;
    } on ApiException catch (e) {
      debugPrint('[HomeShare] 룸메이트 귀가 현황 조회 실패: $e');
      return false;
    } catch (e, st) {
      debugPrint('[HomeShare] 룸메이트 귀가 현황 조회 예외: $e\n$st');
      return false;
    }
  }

  void _setRoommateNearHomeFromServer({
    required bool near,
    required List<RoommateNearHomeStatus> roommates,
    required List<RoommateNearHomeStatus> allRoommates,
  }) {
    final roommatesChanged = !_roommatesEqual(_nearHomeRoommates, roommates);
    final allRoommatesChanged =
        !_roommatesStatusEqual(_allRoommateStatuses, allRoommates);
    if (_roommateNearHome == near &&
        !roommatesChanged &&
        !allRoommatesChanged) {
      return;
    }

    _roommateNearHome = near;
    _nearHomeRoommates = List.unmodifiable(roommates);
    _allRoommateStatuses = List.unmodifiable(allRoommates);

    if (near) {
      unawaited(StorageService.setRoommateNearHomeAt(DateTime.now()));
      _scheduleRoommateNearHomeExpiry();
    } else {
      _roommateNearHomeExpiryTimer?.cancel();
      unawaited(StorageService.clearRoommateNearHomeAt());
    }
    notifyListeners();
  }

  bool _roommatesStatusEqual(
    List<RoommateNearHomeStatus> a,
    List<RoommateNearHomeStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].userId != b[i].userId ||
          a[i].name != b[i].name ||
          a[i].isNearHome != b[i].isNearHome) {
        return false;
      }
    }
    return true;
  }

  bool _roommatesEqual(
    List<RoommateNearHomeStatus> a,
    List<RoommateNearHomeStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].userId != b[i].userId || a[i].name != b[i].name) return false;
    }
    return true;
  }

  void _mergeNearHomeRoommate({
    required int userId,
    String? name,
  }) {
    final merged = List<RoommateNearHomeStatus>.from(_nearHomeRoommates);
    final index = merged.indexWhere((r) => r.userId == userId);
    final resolvedName = (name != null && name.isNotEmpty)
        ? name
        : (index >= 0 ? merged[index].name : '');
    final entry = RoommateNearHomeStatus(
      userId: userId,
      name: resolvedName,
      isNearHome: true,
    );
    if (index >= 0) {
      merged[index] = entry;
    } else {
      merged.add(entry);
    }
    merged.sort((a, b) => a.userId.compareTo(b.userId));
    _nearHomeRoommates = List.unmodifiable(merged);

    final allMerged =
        List<RoommateNearHomeStatus>.from(_allRoommateStatuses);
    final allIndex = allMerged.indexWhere((r) => r.userId == userId);
    if (allIndex >= 0) {
      allMerged[allIndex] = entry;
    } else {
      allMerged.add(entry);
    }
    allMerged.sort((a, b) => a.userId.compareTo(b.userId));
    _allRoommateStatuses = List.unmodifiable(allMerged);
  }

  /// FCM `NEAR_HOME_ARRIVAL` 수신 시 알림 패널 상단 배너를 갱신합니다.
  void applyRoommateNearHomeEvent({String? senderName, int? senderUserId}) {
    if (senderUserId != null && senderUserId > 0) {
      _mergeNearHomeRoommate(userId: senderUserId, name: senderName);
    }
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

      if (_homeLocation == null) {
        await _ensureHomeLocationFromServer();
      }
      if (_homeLocation == null) {
        debugPrint('[HomeShare] 집 위치 없어 귀가 공유 활성화 불가');
        return false;
      }

      await _startLocationWatch();
      _isEnabled = true;
      await StorageService.setSharingEnabled(true);
      // 토글 ON 시 위치가 집 안이면 클라이언트 쿨다운을 무시하고 강제 전송
      await _evaluateCurrentPosition(force: true);

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
    _stopAtHomeRefreshTimer();
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
      unawaited(refreshRoommateNearHomeFromServer());
      return;
    }
    _roommateNearHomeExpiryTimer = Timer(wait, () {
      unawaited(refreshRoommateNearHomeFromServer());
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

  /// 권한 다이얼로그를 띄우지 않고 현재 권한·위치 서비스 상태만 확인합니다.
  /// 다른 디바이스에서 ON한 상태를 자동 동기화할 때 사용 — 사용자 인터랙션 없이
  /// 권한 다이얼로그가 갑자기 뜨는 것을 방지합니다.
  Future<bool> _hasLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    final permission = await Geolocator.checkPermission();
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

  /// 토글 ON·홈 재진입 시 이미 집 근처여도 알림이 가도록 현재 좌표를 한 번 평가합니다.
  /// [force]가 true이면 위치가 집 안일 때 클라이언트 쿨다운을 무시하고 POST를 전송합니다.
  Future<void> _evaluateCurrentPosition({bool force = false}) async {
    if (!_isEnabled || _homeLocation == null) return;
    try {
      final granted = await _ensureLocationPermission();
      if (!granted) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      _onPosition(position, force: force);
    } catch (e) {
      debugPrint('[HomeShare] 현재 위치 평가 실패: $e');
    }
  }

  /// 권한 다이얼로그를 띄우지 않고 현재 좌표를 평가합니다.
  /// 새로고침처럼 자동 트리거 흐름에서 사용 — 권한이 없으면 조용히 패스합니다.
  Future<void> _silentlyEvaluateCurrentPosition() async {
    if (!_isEnabled || _homeLocation == null) return;
    if (!await _hasLocationPermission()) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      _onPosition(position);
    } catch (e) {
      debugPrint('[HomeShare] 현재 위치 자동 평가 실패: $e');
    }
  }

  void _stopLocationWatch() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _onPosition(Position position, {bool force = false}) {
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
    final bool stateChanged = isNear != wasNear;

    _isNearHome = isNear;

    if (_isNearHome) {
      // 집 반경 진입 또는 강제 호출(토글 ON 등) 시 POST 전송
      if (stateChanged || force) {
        _maybeNotify(force: force);
      } else if (_isAtHomeStateStale()) {
        // 같은 집 안 상태가 유지 중인데 서버 TTL(30분) 만료가 임박 — force POST로 갱신.
        // 이러면 사용자가 새로고침할 때(또는 위치 콜백이 들어올 때) 룸메이트의 배너가
        // 끊기지 않고 지속적으로 유지됩니다 (백그라운드 Timer 신뢰성 보완).
        _maybeNotify(force: true);
      }
      _startAtHomeRefreshTimer();
    } else {
      _stopAtHomeRefreshTimer();
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  /// 마지막 `entered_home_area` POST 이후 [_atHomeRefreshThreshold]가 지나
  /// 서버 TTL 만료가 임박했는지 여부.
  bool _isAtHomeStateStale() {
    final lastAt = _lastNotifiedAt;
    if (lastAt == null) return true;
    return DateTime.now().difference(lastAt) >= _atHomeRefreshThreshold;
  }

  void _maybeNotify({bool force = false}) {
    if (!force &&
        _lastNotifiedAt != null &&
        DateTime.now().difference(_lastNotifiedAt!) < _cooldown) {
      return;
    }
    _lastNotifiedAt = DateTime.now();
    StorageService.setLastNearHomeNotification(_lastNotifiedAt!);

    _service.sendNearHomeEvent().catchError((Object e) {
      debugPrint('[HomeShare] 집 근처 알림 전송 실패: $e');
    });
  }

  /// 집 안에 머무는 동안 서버 GET `isNearHome` 상태가 만료(30분)되지 않도록
  /// 5분 간격으로 체크하고, 마지막 POST 후 28분이 지났으면 강제 재전송합니다.
  void _startAtHomeRefreshTimer() {
    if (_atHomeRefreshTimer != null && _atHomeRefreshTimer!.isActive) return;
    _atHomeRefreshTimer = Timer.periodic(_atHomeRefreshInterval, (_) {
      if (!_isEnabled || !_isNearHome || _homeLocation == null) {
        _stopAtHomeRefreshTimer();
        return;
      }
      final lastAt = _lastNotifiedAt;
      // 서버 30분 쿨다운이 끝나기 직전(28분)부터만 재전송 — 불필요한 요청 최소화
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < _atHomeRefreshThreshold) {
        return;
      }
      _maybeNotify(force: true);
    });
  }

  void _stopAtHomeRefreshTimer() {
    _atHomeRefreshTimer?.cancel();
    _atHomeRefreshTimer = null;
  }

  @override
  void dispose() {
    _roommateNearHomeExpiryTimer?.cancel();
    _stopAtHomeRefreshTimer();
    _stopLocationWatch();
    super.dispose();
  }
}
