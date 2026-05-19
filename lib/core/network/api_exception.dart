import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  /// 서버 `code` (예: `RESERVATION_2005`)
  final String? code;
  final dynamic originalError;

  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.originalError,
  });

  @override
  String toString() {
    return 'ApiException: $message (Status: $statusCode)';
  }

  factory ApiException.fromDioError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(
            message: '연결 시간이 초과되었습니다.',
            statusCode: error.response?.statusCode,
            originalError: error,
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          String errorMessage = '서버 오류가 발생했습니다.';
          String? apiCode;

          if (statusCode == 413) {
            errorMessage =
                '파일 용량이 서버에서 허용하는 한도를 넘었습니다. (예: 음성 25MB, 이미지 업로드 제한)';
          } else {
            // 에러 응답 데이터 안전하게 파싱
            try {
              final responseData = error.response?.data;
              if (responseData is Map<String, dynamic>) {
                apiCode = responseData['code']?.toString();
                final detail = responseData['detail'];
                if (detail is String && detail.trim().isNotEmpty) {
                  errorMessage = detail.trim();
                } else if (detail is List && detail.isNotEmpty) {
                  final first = detail.first;
                  if (first is Map<String, dynamic>) {
                    final msg = first['msg']?.toString();
                    if (msg != null && msg.isNotEmpty) {
                      errorMessage = msg;
                    }
                  }
                }
                if (errorMessage == '서버 오류가 발생했습니다.') {
                  errorMessage = responseData['message'] as String? ??
                      responseData['error'] as String? ??
                      '서버 오류가 발생했습니다.';
                }
              } else if (responseData is String) {
                final s = responseData.trim();
                // HTML(nginx 오류 페이지 등)이면 본문 대신 코드만
                if (s.startsWith('<!') || s.startsWith('<html')) {
                  errorMessage =
                      '서버 오류가 발생했습니다. (${statusCode ?? '?'})';
                } else {
                  errorMessage = s;
                }
              }
            } catch (e) {
              errorMessage =
                  '서버 오류가 발생했습니다. (${error.response?.statusCode})';
            }
          }

          return ApiException(
            message: errorMessage,
            statusCode: statusCode,
            code: apiCode,
            originalError: error,
          );
        case DioExceptionType.cancel:
          return ApiException(
            message: '요청이 취소되었습니다.',
            originalError: error,
          );
        default:
          final tlsMsg = _messageForTlsFailure(error);
          return ApiException(
            message: tlsMsg ?? '네트워크 오류가 발생했습니다.',
            originalError: error,
          );
      }
    }
    return ApiException(
      message: '알 수 없는 오류가 발생했습니다.',
      originalError: error,
    );
  }

  /// VPN·프록시·SSL 검사(기업망) 등으로 [CERTIFICATE_VERIFY_FAILED]가 나는 경우 안내.
  /// 웹 빌드 호환을 위해 `dart:io` 예외 타입 대신 문자열 패턴만 사용합니다.
  static String? _messageForTlsFailure(DioException error) {
    final causeStr = '${error.error ?? ''}';
    if (causeStr.contains('HandshakeException')) {
      return '보안 연결(SSL)을 확인하지 못했습니다. VPN·HTTPS 가로채기 앱을 끄거나 다른 네트워크에서 다시 시도해 주세요.';
    }
    if (causeStr.contains('TlsException') &&
        causeStr.contains('CERTIFICATE_VERIFY_FAILED')) {
      return '서버 인증서 검증에 실패했습니다. 기기 날짜·시간이 맞는지, 중간 보안 프로그램이 없는지 확인해 주세요.';
    }
    final text = '${error.message ?? ''}$causeStr';
    if (text.contains('CERTIFICATE_VERIFY_FAILED') ||
        text.contains('HandshakeException')) {
      return '보안 연결(SSL)을 확인하지 못했습니다. VPN·프록시를 끄고 다시 시도해 주세요.';
    }
    return null;
  }
}

