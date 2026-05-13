import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';

/// 사용자 계정 API — `POST /api/users/me/withdraw` 등
class UserService {
  final ApiClient _apiClient = ApiClient();

  /// 회원 탈퇴 — `POST /users/me/withdraw` (요청 본문 없음).
  ///
  /// 성공: `{ isSuccess: true, result: null }`
  /// - 404 `USER_4001`: 사용자를 찾을 수 없습니다.
  /// - 400 `USER_4002`: 그룹 리더는 탈퇴할 수 없습니다.
  Future<void> withdraw() async {
    try {
      final response = await _apiClient.post(
        AppConfig.userWithdrawEndpoint,
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '회원 탈퇴에 실패했어요.',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
