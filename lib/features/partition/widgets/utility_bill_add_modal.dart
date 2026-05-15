import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/shared_expense_table_item.dart';
import 'package:partition_app/features/partition/models/utility_bill_model.dart';
import 'package:partition_app/features/partition/services/utility_bill_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/partition/widgets/utility_pay_day_glass_picker.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';

/// 공과금 추가하기 — 더미: 항목 다중 선택 + 매월 납부일 / API: 카테고리 조회 + 매달 payDay + POST
class UtilityBillAddModal extends StatefulWidget {
  final bool useBillsApi;
  final UtilityBillService? billService;

  /// 더미 모드: 표 항목명 중복 방지
  final Set<String> existingItemNames;

  /// API 모드: `utilityType_payDay` 중복 방지
  final Set<String> existingBillKeys;

  final void Function(List<SharedExpenseTableItem> items) onLocalConfirm;
  final Future<void> Function()? onApiCreated;

  const UtilityBillAddModal({
    super.key,
    required this.useBillsApi,
    this.billService,
    required this.existingItemNames,
    required this.existingBillKeys,
    required this.onLocalConfirm,
    this.onApiCreated,
  }) : assert(!useBillsApi || billService != null);

  @override
  State<UtilityBillAddModal> createState() => _UtilityBillAddModalState();
}

class _UtilityBillAddModalState extends State<UtilityBillAddModal> {
  static const _localCategoryLabels = <String>[
    '수도세',
    '전기세',
    '가스비',
    '인터넷',
    '월세',
    '대출 이자',
    '기타',
  ];

  List<UtilityBillCategory> _apiCategories =
      UtilityBillCategory.fallbackCategories;
  bool _categoriesLoading = false;

  final Set<String> _selectedLocal = {};
  final Set<String> _selectedCodes = {};

  int _paymentDay = 1;
  bool _utilityBillFixedType = true;

  bool _submitting = false;

