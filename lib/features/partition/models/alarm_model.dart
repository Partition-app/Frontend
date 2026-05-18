/// GET /api/alarms — `type` 문자열 매핑
enum AlarmNoticeType {
  supplySettlementRequested(
    'SUPPLY_SETTLEMENT_REQUESTED',
    '공동 구매 정산이 요청되었습니다.',
  ),
  supplySettlementConfirmed(
    'SUPPLY_SETTLEMENT_CONFIRMED',
    '공동 구매 정산이 완료되었습니다.',
  ),
  billSettlementRequested(
    'BILL_SETTLEMENT_REQUESTED',
    '공과금 정산이 요청되었습니다.',
  ),
  billSettlementConfirmed(
    'BILL_SETTLEMENT_CONFIRMED',
    '공과금 정산이 완료되었습니다.',
  ),
  /// 매월 공과금 알림 (`referenceId` = `billId`)
  billPaymentReminder(
    'BILL_PAYMENT_REMINDER',
    '이번 달 공과금 금액을 입력해주세요.',
  ),
  choreAssigned(
    'CHORE_ASSIGNED',
    '{name}님의 새로운 집안일이 등록되었습니다.',
  ),
  choreUpdated(
    'CHORE_UPDATED',
    '{name}님의 집안일이 수정되었습니다.',
  ),
  choreDeleted(
    'CHORE_DELETED',
    '{name}님의 집안일이 삭제되었습니다.',
  ),
  unknown('', '');

  const AlarmNoticeType(this.apiValue, this.defaultMessage);
  final String apiValue;
  final String defaultMessage;

  static AlarmNoticeType parse(String? raw) {
    if (raw == null || raw.isEmpty) return AlarmNoticeType.unknown;
    if (raw == 'BILL_AMOUNT_INPUT_REQUIRED') {
      return AlarmNoticeType.billPaymentReminder;
    }
    for (final v in AlarmNoticeType.values) {
      if (v.apiValue == raw) return v;
    }
    return AlarmNoticeType.unknown;
  }

  bool get isChoreNotice =>
      this == AlarmNoticeType.choreAssigned ||
      this == AlarmNoticeType.choreUpdated ||
      this == AlarmNoticeType.choreDeleted;

  /// 스펙 Enum 문구 우선. 집안일·개인화 문구는 서버 `message` 우선.
  String resolvedMessage(String? serverMessage) {
    if (this == AlarmNoticeType.unknown) return serverMessage ?? '';
    final trimmed = serverMessage?.trim();
    if (isChoreNotice || defaultMessage.contains('{name}')) {
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return defaultMessage.isNotEmpty ? defaultMessage : (serverMessage ?? '');
  }

  /// 정산 **완료** 알림 — 공동 구매는 읽음 + 이 타입일 때 체크.
  /// 공과금은 `billSettlementConfirmed` 또는 클라이언트가 확인한 확정 정산번호도 체크(메인 패널).
  bool get isSettlementCompletionNotice =>
      this == AlarmNoticeType.supplySettlementConfirmed ||
      this == AlarmNoticeType.billSettlementConfirmed;

  bool get isSettlementRequestNotice =>
      this == AlarmNoticeType.supplySettlementRequested ||
      this == AlarmNoticeType.billSettlementRequested;

  /// 서버 `type` 미등록 시 알림 문구로 공과금 금액 입력 알림을 추정합니다.
  static bool messageLooksLikeUtilityBillAmountInput(String message) {
    final n = message.replaceAll(RegExp(r'\s+'), '');
    if (n.isEmpty) return false;
    final hasBill = n.contains('공과금');
    final asksInput =
        n.contains('입력') || n.contains('입력해') || n.contains('입력해주');
    final hasMonth = n.contains('이번달') || n.contains('이번');
    return hasBill && asksInput && (hasMonth || n.contains('금액'));
  }
}

class AlarmItem {
  const AlarmItem({
    required this.alarmId,
    required this.type,
    required this.message,
    required this.referenceId,
    required this.isRead,
    required this.createdAt,
  });

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString();
    final noticeType = AlarmNoticeType.parse(typeStr);
    return AlarmItem(
      alarmId: (json['alarmId'] as num?)?.toInt() ?? 0,
      type: noticeType,
      message: json['message']?.toString() ?? '',
      referenceId: (json['referenceId'] as num?)?.toInt(),
      isRead: json['isRead'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int alarmId;
  final AlarmNoticeType type;
  final String message;
  /// 정산 관련 알림일 때 settlementId 로 사용 (백엔드 스펙)
  final int? referenceId;
  final bool isRead;
  final DateTime createdAt;

  String get displayMessage => type.resolvedMessage(message);

  /// 이번 달 공과금 금액 입력 모달을 열 수 있는 알림인지 여부.
  bool get isUtilityBillAmountInputReminder {
    if (type == AlarmNoticeType.billPaymentReminder) return true;
    final text = message.isNotEmpty ? message : displayMessage;
    if (!AlarmNoticeType.messageLooksLikeUtilityBillAmountInput(text)) {
      return false;
    }
    // 정산 알림 문구와 구분 — `referenceId`가 billId일 때만 모달로 연결
    return referenceId != null && referenceId! > 0;
  }

  /// [isUtilityBillAmountInputReminder]일 때 `referenceId`를 `billId`로 사용합니다.
  int? get utilityBillIdForAmountInput {
    if (!isUtilityBillAmountInputReminder) return null;
    final id = referenceId;
    if (id == null || id <= 0) return null;
    return id;
  }

  AlarmItem copyWith({bool? isRead}) {
    return AlarmItem(
      alarmId: alarmId,
      type: type,
      message: message,
      referenceId: referenceId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class AlarmListResult {
  const AlarmListResult({
    required this.alarms,
    required this.unreadCount,
  });

  final List<AlarmItem> alarms;
  final int unreadCount;
}
