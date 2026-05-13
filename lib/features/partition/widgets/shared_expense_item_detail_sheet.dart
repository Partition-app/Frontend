import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:partition_app/features/partition/models/shared_expense_table_item.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 공용소비 표 — 항목명 탭 시 상세(분류·AI 더미·정산 여부)
class SharedExpenseItemDetailSheet extends StatefulWidget {
  final SharedExpenseTableItem item;
  final bool isUtility;
  /// 정산 요청 버튼 액션
  final Future<void> Function()? onSettlementRequest;
  /// 정산 완료 처리 버튼 액션
  final Future<void> Function()? onSettlementComplete;
  /// 시트를 닫은 뒤 내역 수정 다이얼로그를 연다
  final VoidCallback? onEditRequested;
  /// 시트를 닫은 뒤 삭제 확인·처리
  final Future<void> Function()? onDeleteRequested;

  const SharedExpenseItemDetailSheet({
    super.key,
    required this.item,
    required this.isUtility,
    this.onSettlementRequest,
    this.onSettlementComplete,
    this.onEditRequested,
    this.onDeleteRequested,
  });

  @override
  State<SharedExpenseItemDetailSheet> createState() =>
      _SharedExpenseItemDetailSheetState();
}

class _SharedExpenseItemDetailSheetState
    extends State<SharedExpenseItemDetailSheet> {
  late bool _settled;
  bool _requestingSettlement = false;
  bool _completingSettlement = false;

  @override
  void initState() {
    super.initState();
    _settled = widget.item.manuallySettled;
  }

  @override
  void didUpdateWidget(SharedExpenseItemDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.purchaseId != widget.item.purchaseId ||
        oldWidget.item.billId != widget.item.billId ||
        oldWidget.item.manuallySettled != widget.item.manuallySettled ||
        oldWidget.item.name != widget.item.name) {
      _settled = widget.item.manuallySettled;
    }
  }

  /// 항상 `대분류 > 소분류` 형태 (없으면 `—` 자리 표시)
  String get _categoryLine {
    final m = widget.item.majorCategory?.trim();
    final s = widget.item.minorCategory?.trim();
    final major = (m != null && m.isNotEmpty) ? m : '—';
    final minor = (s != null && s.isNotEmpty) ? s : '—';
    return '$major > $minor';
  }

  String get _amountQtyLine {
    final a = widget.item.amount.trim();
    final q = widget.item.quantity?.trim();
    if (q == null || q.isEmpty) return a;
    return '$a, $q';
  }

  String get _displayDateLine {
    final raw = widget.item.date.trim();
    if (raw.isEmpty) return raw;

    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (isoMatch != null) {
      return '${isoMatch.group(1)}.${isoMatch.group(2)}.${isoMatch.group(3)}.';
    }

    final dottedMatch =
        RegExp(r'^(\d{2}|\d{4})\.(\d{2})\.(\d{2})\.$').firstMatch(raw);
    if (dottedMatch != null) {
      final year = dottedMatch.group(1)!;
      final normalizedYear = year.length == 2 ? '20$year' : year;
      return '$normalizedYear.${dottedMatch.group(2)}.${dottedMatch.group(3)}.';
    }

    return raw;
  }

  String get _dummyAiBlock {
    if (widget.isUtility) {
      return '이 항목은 공과금 성격의 고정·주기 청구로 추정돼요.\n'
          '납부 주기와 금액 변동을 다음 달 예산에 반영해 보세요.';
    }
    return '해당 용품은 30일에 한 번 정도 구매하고 있네요!\n'
        '평균 구매 가격은 약 ${widget.item.amount}이고,\n'
        '저번 달에는 특히 빠른 주기로 구매했어요.';
  }

  Future<void> _handleSettlementRequest() async {
    final action = widget.onSettlementRequest;
    if (action == null || _requestingSettlement || _completingSettlement) return;
    setState(() => _requestingSettlement = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _requestingSettlement = false);
      }
    }
  }

  Future<void> _handleSettlementComplete() async {
    final action = widget.onSettlementComplete;
    if (action == null || _requestingSettlement || _completingSettlement) return;
    setState(() => _completingSettlement = true);
    try {
      await action();
      if (mounted) {
        setState(() => _settled = true);
      }
    } finally {
      if (mounted) {
        setState(() => _completingSettlement = false);
      }
    }
  }

  Widget _buildSettlementActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger
            ? const Color.fromRGBO(255, 180, 180, 1.0)
            : Colors.white,
        side: BorderSide(
          color: danger
              ? Colors.redAccent.withOpacity(0.55)
              : Colors.white.withOpacity(onPressed == null ? 0.18 : 0.45),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onPressed == null
              ? Colors.white.withOpacity(0.42)
              : (danger
                    ? const Color.fromRGBO(255, 180, 180, 1.0)
                    : Colors.white),
          fontWeight: FontWeight.w600,
          fontFamily: 'Pretendard Variable',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.45), width: 0.5),
            gradient: const RadialGradient(
              center: Alignment(-0.12, -0.12),
              radius: 1.7,
              colors: [
                Color.fromRGBO(255, 255, 255, 0.14),
                Color.fromRGBO(255, 255, 255, 0.08),
              ],
              stops: [0.0, 1.0],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(255, 255, 255, 0.12),
                offset: Offset(0, -4),
                blurRadius: 24,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.item.displayLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Pretendard Variable',
                              height: 1.25,
                            ),
                          ),
                        ),
                        PartitionModalCloseButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _displayDateLine,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _amountQtyLine,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!widget.isUtility) ...[
                      Text(
                        _categoryLine,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.onEditRequested != null ||
                        widget.onDeleteRequested != null) ...[
                      Row(
                        children: [
                          if (widget.onEditRequested != null)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onEditRequested!();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  '수정',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ),
                            ),
                          if (widget.onEditRequested != null &&
                              widget.onDeleteRequested != null)
                            const SizedBox(width: 10),
                          if (widget.onDeleteRequested != null)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final del = widget.onDeleteRequested!;
                                  Navigator.of(context).pop();
                                  await del();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      const Color.fromRGBO(255, 180, 180, 1.0),
                                  side: BorderSide(
                                    color: Colors.redAccent.withOpacity(0.55),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  '삭제',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'AI 분석',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withOpacity(0.06),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                        ),
                      ),
                      child: Text(
                        _dummyAiBlock,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '정산 관리',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _settled ? '정산 완료' : '정산 전',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _settled
                                      ? '이 항목은 정산이 끝났어요.'
                                      : '정산 요청과 완료 처리를 구분해서 진행할 수 있어요.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.62),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSettlementActionButton(
                            label: _requestingSettlement ? '요청 중...' : '정산 요청',
                            onPressed: _settled
                                ? null
                                : () {
                                    _handleSettlementRequest();
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSettlementActionButton(
                            label: _completingSettlement
                                ? '처리 중...'
                                : (_settled ? '정산 완료됨' : '정산 완료 처리'),
                            onPressed: _settled
                                ? null
                                : () {
                                    _handleSettlementComplete();
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
