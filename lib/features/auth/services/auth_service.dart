import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/models/auth_response_model.dart';
import 'package:partition_app/features/auth/models/user_model.dart';
import 'package:partition_app/features/auth/models/kakao_auth_response_model.dart';
import 'package:partition_app/features/auth/models/update_name_response_model.dart';
import 'package:partition_app/features/auth/models/household_response_model.dart';
import 'package:partition_app/features/auth/models/preference_response_model.dart';

/// 하우스 멤버 (`POST /supplies/settlement`의 `memberIds` 등)
class HouseholdMemberBrief {
  final int userId;
  final String name;
  final String? profileImage;
  final String? role;

  const HouseholdMemberBrief({
    required this.userId,
    required this.name,
    this.profileImage,
    this.role,
  });
}

int? _parseHouseholdMemberUserId(Map<String, dynamic> e) {
  for (final key in ['userId', 'id', 'memberId', 'user_id']) {
    final v = e[key];
    if (v == null) continue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isNotEmpty) return int.tryParse(s);
  }
  return null;
}

String? _parseHouseholdMemberDisplayName(Map<String, dynamic> e) {
  final n = e['name'] as String? ??
      e['nickname'] as String? ??
      e['userName'] as String?;
  final t = n?.trim();
  return (t != null && t.isNotEmpty) ? t : null;
}

String? _parseHouseholdMemberProfileImage(Map<String, dynamic> e) {
  final raw = e['profileImage'] ?? e['profileImageUrl'] ?? e['imageUrl'];
  final text = raw?.toString().trim();
  return (text != null && text.isNotEmpty) ? text : null;
}

