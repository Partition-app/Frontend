import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_auth/kakao_flutter_sdk_auth.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// 카카오 로그인 서비스
class KakaoAuthService {
  /// 카카오 로그인 실행
  /// 카카오톡 설치 여부를 확인하고, 설치되어 있으면 카카오톡으로 로그인,
  /// 없으면 카카오계정으로 로그인
  /// 이메일 권한은 카카오 개발자 콘솔에서 동의 항목을 설정하면 자동으로 받아올 수 있습니다.
  static Future<OAuthToken?> login() async {
    try {
      final canUseKakaoTalk = await _canUseKakaoTalkLogin();

      if (canUseKakaoTalk) {
        try {
          // 카카오톡으로 로그인 시도
          final token = await UserApi.instance.loginWithKakaoTalk();
          return token;
        } catch (error) {
          // 사용자가 카카오톡 설치 후 디바이스 권한 요청 화면에서 로그인을 취소한 경우
          if (error is PlatformException && error.code == 'CANCELED') {
            return null;
          }
          
          // 카카오톡에 연결된 카카오계정이 없는 경우, 카카오계정으로 로그인 시도
          try {
            final token = await UserApi.instance.loginWithKakaoAccount();
            return token;
          } catch (accountError) {
            throw accountError;
          }
        }
      } else {
        // 카카오톡이 설치되어 있지 않은 경우, 카카오계정으로 로그인
        final token = await UserApi.instance.loginWithKakaoAccount();
        return token;
      }
    } catch (error) {
      rethrow;
    }
  }

  static Future<bool> _canUseKakaoTalkLogin() async {
    if (kIsWeb) {
      return false;
    }

    // iOS/Android가 아니면 카카오톡 로그인 불가
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android)) {
      return false;
    }

    try {
      return await isKakaoTalkInstalled();
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 사용자 정보 조회
  /// 이메일 정보를 포함한 사용자 정보를 가져옵니다.
  static Future<User?> getUserInfo() async {
    try {
      // 사용자 정보 조회 - propertyKeys로 필요한 정보 명시적으로 요청
      // kakao_account와 account_email을 요청하여 이메일 정보를 포함
      final user = await UserApi.instance.me();
      
      return user;
    } catch (error) {
      rethrow;
    }
  }
  
  /// 사용자 정보를 다시 조회 (토큰 갱신 후)
  /// 카카오 개발자 콘솔 설정 변경 후 사용
  static Future<User?> refreshUserInfo() async {
    try {
      // 기존 토큰이 있으면 로그아웃 후 다시 로그인하도록 안내
      // 또는 토큰을 갱신하여 사용자 정보를 다시 가져옴
      final user = await UserApi.instance.me();
      return user;
    } catch (error) {
      rethrow;
    }
  }
  
  /// 추가 동의가 필요한 항목 확인
  static Future<bool> needsAdditionalAgreement() async {
    try {
      final user = await UserApi.instance.me();
      return user?.kakaoAccount?.emailNeedsAgreement ?? false;
    } catch (error) {
      return false;
    }
  }

  /// 저장된 카카오 액세스 토큰 (서버 JWT 재발급용)
  static Future<String?> getStoredAccessToken() async {
    try {
      if (!await AuthApi.instance.hasToken()) return null;
      final token = await TokenManagerProvider.instance.manager.getToken();
      final access = token?.accessToken;
      if (access == null || access.isEmpty) return null;
      return access;
    } catch (_) {
      return null;
    }
  }

  /// 로그아웃
  static Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (error) {
      rethrow;
    }
  }

  /// 토큰 존재 여부 확인
  static Future<bool> hasToken() async {
    try {
      return await AuthApi.instance.hasToken();
    } catch (error) {
      return false;
    }
  }

  /// 액세스 토큰 정보 조회
  static Future<AccessTokenInfo?> getAccessTokenInfo() async {
    try {
      final tokenInfo = await UserApi.instance.accessTokenInfo();
      return tokenInfo;
    } catch (error) {
      return null;
    }
  }
}

