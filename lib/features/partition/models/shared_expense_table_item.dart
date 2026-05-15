/// 공용 소비 표 한 줄 (물품 구매 / 공과금 공통).
class SharedExpenseTableItem {
  final String name;
  final String date;
  final String amount;
  final String? quantity;
  final bool manuallySettled;

  /// 물품 API (`purchaseId`)
  final int? purchaseId;
  final String? categoryCode;
  final String? subCategoryCode;

  final String? majorCategory;
  final String? minorCategory;
  final String? detail;

  /// 공과금 API (`billId`, `utilityType`, 매월 결제일 1–31)
  final int? billId;
  /// 납부 기록 ID (`GET /bills/payments`, 정산 요청 등)
  final int? paymentId;
  final String? utilityTypeEnum;
  /// 고정 공과금 여부 (목록에서 온 행만; null 이면 구버전/미표시).
  final bool? utilityIsFixed;
  /// 구버전 세부 일자(있을 때만). 신규 API는 [utilityPayDay] 사용.
  final String? utilityDueDateIso;
  /// 매달 결제일(1–31). API `payDay`와 동일.
  final int? utilityPayDay;

  const SharedExpenseTableItem({
    required this.name,
    required this.date,
    required this.amount,
    this.quantity,
    this.manuallySettled = false,
    this.purchaseId,
    this.categoryCode,
    this.subCategoryCode,
    this.majorCategory,
    this.minorCategory,
    this.detail,
    this.billId,
    this.paymentId,
    this.utilityTypeEnum,
    this.utilityIsFixed,
    this.utilityDueDateIso,
    this.utilityPayDay,
  });

  /// 목록·정산 선택 UI 등에서 쓰는 표시명 (구조화된 물품 행은 세부 품목명 우선).
  String get displayLabel {
    final d = detail?.trim();
    if (d != null && d.isNotEmpty) return d;
    return name;
  }

  SharedExpenseTableItem copyWith({
    String? name,
    String? date,
    String? amount,
    String? quantity,
    bool? manuallySettled,
    int? purchaseId,
    String? categoryCode,
    String? subCategoryCode,
    String? majorCategory,
    String? minorCategory,
    String? detail,
    int? billId,
    int? paymentId,
    String? utilityTypeEnum,
    bool? utilityIsFixed,
    String? utilityDueDateIso,
    int? utilityPayDay,
  }) {
    return SharedExpenseTableItem(
      name: name ?? this.name,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      manuallySettled: manuallySettled ?? this.manuallySettled,
      purchaseId: purchaseId ?? this.purchaseId,
      categoryCode: categoryCode ?? this.categoryCode,
      subCategoryCode: subCategoryCode ?? this.subCategoryCode,
      majorCategory: majorCategory ?? this.majorCategory,
      minorCategory: minorCategory ?? this.minorCategory,
      detail: detail ?? this.detail,
      billId: billId ?? this.billId,
      paymentId: paymentId ?? this.paymentId,
      utilityTypeEnum: utilityTypeEnum ?? this.utilityTypeEnum,
      utilityIsFixed: utilityIsFixed ?? this.utilityIsFixed,
      utilityDueDateIso: utilityDueDateIso ?? this.utilityDueDateIso,
      utilityPayDay: utilityPayDay ?? this.utilityPayDay,
    );
  }
}
