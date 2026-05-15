import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/utility_bill_model.dart';

/// 공과금 API (`/bills/**`, 종류 조회 포함)
class UtilityBillService {
  final ApiClient _apiClient = ApiClient();

  /// 해당 기간 `GET /bills/payments` 결과 중 선택한 공과금(`billIds`)의
  /// `UNSETTLED` 납부 기록 `paymentId` (정산 POST 본문에 사용).
  Future<List<int>> fetchUnsettledPaymentIds({
    required String startDate,
    required String endDate,
    required Iterable<int> billIds,
  }) async {
    final want = billIds.map((e) => e).where((id) => id > 0).toSet();
    if (want.isEmpty) return [];
    final bundle = await fetchBillPayments(startDate: startDate, endDate: endDate);
    final out = <int>[];
    for (final p in bundle.payments) {
      if (!want.contains(p.billId)) continue;
      if (p.paymentId <= 0) continue;
      if (p.status != 'UNSETTLED') continue;
      out.add(p.paymentId);
    }
    return out;
  }
  Future<List<UtilityBillCategory>> fetchCategories() async {
    try {
      final response =
          await _apiClient.get(AppConfig.billsCategoriesEndpoint);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 카테고리 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message:
              data['message']?.toString() ?? '공과금 카테고리 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! List) return [];
      return raw
          .map((e) => UtilityBillCategory.fromJson(e as Map<String, dynamic>))
          .where((c) => c.category.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<UtilityBillListItem>> fetchBills({
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _apiClient.get(
        AppConfig.billsEndpoint,
        queryParameters: {
          'startDate': startDate,
          'endDate': endDate,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 목록 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 목록 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! List) return [];
      return raw
          .map((e) => UtilityBillListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET `/api/bills/payments` — 공과금 납부 기록
  Future<UtilityBillPaymentsResult> fetchBillPayments({
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _apiClient.get(
        AppConfig.billsPaymentsEndpoint,
        queryParameters: {
          'startDate': startDate,
          'endDate': endDate,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 납부 기록 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message:
              data['message']?.toString() ?? '공과금 납부 기록 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 납부 기록 결과 형식이 올바르지 않습니다.');
      }
      return UtilityBillPaymentsResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// PATCH `/api/bills/{billId}/payments/{yearMonth}/amount` (`yyyy-MM`)
  Future<UtilityBillVariableAmountPatchResult> patchBillVariableAmount({
    required int billId,
    required String yearMonth,
    required int thisMonthAmount,
  }) async {
    if (billId <= 0) {
      throw ApiException(message: '유효하지 않는 공과금입니다.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.billsBillPaymentAmountPath(billId, yearMonth),
        data: {'thisMonthAmount': thisMonthAmount},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 금액 입력 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 금액 입력에 실패했습니다.',
          statusCode: response.statusCode,
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 금액 입력 결과가 비어 있습니다.');
      }
      return UtilityBillVariableAmountPatchResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// PATCH `/api/bills/payments/{paymentId}/settlement-status` (본문 명세 미정 — 서버 규격에 맞춰 확장 가능)
  Future<void> patchBillPaymentSettlementStatus(
    int paymentId, [
    Map<String, dynamic>? body,
  ]) async {
    if (paymentId <= 0) {
      throw ApiException(message: '유효하지 않는 납부 기록입니다.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.billsPaymentSettlementStatusPath(paymentId),
        data: body,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '정산 상태 변경 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '정산 상태 변경에 실패했습니다.',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /api/bills — 수동 등록 (`payDay`: 매달 해당 일에 결제)
  Future<UtilityBillCreateResult> createBill({
    required String utilityType,
    required int payDay,
    required bool isFixed,
    int? amount,
    String? note,
  }) async {
    try {
      final payload = <String, dynamic>{
        'utilityType': utilityType,
        'payDay': payDay,
        'isFixed': isFixed,
        'amount': amount,
        'note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      };
      final response = await _apiClient.post(
        AppConfig.billsEndpoint,
        data: payload,
      );
      final data = response.data;     
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 등록 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 등록에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 등록 결과가 비어 있습니다.');
      }
      return UtilityBillCreateResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// PATCH /api/bills/{billId}
  Future<UtilityBillCreateResult> updateBill({
    required int billId,
    required String utilityType,
    required int payDay,
    required bool isFixed,
    int? amount,
    String? note,
  }) async {
    try {
      final payload = <String, dynamic>{
        'utilityType': utilityType,
        'payDay': payDay,
        'isFixed': isFixed,
        'amount': amount,
        'note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      };
      final response = await _apiClient.patch(
        AppConfig.billsBillPath(billId),
        data: payload,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 수정 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 수정에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 수정 결과가 비어 있습니다.');
      }
      return UtilityBillCreateResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// DELETE /api/bills/{billId}
  Future<void> deleteBill(int billId) async {
    try {
      final response =
          await _apiClient.delete(AppConfig.billsBillPath(billId));
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 삭제 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 삭제에 실패했습니다.',
        );
      }
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /api/bills/settlement/list
  Future<UtilityBillSettlementSummary> fetchSettlementList({
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _apiClient.get(
        AppConfig.billsSettlementListEndpoint,
        queryParameters: {
          'startDate': startDate,
          'endDate': endDate,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(
          message: '공과금 정산 목록 응답 형식이 올바르지 않습니다.',
        );
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message:
              data['message']?.toString() ?? '공과금 정산 목록 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 목록 결과가 비어 있습니다.');
      }
      return UtilityBillSettlementSummary.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 공과금 **정산 요청** — `POST /api/bills/settlement` (`paymentIds`, `memberIds`).
  /// 푸시 알림은 서버에서 발송; 단말은 `PATCH /users/me/fcm-token`으로 FCM 토큰을 등록해야 함.
  Future<BillSettlementRequestResult> requestBillSettlement({
    required List<int> paymentIds,
    required List<int> memberIds,
  }) async {
    if (paymentIds.isEmpty) {
      throw ApiException(message: '정산할 공과금을 선택해주세요.');
    }
    if (memberIds.isEmpty) {
      throw ApiException(message: '정산 대상 멤버를 선택해주세요.');
    }
    try {
      final response = await _apiClient.post(
        AppConfig.billsSettlementRequestEndpoint,
        data: {
          'paymentIds': paymentIds,
          'memberIds': memberIds,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 요청 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 정산 요청에 실패했습니다.',
          statusCode: response.statusCode,
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 요청 결과가 없습니다.');
      }
      return BillSettlementRequestResult.fromJson(raw);
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 정산 **상세** 조회 (GET `/bills/settlement/{settlementId}`)
  Future<BillSettlementDetailResult> fetchBillSettlementDetail(
    int settlementId,
  ) async {
    if (settlementId <= 0) {
      throw ApiException(message: '유효하지 않은 정산입니다.');
    }
    try {
      final response = await _apiClient.get(
        AppConfig.billsSettlementDetailPath(settlementId),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 상세 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 정산 상세 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 상세 결과가 없습니다.');
      }
      return BillSettlementDetailResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 정산 **완료** 처리 (PATCH `/bills/settlement/{settlementId}/confirm`)
  Future<BillSettlementConfirmResult> confirmBillSettlement(
    int settlementId,
  ) async {
    if (settlementId <= 0) {
      throw ApiException(message: '유효하지 않은 정산입니다.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.billsSettlementConfirmPath(settlementId),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 완료 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '공과금 정산 완료 처리에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '공과금 정산 완료 결과가 없습니다.');
      }
      return BillSettlementConfirmResult.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
