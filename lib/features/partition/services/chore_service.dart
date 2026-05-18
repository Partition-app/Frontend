import 'package:flutter/foundation.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/chore_api_models.dart';
import 'package:partition_app/features/partition/models/chore_auto_assign_response_model.dart';
import 'package:partition_app/features/partition/models/schedule_response_model.dart';

class ChoreService {
  final ApiClient _apiClient = ApiClient();

  /// 집안일 자동 배정 요청
  /// - API: POST /api/chores/auto-assign
  /// - Body: { startDate, endDate, choreTypes[] }
  /// - choreTypes: DISH_WASHING, COOKING, LAUNDRY, FOODTRASH, TRASH, RECYCLING, VACUUM, MOPPING, WINDOW, BATHROOM, FRIDGE
  Future<ChoreAutoAssignResponseModel> autoAssignChores({
    required String startDate,
    required String endDate,
    required List<String> choreTypes, // enum 값들 (DISH_WASHING 등)
  }) async {
    try {
      // 디버깅: API 요청 데이터 확인
      debugPrint('📤 집안일 자동 배정 API 호출');
      debugPrint('  - 엔드포인트: ${AppConfig.choresAutoAssignEndpoint}');
      debugPrint('  - Request Body:');
      debugPrint('    * startDate: $startDate');
      debugPrint('    * endDate: $endDate');
      debugPrint('    * choreTypes: $choreTypes');
      debugPrint('    * choreTypes 개수: ${choreTypes.length}');
      
      // API 명세에 따라 body에 모든 데이터 포함
      final requestBody = {
        'startDate': startDate,
        'endDate': endDate,
        'choreTypes': choreTypes, // enum 값 배열
      };
      
      debugPrint('  - 전체 Request Body: $requestBody');
      
      final response = await _apiClient.post(
        AppConfig.choresAutoAssignEndpoint,
        data: requestBody,
      );

      debugPrint('✅ API 응답 받음');
      debugPrint('  - 응답 데이터: ${response.data}');

      return ChoreAutoAssignResponseModel.fromJson(response.data);
    } catch (e) {
      debugPrint('❌ API 호출 실패: $e');
      throw ApiException.fromDioError(e);
    }
  }

  /// 집안일 수동 등록
  /// - API: POST /api/chores
  /// - Body: assigneeId, choreType (ChoreType enum 문자열), date (yyyy-MM-dd)
  Future<ChoreMutationResponseModel> registerManualChore({
    required int assigneeId,
    required String choreType,
    required String date,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.choresCollectionEndpoint,
        data: {
          'assigneeId': assigneeId,
          'choreType': choreType,
          'date': date,
        },
      );
      return ChoreMutationResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 날짜별 집안일 목록 (전용 chore 리스트)
  /// - API: GET /api/chores/daily?date=
  Future<ChoreDailyListResponseModel> fetchDailyChores({
    required String date,
  }) async {
    try {
      final response = await _apiClient.get(
        AppConfig.choresDailyEndpoint,
        queryParameters: {'date': date},
      );
      return ChoreDailyListResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 담당자·날짜 수정 (전달한 필드만 반영)
  /// - API: PATCH /api/chores/{choreId}
  ///
  /// 참고: [updateChoreCompletion] 의 미완료 처리도 동일 PATCH 경로를 쓰는 경우,
  /// 백엔드 명세와 충돌할 수 있으니 서버 스펙에 맞게 조정합니다.
  Future<ChoreMutationResponseModel> updateChoreAssignment({
    required int choreId,
    int? assigneeId,
    String? date,
  }) async {
    try {
      final endpoint = AppConfig.choreDetailEndpoint.replaceAll(
        '{choreId}',
        choreId.toString(),
      );
      final body = <String, dynamic>{
        if (assigneeId != null) 'assigneeId': assigneeId,
        if (date != null) 'date': date,
      };
      if (body.isEmpty) {
        throw ArgumentError(
          'updateChoreAssignment: assigneeId 또는 date 중 하나는 필요합니다.',
        );
      }
      final response = await _apiClient.patch(endpoint, data: body);
      return ChoreMutationResponseModel.fromJson(response.data);
    } catch (e) {
      if (e is ArgumentError) rethrow;
      throw ApiException.fromDioError(e);
    }
  }

  /// 집안일 삭제
  /// - API: DELETE /api/chores/{choreId}
  Future<ScheduleResponseModel> deleteChore({
    required int choreId,
  }) async {
    try {
      final endpoint = AppConfig.choreDetailEndpoint.replaceAll(
        '{choreId}',
        choreId.toString(),
      );
      final response = await _apiClient.delete(endpoint);
      return ScheduleResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 집안일 완료·미완료 토글 (일간 캘린더)
  /// - 완료: PATCH /api/chores/{choreId}/complete (본문 없음)
  /// - 미완료: PATCH /api/chores/{choreId} … `{ "isCompleted": false }`
  Future<ScheduleResponseModel> updateChoreCompletion({
    required int choreId,
    required bool isCompleted,
  }) async {
    try {
      if (isCompleted) {
        final endpoint = AppConfig.choreCompleteEndpoint.replaceAll(
          '{choreId}',
          choreId.toString(),
        );
        final response = await _apiClient.patch(endpoint);
        return ScheduleResponseModel.fromJson(response.data);
      }

      final endpoint = AppConfig.choreDetailEndpoint.replaceAll(
        '{choreId}',
        choreId.toString(),
      );
      final response = await _apiClient.patch(
        endpoint,
        data: {'isCompleted': false},
      );
      return ScheduleResponseModel.fromJson(response.data);
    } catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}

