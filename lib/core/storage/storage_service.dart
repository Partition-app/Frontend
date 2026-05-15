import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:partition_app/core/config/app_config.dart';

class StorageService {
  static SharedPreferences? _prefs;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Access Token을 flutter_secure_storage에 저장
  static Future<bool> setToken(String token) async {
    try {
      await _secureStorage.write(key: AppConfig.tokenKey, value: token);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Access Token을 flutter_secure_storage에서 읽기
  static Future<String?> getToken() async {
    try {
      return await _secureStorage.read(key: AppConfig.tokenKey);
    } catch (e) {
      return null;
    }
  }

  /// Access Token 삭제
  static Future<bool> removeToken() async {
    try {
      await _secureStorage.delete(key: AppConfig.tokenKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refresh Token을 flutter_secure_storage에 저장
  static Future<bool> setRefreshToken(String refreshToken) async {
    try {
      await _secureStorage.write(key: AppConfig.refreshTokenKey, value: refreshToken);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refresh Token을 flutter_secure_storage에서 읽기
  static Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: AppConfig.refreshTokenKey);
    } catch (e) {
      return null;
    }
  }

  /// Refresh Token 삭제
  static Future<bool> removeRefreshToken() async {
    try {
      await _secureStorage.delete(key: AppConfig.refreshTokenKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setUserId(String userId) async {
    return await _prefs?.setString(AppConfig.userIdKey, userId) ?? false;
  }

  static Future<String?> getUserId() async {
    return _prefs?.getString(AppConfig.userIdKey);
  }

  static Future<bool> setUserName(String name) async {
    return await _prefs?.setString('user_name', name) ?? false;
  }

  static Future<String?> getUserName() async {
    return _prefs?.getString('user_name');
  }

  static Future<void> removeUserName() async {
    await _prefs?.remove('user_name');
  }

  /// 앱 내 닉네임 입력(온보딩) 완료 여부 — 카카오 프로필 닉네임과 구분합니다.
  static Future<bool> setNicknameSetupCompleted(bool completed) async {
    return await _prefs?.setBool('nickname_setup_completed', completed) ??
        false;
  }

  static bool isNicknameSetupCompleted() {
    return _prefs?.getBool('nickname_setup_completed') ?? false;
  }

  /// 닉네임 입력 완료 여부 (기존 사용자 마이그레이션 포함).
  static Future<bool> hasNicknameSetupCompleted() async {
    if (isNicknameSetupCompleted()) return true;

    final name = _prefs?.getString('user_name');
    if (name == null || name.isEmpty) return false;

    final role = getUserRole();
    if (role == 'LEADER' ||
        role == 'MEMBER' ||
        await isOnboardingCompleted()) {
      await setNicknameSetupCompleted(true);
      return true;
    }
    return false;
  }

  /// 카카오 로그인 응답의 `userRole` (LEADER / MEMBER / GUEST)을 저장.
  /// 새로고침 후에도 사용자가 "이미 가구에 속한 정상 사용자"인지 빠르게 판별하는 데 사용.
  static Future<bool> setUserRole(String role) async {
    return await _prefs?.setString(AppConfig.userRoleKey, role) ?? false;
  }

  static String? getUserRole() {
    return _prefs?.getString(AppConfig.userRoleKey);
  }

  static Future<bool> removeUserRole() async {
    return await _prefs?.remove(AppConfig.userRoleKey) ?? false;
  }

  static Future<bool> setOnboardingCompleted(bool completed) async {
    return await _prefs?.setBool('onboarding_completed', completed) ?? false;
  }

  static Future<bool> isOnboardingCompleted() async {
    return _prefs?.getBool('onboarding_completed') ?? false;
  }

  static Future<bool> setHouseholdId(String householdId) async {
    // SharedPreferences와 SecureStorage 모두에 저장해 웹 새로고침 후에도 유실되지 않도록 함
    final prefResult =
        await _prefs?.setString('household_id', householdId) ?? false;
    try {
      await _secureStorage.write(key: 'household_id', value: householdId);
    } catch (_) {}
    return prefResult;
  }

  static Future<String?> getHouseholdId() async {
    // SharedPreferences 우선 조회, 없으면 SecureStorage에서 복구
    final fromPrefs = _prefs?.getString('household_id');
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    try {
      final fromSecure = await _secureStorage.read(key: 'household_id');
      if (fromSecure != null && fromSecure.isNotEmpty) {
        // 복구된 값을 SharedPreferences에도 다시 저장
        await _prefs?.setString('household_id', fromSecure);
        return fromSecure;
      }
    } catch (_) {}
    return null;
  }

  // ── 귀가 공유 설정 ───────────────────────────────────────────────────────
  static Future<bool> setSharingEnabled(bool enabled) async {
    return await _prefs?.setBool('home_sharing_enabled', enabled) ?? false;
  }

  static bool getSharingEnabled() {
    return _prefs?.getBool('home_sharing_enabled') ?? false;
  }

  static Future<bool> setHomeLocation(double lat, double lng, double radius) async {
    final ok1 = await _prefs?.setDouble('home_lat', lat) ?? false;
    final ok2 = await _prefs?.setDouble('home_lng', lng) ?? false;
    final ok3 = await _prefs?.setDouble('home_radius', radius) ?? false;
    return ok1 && ok2 && ok3;
  }

  /// null 이면 집 위치가 설정되지 않은 것
  static ({double lat, double lng, double radius})? getHomeLocation() {
    final lat = _prefs?.getDouble('home_lat');
    final lng = _prefs?.getDouble('home_lng');
    final radius = _prefs?.getDouble('home_radius') ?? 300.0;
    // lat/lng 가 0,0 이면 미설정으로 간주
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return null;
    return (lat: lat, lng: lng, radius: radius);
  }

  static Future<void> clearHomeLocation() async {
    await _prefs?.remove('home_lat');
    await _prefs?.remove('home_lng');
    await _prefs?.remove('home_radius');
    await _prefs?.remove('home_address');
  }

  static Future<bool> setHomeAddress(String address) async {
    return await _prefs?.setString('home_address', address) ?? false;
  }

  static Future<void> clearHomeAddress() async {
    await _prefs?.remove('home_address');
  }

  static String? getHomeAddress() {
    return _prefs?.getString('home_address');
  }

  static Future<bool> setLastNearHomeNotification(DateTime time) async {
    return await _prefs?.setInt(
          'last_near_home_at',
          time.millisecondsSinceEpoch,
        ) ??
        false;
  }

  static DateTime? getLastNearHomeNotification() {
    final ms = _prefs?.getInt('last_near_home_at');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 룸메이트 집 근처 진입 FCM 수신 시각 (30분 TTL용)
  static Future<bool> setRoommateNearHomeAt(DateTime time) async {
    return await _prefs?.setInt(
          'roommate_near_home_at',
          time.millisecondsSinceEpoch,
        ) ??
        false;
  }

  static DateTime? getRoommateNearHomeAt() {
    final ms = _prefs?.getInt('roommate_near_home_at');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 가구 참여 정보만 초기화(토큰·닉네임 유지 → 그룹 선택·재참여용).
  static Future<void> clearHouseholdAffiliation() async {
    try {
      await _prefs?.remove('household_id');
    } catch (_) {}
    try {
      await _secureStorage.delete(key: 'household_id');
    } catch (_) {}
    await removeUserRole();
    await setUserRole('GUEST');
    await setOnboardingCompleted(false);
  }

  /// JWT 만료 등 재로그인만 필요할 때 — 귀가 공유·집 위치 등 로컬 설정은 유지합니다.
  static Future<void> clearAuthSession() async {
    try {
      await removeToken();
      await removeRefreshToken();
    } catch (_) {}
  }

  static Future<bool> clear() async {
    try {
      // Secure storage 삭제
      await _secureStorage.deleteAll();
      // SharedPreferences 삭제
      return await _prefs?.clear() ?? false;
    } catch (e) {
      return false;
    }
  }
}

