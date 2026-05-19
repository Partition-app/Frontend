import 'package:dio/dio.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_client.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/reservation_booking_model.dart';

/// 예약 목록 조회·등록·삭제 (`GET`·`POST`·`DELETE /api/reservations`)
class ReservationsService {
  final ApiClient _apiClient = ApiClient();

  static String _yyyyMmDd(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// API 요청용 `LocalDateTime` 문자열 (분 단위 포함, `yyyy-MM-ddTHH:mm:ss`)
  static String toApiLocalDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
    return '${d.year}-${two(d.month)}-${two(d.day)}T'
        '${two(d.hour)}:${two(d.minute)}:00';
  }

  static const String conflictErrorCode = 'RESERVATION_2005';
  static const String conflictErrorMessage = '해당 시간에 이미 예약이 존재합니다.';

  /// [startA, endA) 와 [startB, endB) 구간이 겹치는지
  static bool intervalsOverlap({
    required DateTime startA,
    required DateTime endA,
    required DateTime startB,
    required DateTime endB,
  }) {
    return startA.isBefore(endB) && startB.isBefore(endA);
  }

  /// 동일 예약 대상과 시간이 겹치면 true
  Future<bool> hasConflictingReservation({
    required int itemId,
    String? itemName,
    required DateTime startTime,
    required DateTime endTime,
    int? excludeReservationId,
  }) async {
    final startDay = DateTime(startTime.year, startTime.month, startTime.day);
    final endDay = DateTime(endTime.year, endTime.month, endTime.day);
    final list = await fetchReservations(
      startDate: startDay,
      endDate: endDay,
    );
    for (final r in list) {
      if (excludeReservationId != null &&
          r.reservationId == excludeReservationId) {
        continue;
      }
      final sameItem = itemId > 0 && r.itemId > 0
          ? r.itemId == itemId
          : (itemName != null && r.itemName == itemName);
      if (!sameItem) continue;
      if (intervalsOverlap(
        startA: startTime,
        endA: endTime,
        startB: r.startTime,
        endB: r.endTime,
      )) {
        return true;
      }
    }
    return false;
  }

  /// `GET ?startDate&endDate` (yyyy-MM-dd)
  Future<List<ReservationListEntry>> fetchReservations({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    try {
      final response = await _apiClient.get(
        AppConfig.reservationsEndpoint,
        queryParameters: <String, dynamic>{
          'startDate': _yyyyMmDd(s),
          'endDate': _yyyyMmDd(e),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '예약 목록 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '예약 목록 조회에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! List) return [];
      return raw
          .map((e) => ReservationListEntry.fromJson(e as Map<String, dynamic>))
          .where((r) => r.reservationId > 0 && r.itemName.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<ReservationCreated> createReservation({
    required int itemId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.reservationsEndpoint,
        data: <String, dynamic>{
          'itemId': itemId,
          'startTime': toApiLocalDateTime(startTime),
          'endTime': toApiLocalDateTime(endTime),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '예약 등록 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '예약 등록에 실패했습니다.',
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '예약 등록 결과가 비어 있습니다.');
      }
      return ReservationCreated.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// `PATCH /api/reservations/{reservationId}/complete`
  Future<ReservationCompleted> completeReservation(int reservationId) async {
    if (reservationId <= 0) {
      throw ApiException(message: '완료 처리할 예약을 선택해주세요.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.reservationsCompletePath(reservationId),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '예약 완료 처리 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '예약 완료 처리에 실패했습니다.',
          code: data['code']?.toString(),
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '예약 완료 처리 결과가 비어 있습니다.');
      }
      return ReservationCompleted.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// `PATCH /api/reservations/{reservationId}`
  Future<ReservationCreated> updateReservation({
    required int reservationId,
    int? itemId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (reservationId <= 0) {
      throw ApiException(message: '수정할 예약을 선택해주세요.');
    }
    final body = <String, dynamic>{};
    if (itemId != null) body['itemId'] = itemId;
    if (startTime != null) {
      body['startTime'] = toApiLocalDateTime(startTime);
    }
    if (endTime != null) body['endTime'] = toApiLocalDateTime(endTime);
    if (body.isEmpty) {
      throw ApiException(message: '수정할 내용이 없습니다.');
    }
    try {
      final response = await _apiClient.patch(
        AppConfig.reservationsDetailPath(reservationId),
        data: body,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '예약 수정 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '예약 수정에 실패했습니다.',
          code: data['code']?.toString(),
        );
      }
      final raw = data['result'];
      if (raw is! Map<String, dynamic>) {
        throw ApiException(message: '예약 수정 결과가 비어 있습니다.');
      }
      return ReservationCreated.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// 본문 `{ reservationIds: [...] }` — 다중 삭제
  Future<void> deleteReservations(List<int> reservationIds) async {
    if (reservationIds.isEmpty) {
      throw ApiException(message: '삭제할 예약을 선택해주세요.');
    }
    try {
      final response = await _apiClient.delete(
        AppConfig.reservationsEndpoint,
        data: <String, dynamic>{
          'reservationIds': reservationIds,
        },
      );
      final data = response.data;
      if (data == null || data == '') {
        return;
      }
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: '예약 삭제 응답 형식이 올바르지 않습니다.');
      }
      if (data['isSuccess'] != true) {
        throw ApiException(
          message: data['message']?.toString() ?? '예약 삭제에 실패했습니다.',
        );
      }
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
