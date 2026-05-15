import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/utility_bill_model.dart';
import 'package:partition_app/features/partition/services/utility_bill_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/partition/utils/supply_purchase_input.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';

/// 알림「이번달 공과금을 입력해주세요」탭 시 — 이번 달 금액 PATCH 입력 (글래스 모달).
class UtilityBillMonthlyAmountModal extends StatefulWidget {
  const UtilityBillMonthlyAmountModal({
    super.key,
    required this.billId,
  });

  final int billId;

  @override
  State<UtilityBillMonthlyAmountModal> createState() =>
      _UtilityBillMonthlyAmountModalState();
}

class _UtilityBillMonthlyAmountModalState
    extends State<UtilityBillMonthlyAmountModal> {
  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    fontFamily: 'Pretendard Variable',
    height: 1.15,
  );

  final UtilityBillService _billService = UtilityBillService();
  final TextEditingController _amountCtrl = TextEditingController();

  UtilityBillListItem? _bill;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBill();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  static String _dateToIsoYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String currentYearMonth() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadBill() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      final bills = await _billService.fetchBills(
        startDate: _dateToIsoYmd(start),
        endDate: _dateToIsoYmd(end),
      );
      UtilityBillListItem? found;
      for (final b in bills) {
        if (b.billId == widget.billId) {
          found = b;
          break;
        }
      }
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _loading = false;
          _loadError = '공과금 정보를 찾지 못했어요.';
        });
        return;
      }
      final prefill = found.thisMonthAmount ?? found.amount;
      if (prefill != null && prefill > 0) {
        _amountCtrl.text = prefill.toString();
      }
      setState(() {
        _bill = found;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '공과금 정보를 불러오지 못했어요.';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || _bill == null) return;
    final amount = tryParseWonAmount(_amountCtrl.text);
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('금액은 1원 이상의 정수로 입력해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _billService.patchBillVariableAmount(
        billId: widget.billId,
        yearMonth: currentYearMonth(),
        thisMonthAmount: amount,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('금액 저장에 실패했어요. 잠시 후 다시 시도해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = (screenW - 40).clamp(300.0, 350.0);
    final bill = _bill;
    final billLabel = bill == null
        ? null
        : (bill.utilityTypeName.isNotEmpty
            ? bill.utilityTypeName
            : bill.utilityType);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        constraints: BoxConstraints.tightFor(width: dialogW),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        borderColor: Colors.white.withOpacity(0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '이번 달 공과금',
                textAlign: TextAlign.center,
                style: _titleStyle,
              ),
              const SizedBox(height: 10),
              Text(
                bill != null
                    ? '$billLabel · ${currentYearMonth()}'
                        '${bill.isFixed ? '' : ' · 변동'}'
                        ' · 매월 ${bill.payDay}일'
                    : '금액을 입력하면 룸메이트와 공유돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                )
              else if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadBill,
                        child: const Text(
                          '다시 불러오기',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                _glassAmountField(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: '취소',
                      primary: false,
                      onTap: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      label: '저장하기',
                      primary: true,
                      onTap: (_loading ||
                              _loadError != null ||
                              _submitting ||
                              _bill == null)
                          ? null
                          : _submit,
                      loading: _submitting,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassAmountField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.42)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.16),
                Colors.white.withOpacity(0.05),
              ],
            ),
          ),
          child: TextField(
            controller: _amountCtrl,
            enabled: !_submitting,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'Pretendard Variable',
            ),
            decoration: InputDecoration(
              hintText: '납부 금액 입력',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 14,
              ),
              suffixText: '원',
              suffixStyle: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
                fontFamily: 'Pretendard Variable',
              ),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required bool primary,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Opacity(
            opacity: onTap != null ? 1 : 0.48,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  PartitionUiTokens.actionButtonRadius,
                ),
                border: Border.all(
                  color: primary
                      ? PartitionUiTokens.actionButtonBorder
                      : Colors.white.withOpacity(0.35),
                ),
                color: primary
                    ? PartitionUiTokens.actionButtonFill
                    : Colors.white.withOpacity(0.08),
              ),
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: primary
                            ? PartitionUiTokens.actionText
                            : Colors.white.withOpacity(0.92),
                        fontSize: PartitionUiTokens.actionFontSize,
                        fontWeight: PartitionUiTokens.actionWeight,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 알림 패널·FCM에서 공과금 금액 입력 모달을 띄웁니다. 저장 성공 시 `true`.
Future<bool?> showUtilityBillMonthlyAmountModal(
  BuildContext context, {
  required int billId,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (ctx) => UtilityBillMonthlyAmountModal(billId: billId),
  );
}