String? _parseHouseholdMemberRole(Map<String, dynamic> e) {
  final raw = e['role']?.toString().trim().toUpperCase();
  return (raw != null && raw.isNotEmpty) ? raw : null;
}

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Future<AuthResponseModel> login(String email, String password) async {
    try {
      final response = await _apiClient.post(
        AppConfig.loginEndpoint,
        data: {
          'email': email,
          'password': password,
        },
      );

      final authResponse = AuthResponseModel.fromJson(response.data);
      
      // 토큰 저장
      await StorageService.setToken(authResponse.token);
      await StorageService.setUserId(authResponse.user.id);

      return authResponse;
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<AuthResponseModel> register({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.registerEndpoint,
        data: {
          'email': email,
          'password': password,
          if (name != null) 'name': name,
        },
      );

      final authResponse = AuthResponseModel.fromJson(response.data);
      
      // 토큰 저장
      await StorageService.setToken(authResponse.token);
      await StorageService.setUserId(authResponse.user.id);

      return authResponse;
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.post(
        AppConfig.logoutEndpoint,
        data: null,
        options: Options(
          validateStatus: (status) =>
              status != null && (status == 200 || status == 401 || status == 404),
        ),
      );
    } catch (_) {
      // 서버 로그아웃 실패와 관계없이 로컬 세션은 정리합니다.
    }
    await StorageService.clear();
  }

  Future<bool> isAuthenticated() async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) return false;
    // JWT 만료 여부 확인 — 만료됐으면 저장된 토큰을 제거하고 false 반환
    if (_isTokenExpired(token)) {
      await StorageService.clear();
      return false;
    }
    return true;
  }

  /// JWT exp 클레임을 기준으로 토큰 만료 여부 반환.
  /// 파싱에 실패하면 만료되지 않은 것으로 간주(false 반환).
  static bool _isTokenExpired(String token) {
    try {
      final segments = token.split('.');
      if (segments.length < 2) return false;
      var payload = segments[1];
      final pad = payload.length % 4;
      if (pad == 1) return false;
      if (pad == 2) payload += '==';
      if (pad == 3) payload += '=';
      final jsonStr = utf8.decode(base64Url.decode(payload));
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return false;
      final exp = decoded['exp'];
      if (exp == null) return false;
      final expSeconds = exp is int ? exp : int.tryParse(exp.toString());
      if (expSeconds == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= expSeconds;
    } catch (_) {
      return false;
    }
  }

  /// 카카오 로그인
  Future<KakaoAuthResponseModel> loginWithKakao({
    required String kakaoAccessToken,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.kakaoLoginEndpoint,
        data: {
          'kakaoAccessToken': kakaoAccessToken,
        },
      );

      final kakaoAuthResponse = KakaoAuthResponseModel.fromJson(response.data);
      
      // 토큰 저장
      if (kakaoAuthResponse.result != null) {
        final access = kakaoAuthResponse.result!.accessToken;
        await StorageService.setToken(access);
        await StorageService.setRefreshToken(kakaoAuthResponse.result!.refreshToken);
        final jwtUid = _jwtPreferredNumericUserId(access);
        if (jwtUid != null && jwtUid > 0) {
          await StorageService.setUserId('$jwtUid');
        }
        // userRole(LEADER/MEMBER/GUEST)을 로컬에 저장 — 새로고침 시 1순위 라우팅 신호로 사용
        final role = kakaoAuthResponse.result!.userRole.trim();
        if (role.isNotEmpty) {
          await StorageService.setUserRole(role);
        }
      }

      return kakaoAuthResponse;
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 사용자 이름 업데이트
  Future<UpdateNameResponseModel> updateUserName({
    required String name,
  }) async {
    try {
      final response = await _apiClient.patch(
        AppConfig.updateUserNameEndpoint,
        data: {
          'name': name,
        },
      );

      return UpdateNameResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 그룹(가구) 생성
  Future<HouseholdResponseModel> createHousehold({
    required String name,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.householdsEndpoint,
        data: {
          'name': name,
        },
      );

      return HouseholdResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 현재 사용자를 가구에서 제거합니다. (서버 미배포 시 404 가능)
  Future<void> leaveHouseholdAsMember() async {
    try {
      await _apiClient.post(
        AppConfig.householdsLeaveEndpoint,
        data: const <String, dynamic>{},
      );
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 회원 탈퇴 — `POST /users/me/withdraw` (본문 없음 · `{}`).
  ///
  /// 성공: `isSuccess: true`, `result: null`.
  /// 404 `USER_4001`, 400 `USER_4002`(그룹 리더는 위임 후 탈퇴) 등은 서버 `message`를 그대로 전달합니다.
  Future<void> deleteMyAccountOnServer() async {
    try {
      final response = await _apiClient.post(
        AppConfig.userWithdrawEndpoint,
        data: const <String, dynamic>{},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['isSuccess'] == false) {
        final message = (data['message'] as String?)?.trim();
        throw ApiException(
          message:
              message != null && message.isNotEmpty
                  ? message
                  : '회원 탈퇴에 실패했어요.',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioError(e);
    }
  }

  /// 그룹(가구) 참여
  Future<HouseholdResponseModel> joinHousehold({
    required String inviteCode,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.householdsJoinEndpoint,
        data: {
          'inviteCode': inviteCode,
        },
      );

      return HouseholdResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 선호도 등록
  Future<PreferenceResponseModel> registerPreferences({
    required List<PreferenceItem> preferences,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.userPreferencesEndpoint,
        data: {
          'preferences': preferences.map((p) => p.toJson()).toList(),
        },
      );

      return PreferenceResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// prefs·JWT에서 현재 사용자 숫자 id (멤버 목록 비교·그룹장 위임 등)
  Future<int?> getResolvedCurrentUserId() async {
    final s = await StorageService.getUserId();
    var id = int.tryParse(s ?? '');
    if (id != null && id > 0) return id;
    final t = await StorageService.getToken();
    return _jwtPreferredNumericUserId(t);
  }

  /// 내 가구 그룹명 변경 (`PATCH /households/name`, `{ name }`)
  Future<void> updateHouseholdName({
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ApiException(message: '그룹명을 입력해주세요.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.householdsNameEndpoint,
        data: {'name': trimmed},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '그룹명 변경 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] == false) {
        final message = (data['message'] as String?)?.trim();
        throw ApiException(
          message:
              message != null && message.isNotEmpty
                  ? message
                  : '그룹명을 변경하지 못했습니다.',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioError(e);
    }
  }

  /// 그룹장을 다른 멤버에게 위임 (그룹장만). `PATCH /households/leader`
  Future<void> transferHouseholdLeadership({
    required int targetUserId,
  }) async {
    if (targetUserId <= 0) {
      throw ApiException(message: '유효한 그룹원을 선택해주세요.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.householdsLeaderEndpoint,
        data: {'targetUserId': targetUserId},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['isSuccess'] == false) {
        final message = (data['message'] as String?)?.trim();
        throw ApiException(
          message:
              message != null && message.isNotEmpty
                  ? message
                  : '그룹 리더 위임에 실패했어요.',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioError(e);
    }
  }

  /// 현재 로그인한 사용자의 그룹(가구) 정보를 서버에서 조회합니다.
  /// `GET /households/me`
  /// 그룹에 속하지 않았거나 요청 실패 시 null 반환.
  Future<HouseholdResponseModel?> fetchMyHousehold() async {
    try {
      final response = await _apiClient.get(
        AppConfig.householdsMeEndpoint,
        options: Options(
          validateStatus: (status) =>
              status != null && (status == 200 || status == 404 || status == 400),
        ),
      );
      if (response.statusCode != 200) return null;
      if (response.data is! Map<String, dynamic>) return null;
      return HouseholdResponseModel.fromJson(
          response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[AuthService] fetchMyHousehold 실패: $e');
      return null;
    }
  }

  /// 그룹 멤버 목록 (설정/정산 API `memberIds` 연동).
  ///
  /// API 형식:
  /// `{ isSuccess, result: [ { userId, name, profileImage, role } ] }`
  /// 또는 `result.members` 등.
  Future<List<HouseholdMemberBrief>> fetchHouseholdMembers() async {
    try {
      // 배포 서버에 경로가 없을 때 404가 나와도 예외·인터셉터 에러 로그를 줄이기 위해 허용
      final response = await _apiClient.get(
        AppConfig.householdMembersEndpoint,
        options: Options(
          validateStatus: (status) =>
              status != null && (status == 200 || status == 404),
        ),
      );
      if (response.statusCode == 404) {
        return _fallbackHouseholdMembersBrief();
      }
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return _fallbackHouseholdMembersBrief();
      }
      if (data['isSuccess'] == false) {
        return _fallbackHouseholdMembersBrief();
      }
      final dynamic result = data['result'];
      List<dynamic>? list;
      if (result is List) {
        list = result;
      } else if (result is Map<String, dynamic>) {
        final m = result['members'] ??
            result['memberList'] ??
            result['users'] ??
            result['userList'];
        if (m is List) list = m;
      }
      if (list == null || list.isEmpty) {
        return _fallbackHouseholdMembersBrief();
      }
      final out = <HouseholdMemberBrief>[];
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final id = _parseHouseholdMemberUserId(e);
          final name = _parseHouseholdMemberDisplayName(e);
          if (id != null && id > 0 && name != null) {
            out.add(
              HouseholdMemberBrief(
                userId: id,
                name: name,
                profileImage: _parseHouseholdMemberProfileImage(e),
                role: _parseHouseholdMemberRole(e),
              ),
            );
          }
        }
      }
      if (out.isEmpty) {
        return _fallbackHouseholdMembersBrief();
      }
      return out;
    } catch (e) {
      return _fallbackHouseholdMembersBrief();
    }
  }

  Future<List<HouseholdMemberBrief>> _fallbackHouseholdMembersBrief() async {
    final token = await StorageService.getToken();
    final idStr = await StorageService.getUserId();
    var uid = int.tryParse(idStr ?? '');
    uid ??= _jwtPreferredNumericUserId(token);
    final u = await getUserInfo();
    final name = u?.name?.trim().isNotEmpty == true
        ? u!.name!.trim()
        : (await StorageService.getUserName())?.trim() ?? '나';
    final role = StorageService.getUserRole();
    if (uid != null && uid > 0) {
      return [
        HouseholdMemberBrief(
          userId: uid,
          name: name,
          role: role,
        ),
      ];
    }
    return [];
  }

  /// JWT 클레임에서 서버 `memberIds`에 넣을 수 있는 양의 정수 user id 추출 (카카오 로그인 등으로 prefs에 id가 없을 때 보조).
  static int? _jwtPreferredNumericUserId(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final segments = token.split('.');
      if (segments.length < 2) return null;
      var payload = segments[1];
      final pad = payload.length % 4;
      if (pad == 1) return null;
      if (pad == 2) payload += '==';
      if (pad == 3) payload += '=';
      final jsonStr = utf8.decode(base64Url.decode(payload));
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      int? fromVal(dynamic v) {
        if (v == null) return null;
        if (v is int) return v > 0 ? v : null;
        if (v is num) {
          final i = v.toInt();
          return i > 0 ? i : null;
        }
        final s = v.toString().trim();
        if (s.isEmpty) return null;
        final n = int.tryParse(s);
        return (n != null && n > 0) ? n : null;
      }

      for (final key in [
        'userId',
        'user_id',
        'id',
        'uid',
        'memberId',
        'member_id',
      ]) {
        final n = fromVal(decoded[key]);
        if (n != null) return n;
      }
      return fromVal(decoded['sub']);
    } catch (_) {
      return null;
    }
  }

  /// 그룹(가구)에 속한 멤버 이름 목록 (공과금 정산 등 UI용).
  Future<List<String>> fetchHouseholdMemberNames() async {
    final briefs = await fetchHouseholdMembers();
    if (briefs.isEmpty) return _fallbackHouseholdMemberNames();
    return briefs.map((e) => e.name).toList();
  }

  Future<List<String>> _fallbackHouseholdMemberNames() async {
    final names = <String>[];
    final u = await getUserInfo();
    if (u?.name != null && u!.name!.trim().isNotEmpty) {
      names.add(u.name!.trim());
    }
    final local = await StorageService.getUserName();
    if (local != null && local.trim().isNotEmpty) {
      final t = local.trim();
      if (!names.contains(t)) names.add(t);
    }
    for (var i = names.length; i < 4; i++) {
      names.add('그룹원 ${i + 1}');
    }
    return names;
  }

  /// JWT payload의 `sub` (GET /users/me 미구현 시 세션 식별용).
  static String? _jwtSubject(String token) {
    try {
      final segments = token.split('.');
      if (segments.length < 2) return null;
      var payload = segments[1];
      final pad = payload.length % 4;
      if (pad == 1) return null;
      if (pad == 2) payload += '==';
      if (pad == 3) payload += '=';
      final jsonStr = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(jsonStr);
      if (map is Map<String, dynamic>) {
        final sub = map['sub'];
        return sub?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// 세션 사용자 정보 (로컬만). GET `/users/me`는 백엔드 미구현으로 호출하지 않음.
  Future<UserModel?> getUserInfo() async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) return null;

    final storedId = await StorageService.getUserId();
    final id = (storedId != null && storedId.isNotEmpty)
        ? storedId
        : (_jwtSubject(token) ?? 'session');
    final name = await StorageService.getUserName();

    return UserModel(
      id: id,
      email: '',
      name: name,
      createdAt: DateTime.now(),
    );
  }
}