  final TextEditingController _otherCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.useBillsApi) {
      _loadCategoriesIfApi();
    }
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    _amountCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesIfApi() async {
    final svc = widget.billService;
    if (svc == null) return;
    setState(() => _categoriesLoading = true);
    try {
      final list = await svc.fetchCategories();
      if (!mounted) return;
      setState(() {
        _apiCategories = list.isNotEmpty ? list : UtilityBillCategory.fallbackCategories;
        _categoriesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiCategories = UtilityBillCategory.fallbackCategories;
        _categoriesLoading = false;
      });
    }
  }

  /// 표 금액 열과 동일하게 천 단위 콤마 + 원
  static String _formatWonForTable(int won) {
    final n = won < 0 ? 0 : won;
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${buf.toString()}원';
  }

  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    fontFamily: 'Pretendard Variable',
    height: 1.15,
  );

  void _toggleLocal(String label) {
    setState(() {
      if (_selectedLocal.contains(label)) {
        _selectedLocal.remove(label);
      } else {
        _selectedLocal.add(label);
      }
    });
  }

  void _toggleCode(String code) {
    setState(() {
      if (_selectedCodes.contains(code)) {
        _selectedCodes.remove(code);
      } else {
        _selectedCodes.add(code);
      }
    });
  }

  Future<void> _submit() async {
    if (widget.useBillsApi) {
      await _submitApi();
    } else {
      _submitLocal();
    }
  }

  Future<void> _submitApi() async {
    final svc = widget.billService;
    if (svc == null) return;

    if (_selectedCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('항목을 하나 이상 선택해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final amountDigits =
        _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
    int? amountInt;
    if (amountDigits.isNotEmpty) {
      amountInt = int.tryParse(amountDigits);
      if (amountInt == null || amountInt < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('금액은 1원 이상의 정수로 입력해 주세요.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    final noteTrim = _remarkCtrl.text.trim();
    final payDay = _paymentDay.clamp(1, 31);
    final toCreate = _selectedCodes.toList();
    final skipped = <String>[];
    for (final code in List<String>.from(toCreate)) {
      final key = '${code}_$payDay';
      if (widget.existingBillKeys.contains(key)) {
        skipped.add(code);
        toCreate.remove(code);
      }
    }

    if (toCreate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped.isEmpty
                ? '추가할 항목이 없어요.'
                : '같은 종류·같은 결제일은 이미 있어 제외했어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      for (final code in toCreate) {
        await svc.createBill(
          utilityType: code,
          payDay: payDay,
          isFixed: _utilityBillFixedType,
          amount: amountInt,
          note: noteTrim.isEmpty ? null : noteTrim,
        );
      }
      await widget.onApiCreated?.call();
      if (!mounted) return;
      setState(() => _submitting = false);
      if (skipped.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미 등록된 종류는 제외하고 추가했어요.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  void _submitLocal() {
    if (_selectedLocal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('항목을 하나 이상 선택해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_selectedLocal.contains('기타')) {
      final other = _otherCtrl.text.trim();
      if (other.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기타 항목 이름을 입력해 주세요.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    final amountDigits =
        _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
    int? parsedAmount;
    if (amountDigits.isNotEmpty) {
      parsedAmount = int.tryParse(amountDigits);
      if (parsedAmount == null || parsedAmount < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('금액은 1원 이상의 정수로 입력해 주세요.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    final amountStr = (parsedAmount != null && parsedAmount >= 1)
        ? _formatWonForTable(parsedAmount)
        : '미입력';
    final remarkTrim = _remarkCtrl.text.trim();
    final remarkForTable = remarkTrim.isEmpty ? '—' : remarkTrim;

    final added = <SharedExpenseTableItem>[];
    final skipped = <String>[];

    for (final label in _selectedLocal) {
      final name = label == '기타' ? _otherCtrl.text.trim() : label;
      if (widget.existingItemNames.contains(name) ||
          added.any((e) => e.name == name)) {
        skipped.add(name);
        continue;
      }
      added.add(
        SharedExpenseTableItem(
          name: name,
          date: utilityBillRelativeDueLabel(DateTime.now(), _paymentDay),
          amount: amountStr,
          quantity: remarkForTable,
          utilityPayDay: _paymentDay,
          utilityIsFixed: _utilityBillFixedType,
        ),
      );
    }

    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped.isEmpty
                ? '추가할 항목이 없어요.'
                : '선택한 항목은 이미 표에 있어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    widget.onLocalConfirm(added);
    if (!mounted) return;
    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped.length == 1
                ? '${skipped.first}은(는) 이미 있어 제외했어요.'
                : '이미 있는 항목은 제외하고 추가했어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    final dialogW = (screenW - 40).clamp(300.0, 350.0);
    final maxDialogH = (screenH * 0.62).clamp(320.0, 520.0);
    final api = widget.useBillsApi;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        constraints: BoxConstraints.tightFor(
          width: dialogW,
          height: maxDialogH,
        ),
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
                        '공과금 추가하기',
                        textAlign: TextAlign.center,
                        style: _titleStyle,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (api && _categoriesLoading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: api
                                    ? _apiCategories.map((c) {
                                        final on =
                                            _selectedCodes.contains(c.category);
                                        return _CategoryChip(
                                          label: c.categoryName.isNotEmpty
                                              ? c.categoryName
                                              : c.category,
                                          selected: on,
                                          onTap: () => _toggleCode(c.category),
                                        );
                                      }).toList()
                                    : _localCategoryLabels.map((label) {
                                        final on =
                                            _selectedLocal.contains(label);
                                        return _CategoryChip(
                                          label: label,
                                          selected: on,
                                          onTap: () => _toggleLocal(label),
                                        );
                                      }).toList(),
                              ),
                              if (!api && _selectedLocal.contains('기타')) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.45),
                                        ),
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                      child: TextField(
                                        controller: _otherCtrl,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontFamily: 'Pretendard Variable',
                                        ),
                                        decoration: InputDecoration(
                                          hintText: '기타 항목 이름',
                                          hintStyle: TextStyle(
                                            color: Colors.white.withOpacity(0.45),
                                            fontSize: 13,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                '매달 결제일',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: _buildGlassUtilityPayDayDropdown(),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '금액 유형',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                              const SizedBox(height: 6),
                              _buildGlassUtilityAmountTypeToggle(),
                              const SizedBox(height: 14),
                              Text(
                                _utilityBillFixedType
                                    ? '납부액 (선택)'
                                    : '납부액 (변동 시 선택 입력)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.45),
                                      ),
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    child: TextField(
                                      controller: _amountCtrl,
                                      enabled: !_submitting,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontFamily: 'Pretendard Variable',
                                      ),
                                      decoration: InputDecoration(
                                        hintText: _utilityBillFixedType
                                            ? '정수만 입력 (생략 가능)'
                                            : '이번 달만 반영할 때 입력',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.45),
                                          fontSize: 13,
                                        ),
                                        suffixText: '원',
                                        suffixStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.55),
                                          fontSize: 13,
                                          fontFamily: 'Pretendard Variable',
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '비고 (선택)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: Border.all(
                                        color:
                                            Colors.white.withOpacity(0.45),
                                      ),
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    child: TextField(
                                      controller: _remarkCtrl,
                                      enabled: !_submitting,
                                      maxLines: 2,
                                      minLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontFamily: 'Pretendard Variable',
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            '선택 · 예: 자동이체, 고정, 후불',
                                        hintStyle: TextStyle(
                                          color:
                                              Colors.white.withOpacity(0.45),
                                          fontSize: 13,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsStyleButton(
                        onTap: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              )
                            : const Text(
                                '추가하기',
                                style: TextStyle(
                                  color: PartitionUiTokens.actionText,
                                  fontSize: PartitionUiTokens.actionFontSize,
                                  fontWeight: PartitionUiTokens.actionWeight,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassPanelBlur({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassUtilityPayDayDropdown() {
    final day = _paymentDay.clamp(1, 31);
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontFamily: 'Pretendard Variable',
    );
    return _glassPanelBlur(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _submitting
              ? null
              : () async {
                  final picked = await showGlassUtilityPayDayPicker(
                    context,
                    currentDay: day,
                  );
                  if (picked != null && mounted) {
                    setState(() => _paymentDay = picked);
                  }
                },
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '매월 $day일',
                  style: labelStyle,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withOpacity(_submitting ? 0.35 : 0.85),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassUtilityAmountTypeToggle() {
    final disabled = _submitting;
    return Row(
      children: [
        Expanded(
          child: _glassTogglePill(
            label: '고정',
            selected: _utilityBillFixedType,
            onTap:
                disabled ? null : () => setState(() => _utilityBillFixedType = true),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _glassTogglePill(
            label: '변동',
            selected: !_utilityBillFixedType,
            onTap: disabled
                ? null
                : () => setState(() => _utilityBillFixedType = false),
          ),
        ),
      ],
    );
  }

  Widget _glassTogglePill({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.white.withOpacity(0.78)
                  : Colors.white.withOpacity(0.22),
              width: selected ? 1.1 : 0.5,
            ),
            color: selected
                ? Colors.white.withOpacity(0.24)
                : Colors.white.withOpacity(0.04),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(selected ? 1 : 0.55),
              fontWeight: FontWeight.w700,
              fontFamily: 'Pretendard Variable',
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsStyleButton({
    required Widget child,
    required VoidCallback? onTap,
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
                  color: PartitionUiTokens.actionButtonBorder,
                ),
                color: PartitionUiTokens.actionButtonFill,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Colors.white.withOpacity(0.85)
                  : Colors.white.withOpacity(0.35),
              width: selected ? 1.0 : 0.5,
            ),
            color: selected
                ? Colors.white.withOpacity(0.22)
                : Colors.white.withOpacity(0.10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(selected ? 1.0 : 0.88),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ),
      ),
    );
  }
}
