import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/shared_expense_table_item.dart';
import 'package:partition_app/features/partition/models/utility_bill_model.dart';
import 'package:partition_app/features/partition/models/supply_category_model.dart';
import 'package:partition_app/features/partition/models/supply_purchase_model.dart';
import 'package:partition_app/features/partition/services/supply_service.dart';
import 'package:partition_app/features/partition/services/utility_bill_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/partition/utils/supply_purchase_input.dart';
import 'package:partition_app/shared/widgets/glassmorphic_date_picker.dart';
import 'package:partition_app/shared/widgets/glassmorphism_widget.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 공용 소비·공과금 내역 관리 모달 (홈 집안일 자동 배정 모달과 동일 글래스 톤)
class SharedExpenseManualModal extends StatefulWidget {
  final bool isUtility;
  /// 서버 연동 물품 목록에서 삭제 시 `DELETE /supplies/purchases/{id}` 호출
  final bool deletePurchasesViaApi;
  /// 로그인 상태 공과금 탭: `POST` 신규 · `PATCH` 수정 · `DELETE` 삭제 연동
  final bool submitUtilityViaApi;
  final List<SharedExpenseTableItem> initialItems;
  final void Function(List<SharedExpenseTableItem> items) onApply;
  /// 물품 탭: 다이얼로그를 열자마자 해당 인덱스 행의 수정 폼을 연다 (분류 API 로드 후).
  final int? initialOpenEditIndex;
  /// 물품·공과금 탭: `+`로 진입 시 추가 폼만 열고, 신규 저장 후 목록 없이 닫는다.
  final bool addOnlyEntry;

  const SharedExpenseManualModal({
    super.key,
    required this.isUtility,
    this.deletePurchasesViaApi = false,
    this.submitUtilityViaApi = false,
    required this.initialItems,
    required this.onApply,
    this.initialOpenEditIndex,
    this.addOnlyEntry = false,
  });

  @override
  State<SharedExpenseManualModal> createState() =>
      _SharedExpenseManualModalState();
}

class _SharedExpenseManualModalState extends State<SharedExpenseManualModal> {
  /// 직접 추가(`+`)만 — `_isForm` 타이밍과 무관하게 목록 레이아웃을 그리지 않음
  bool get _showsAddOnlyForm =>
      widget.addOnlyEntry && widget.initialOpenEditIndex == null;

  final SupplyService _supplyService = SupplyService();
  final UtilityBillService _utilityBillService = UtilityBillService();

  /// 물품: GET /supplies/categories, 실패 시 [kDefaultSupplyCategoryGroups]
  List<SupplyCategoryGroup> _categories = const [];
  bool _categoriesLoading = false;

  late List<SharedExpenseTableItem> _items;
  bool _isForm = false;
  int? _editIndex; // null = 새 추가
  bool _submittingPurchase = false;
  bool _submittingUtilityBill = false;
  bool _deletingPurchase = false;
  bool _deletingUtilityBill = false;

  /// 물품 구체 표기 (예: 콘프라이트 500g)
  late final TextEditingController _detailCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _qtyCtrl;

  /// API `category` 코드 (예: GROCERY)
  String? _selectedMajorCode;
  /// API `subCategory` 코드
  String? _selectedMinorCode;

  /// 공과금: POST 명세 `utilityType` (단일 선택 칩)
  String? _selectedUtilityEnum;
  int _utilityPayDay = 1;

  @override
  void initState() {
    super.initState();
    _items = List<SharedExpenseTableItem>.from(widget.initialItems);
    _detailCtrl = TextEditingController();
    _dateCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _qtyCtrl = TextEditingController();

    /// 물품 `+` 직접 추가: 목록 없이 폼부터 (분류 로딩 표시용)
    final addOnlyGoods = !widget.isUtility &&
        widget.addOnlyEntry &&
        widget.initialOpenEditIndex == null;
    if (addOnlyGoods) {
      _isForm = true;
      _editIndex = null;
      _selectedUtilityEnum = null;
      _utilityPayDay = 1;
      _selectedMajorCode = null;
      _selectedMinorCode = null;
      _categoriesLoading = true;
    }

    /// 공과금 `+` 직접 추가
    final addOnlyUtility = widget.isUtility &&
        widget.addOnlyEntry &&
        widget.initialOpenEditIndex == null;
    if (addOnlyUtility) {
      _isForm = true;
      _editIndex = null;
      _selectedUtilityEnum = null;
      _utilityPayDay = 1;
      _selectedMajorCode = null;
      _selectedMinorCode = null;
    }

    /// 공과금 항목 수정: 초기부터 폼(+데이터). 목록 깜빡임 없음
    final ixEditUtility = widget.initialOpenEditIndex;
    if (widget.isUtility &&
        ixEditUtility != null &&
        ixEditUtility >= 0 &&
        ixEditUtility < _items.length &&
        !widget.addOnlyEntry) {
      _isForm = true;
      _editIndex = ixEditUtility;
      final e = _items[ixEditUtility];
      _amountCtrl.text = e.amount;
      _qtyCtrl.text = e.quantity ?? '';
      _dateCtrl.clear();
      _detailCtrl.clear();
      _selectedMajorCode = null;
      _selectedMinorCode = null;
      _selectedUtilityEnum = _inferUtilityEnumFromItem(e);
      _utilityPayDay = _inferUtilityPayDayFromItem(e) ?? 1;
    }

    if (!widget.isUtility) {
      _loadSupplyCategories();
    }
  }

  void _scheduleInitialEditFormIfNeeded() {
    final ix = widget.initialOpenEditIndex;
    if (ix == null) return;
    if (ix < 0 || ix >= _items.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openEditForm(ix);
    });
  }

  Future<void> _loadSupplyCategories() async {
    setState(() => _categoriesLoading = true);
    try {
      final list = await _supplyService.fetchSupplyCategories();
      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() {
          _categories = list;
          _categoriesLoading = false;
        });
        _scheduleInitialEditFormIfNeeded();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _categories = kDefaultSupplyCategoryGroups;
      _categoriesLoading = false;
    });
    _scheduleInitialEditFormIfNeeded();
  }

  SupplyCategoryGroup? _groupForCategoryCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final c in _categories) {
      if (c.category == code) return c;
    }
    return null;
  }

  SupplyCategoryGroup? _groupForCategoryDisplayName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final c in _categories) {
      if (c.categoryName == name) return c;
    }
    return null;
  }

  SupplySubCategoryItem? _subForCodes(String? majorCode, String? minorCode) {
    final g = _groupForCategoryCode(majorCode);
    if (g == null || minorCode == null || minorCode.isEmpty) return null;
    for (final s in g.subCategories) {
      if (s.subCategory == minorCode) return s;
    }
    return null;
  }

  SupplySubCategoryItem? _subForDisplayName(
    SupplyCategoryGroup? g,
    String? minorDisplay,
  ) {
    if (g == null || minorDisplay == null || minorDisplay.isEmpty) return null;
    for (final s in g.subCategories) {
      if (s.subCategoryName == minorDisplay) return s;
    }
    return null;
  }

  String? _majorLabelForField() {
    final c = _selectedMajorCode;
    if (c == null || c.isEmpty) return null;
    return _groupForCategoryCode(c)?.categoryName;
  }

  String? _minorLabelForField() {
    final sub = _subForCodes(_selectedMajorCode, _selectedMinorCode);
    return sub?.subCategoryName;
  }

  List<String> _majorLabelsForPicker() {
    final labels = _categories.map((c) => c.categoryName).toList();
    if (_isForm && _editIndex != null) {
      final m = _items[_editIndex!].majorCategory?.trim();
      if (m != null && m.isNotEmpty && !labels.contains(m)) {
        return [m, ...labels];
      }
    }
    return labels;
  }

  List<String> _majorCodesForPicker() {
    final codes = _categories.map((c) => c.category).toList();
    if (_isForm && _editIndex != null) {
      final m = _items[_editIndex!].majorCategory?.trim();
      final apiLabels = _categories.map((c) => c.categoryName).toList();
      if (m != null && m.isNotEmpty && !apiLabels.contains(m)) {
        return ['__legacy__', ...codes];
      }
    }
    return codes;
  }

  void _onMajorCodePicked(String code) {
    setState(() {
      if (code == '__legacy__') {
        _selectedMajorCode = null;
        _selectedMinorCode = null;
      } else {
        _selectedMajorCode = code;
        _selectedMinorCode = null;
        final g = _groupForCategoryCode(code);
        final subs = g?.subCategories ?? [];
        if (subs.length == 1) {
          _selectedMinorCode = subs.first.subCategory;
        }
      }
    });
  }

  List<String> _minorLabelsForPicker() {
    final g = _groupForCategoryCode(_selectedMajorCode);
    if (g != null) {
      return g.subCategories.map((s) => s.subCategoryName).toList();
    }
    if (_isForm && _editIndex != null) {
      final e = _items[_editIndex!];
      if (e.minorCategory != null && e.minorCategory!.trim().isNotEmpty) {
        return [e.minorCategory!.trim()];
      }
    }
    return const [];
  }

  List<String> _minorCodesForPicker() {
    final g = _groupForCategoryCode(_selectedMajorCode);
    if (g != null) {
      return g.subCategories.map((s) => s.subCategory).toList();
    }
    if (_isForm && _editIndex != null) {
      final e = _items[_editIndex!];
      if (e.subCategoryCode != null && e.subCategoryCode!.isNotEmpty) {
        return [e.subCategoryCode!];
      }
    }
    return const [];
  }

  String? _utilityLabelForCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final c in UtilityBillCategory.fallbackCategories) {
      if (c.category == code) return c.categoryName;
    }
    return null;
  }

  /// 더미·구형 행 이름 → Enum (매칭 실패 시 null)
  String? _legacyUtilityDisplayNameToEnum(String name) {
    const legacy = <String, String>{
      '가스세': 'GAS',
      '대출 이자': 'LOAN_INTEREST',
      '관리비': 'ETC',
      'TV 수신료': 'ETC',
      '건물 보험': 'ETC',
      '주차비': 'ETC',
      '공용 전기': 'ETC',
    };
    return legacy[name.trim()];
  }

  String? _inferUtilityEnumFromItem(SharedExpenseTableItem e) {
    final code = e.utilityTypeEnum?.trim();
    if (code != null && code.isNotEmpty) {
      if (_utilityLabelForCode(code) != null) return code;
    }
    final name = e.name.trim();
    if (name.isEmpty) return null;
    for (final c in UtilityBillCategory.fallbackCategories) {
      if (c.categoryName == name) return c.category;
    }
    return _legacyUtilityDisplayNameToEnum(name);
  }

  int? _inferUtilityPayDayFromItem(SharedExpenseTableItem e) {
    final pd = e.utilityPayDay;
    if (pd != null && pd >= 1 && pd <= 31) return pd;
    final iso = e.utilityDueDateIso?.trim();
    if (iso != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(iso)) {
      final dt = DateTime.tryParse(iso);
      if (dt != null) return dt.day.clamp(1, 31);
    }
    final m = RegExp(r'매월\s*(\d{1,2})\s*일').firstMatch(e.date);
    if (m != null) {
      final x = int.tryParse(m.group(1)!);
      if (x != null && x >= 1 && x <= 31) return x;
    }
    return null;
  }

  void _toggleUtilityEnum(String code) {
    setState(() {
      if (_selectedUtilityEnum == code) {
        _selectedUtilityEnum = null;
      } else {
        _selectedUtilityEnum = code;
      }
    });
  }

  @override
  void dispose() {
    _detailCtrl.dispose();
    _dateCtrl.dispose();
    _amountCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _openAddForm() {
    setState(() {
      _isForm = true;
      _editIndex = null;
      _selectedUtilityEnum = null;
      _detailCtrl.clear();
      _dateCtrl.clear();
      _amountCtrl.clear();
      _qtyCtrl.clear();
      _utilityPayDay = 1;
      _selectedMajorCode = null;
      _selectedMinorCode = null;
    });
  }

  void _openEditForm(int index) {
    final e = _items[index];
    setState(() {
      _isForm = true;
      _editIndex = index;
      _amountCtrl.text = e.amount;
      _qtyCtrl.text = e.quantity ?? '';
      if (widget.isUtility) {
        _dateCtrl.clear();
        _detailCtrl.clear();
        _selectedMajorCode = null;
        _selectedMinorCode = null;
        _selectedUtilityEnum = _inferUtilityEnumFromItem(e);
        _utilityPayDay = _inferUtilityPayDayFromItem(e) ?? 1;
      } else {
        _dateCtrl.text = e.date;
        if (e.categoryCode != null &&
            e.categoryCode!.isNotEmpty &&
            e.subCategoryCode != null &&
            e.subCategoryCode!.isNotEmpty) {
          _selectedMajorCode = e.categoryCode;
          _selectedMinorCode = e.subCategoryCode;
        } else {
          final g = _groupForCategoryDisplayName(e.majorCategory);
          _selectedMajorCode = g?.category;
          final sub = _subForDisplayName(g, e.minorCategory);
          _selectedMinorCode = sub?.subCategory;
        }
        final hasStructured = e.majorCategory != null ||
            e.minorCategory != null ||
            (e.detail != null && e.detail!.trim().isNotEmpty);
        if (hasStructured) {
          _detailCtrl.text = (e.detail ?? '').trim();
        } else {
          _detailCtrl.text = e.name;
        }
      }
    });
  }

  /// 공용 소비 기간 선택과 동일 `GlassmorphicDatePicker` (과거 구매일 ~ 오늘)
  String _formatPickedDateDisplay(DateTime d) {
    final yy = d.year % 100;
    return '${yy.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.'
        '${d.day.toString().padLeft(2, '0')}.';
  }

  Future<void> _pickPurchaseDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(today.year - 20, 1, 1);
    final lastDate = widget.isUtility
        ? today.add(const Duration(days: 365))
        : today;

    var initial = today;
    final parsedIso = tryParsePurchaseDateToIso(_dateCtrl.text.trim());
    if (parsedIso != null) {
      final parts = parsedIso.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (y != null && m != null && day != null) {
          initial = DateTime(y, m, day);
          if (initial.isBefore(firstDate)) initial = firstDate;
          if (initial.isAfter(lastDate)) initial = lastDate;
        }
      }
    }

    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => GlassmorphicDatePicker(
        initialDate: initial,
        firstDate: firstDate,
        lastDate: lastDate,
        isStartDate: true,
      ),
    );

    if (picked != null && mounted) {
      final d = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _dateCtrl.text = _formatPickedDateDisplay(d);
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  SharedExpenseTableItem _rowFromPurchaseResult(SupplyPurchaseResult r) {
    final majorLabel =
        _groupForCategoryCode(r.category)?.categoryName ?? r.category;
    final minorLabel = _subForCodes(r.category, r.subCategory)
            ?.subCategoryName ??
        r.subCategory;
    final dateDisp = displayDateFromIso(r.purchaseDate);
    final amountDisp = formatAmountWithWon(r.amount);
    final qtyDisp = '${r.quantity}개';
    return SharedExpenseTableItem(
      name: '$majorLabel · $minorLabel · ${r.itemName}',
      date: dateDisp,
      amount: amountDisp,
      quantity: qtyDisp,
      majorCategory: majorLabel,
      minorCategory: minorLabel,
      detail: r.itemName,
      purchaseId: r.purchaseId,
      categoryCode: r.category,
      subCategoryCode: r.subCategory,
    );
  }

  Future<void> _saveForm() async {
    final date = _dateCtrl.text.trim();
    final amount = _amountCtrl.text.trim();
    final qty = _qtyCtrl.text.trim();

    if (widget.isUtility) {
      final code = _selectedUtilityEnum?.trim();
      if (code == null ||
          code.isEmpty ||
          _utilityLabelForCode(code) == null ||
          amount.isEmpty) {
        _snack('공과금 종류·매달 결제일·납부액은 필수예요.');
        return;
      }
      final payDay = _utilityPayDay.clamp(1, 31);
      final amountInt = tryParseWonAmount(amount);
      if (amountInt == null) {
        _snack('금액을 숫자로 입력해 주세요.');
        return;
      }
      if (amountInt < 1) {
        _snack('금액은 1원 이상이어야 해요.');
        return;
      }
      final noteTrim = qty.trim();
      final label = _utilityLabelForCode(code)!;
      final amountDisp = formatAmountWithWon(amountInt);
      final dateLabel = utilityBillRelativeDueLabel(DateTime.now(), payDay);

      if (widget.submitUtilityViaApi && _editIndex != null) {
        final prev = _items[_editIndex!];
        final bid = prev.billId;
        if (bid != null && bid > 0) {
          if (_submittingPurchase || _submittingUtilityBill) return;
          setState(() => _submittingUtilityBill = true);
          try {
            final updated = await _utilityBillService.updateBill(
              billId: bid,
              utilityType: code,
              payDay: payDay,
              amount: amountInt,
              note: noteTrim.isEmpty ? null : noteTrim,
            );
            if (!mounted) return;
            final nameLabel = updated.utilityTypeName.isNotEmpty
                ? updated.utilityTypeName
                : updated.utilityType;
            final qFromServer = updated.note?.trim().isNotEmpty == true
                ? updated.note!.trim()
                : null;
            final row = SharedExpenseTableItem(
              name: nameLabel,
              date: utilityBillRelativeDueLabel(DateTime.now(), updated.payDay),
              amount: formatAmountWithWon(updated.amount),
              quantity: qFromServer ?? (noteTrim.isEmpty ? null : noteTrim),
              manuallySettled: prev.manuallySettled,
              utilityTypeEnum: updated.utilityType.isNotEmpty
                  ? updated.utilityType
                  : code,
              utilityPayDay: updated.payDay,
              billId: updated.billId,
              utilityDueDateIso: prev.utilityDueDateIso,
            );
            _commitRow(row);
          } on ApiException catch (e) {
            if (mounted) _snack(e.message);
          } catch (_) {
            if (mounted) {
              _snack('공과금 수정에 실패했어요. 잠시 후 다시 시도해 주세요.');
            }
          } finally {
            if (mounted) setState(() => _submittingUtilityBill = false);
          }
          return;
        }
      }

      if (widget.submitUtilityViaApi && _editIndex == null) {
        if (_submittingPurchase || _submittingUtilityBill) return;
        setState(() => _submittingUtilityBill = true);
        try {
          final created = await _utilityBillService.createBill(
            utilityType: code,
            payDay: payDay,
            amount: amountInt,
            note: noteTrim.isEmpty ? null : noteTrim,
          );
          if (!mounted) return;
          final nameLabel = created.utilityTypeName.isNotEmpty
              ? created.utilityTypeName
              : created.utilityType;
          final qFromServer =
              created.note?.trim().isNotEmpty == true ? created.note!.trim() : null;
          final row = SharedExpenseTableItem(
            name: nameLabel,
            date: utilityBillRelativeDueLabel(DateTime.now(), created.payDay),
            amount: formatAmountWithWon(created.amount),
            quantity: qFromServer ?? (noteTrim.isEmpty ? null : noteTrim),
            utilityTypeEnum: created.utilityType.isNotEmpty
                ? created.utilityType
                : code,
            utilityPayDay: created.payDay,
            billId: created.billId,
          );
          _commitRow(row);
        } on ApiException catch (e) {
          if (mounted) _snack(e.message);
        } catch (_) {
          if (mounted) {
            _snack('공과금 등록에 실패했어요. 잠시 후 다시 시도해 주세요.');
          }
        } finally {
          if (mounted) setState(() => _submittingUtilityBill = false);
        }
        return;
      }

      SharedExpenseTableItem row;
      if (_editIndex != null) {
        final prev = _items[_editIndex!];
        row = SharedExpenseTableItem(
          name: label,
          date: dateLabel,
          amount: amountDisp,
          quantity: noteTrim.isEmpty ? null : noteTrim,
          manuallySettled: prev.manuallySettled,
          billId: prev.billId,
          utilityTypeEnum: code,
          utilityPayDay: payDay,
          utilityDueDateIso: prev.utilityDueDateIso,
        );
      } else {
        row = SharedExpenseTableItem(
          name: label,
          date: dateLabel,
          amount: amountDisp,
          quantity: noteTrim.isEmpty ? null : noteTrim,
          utilityTypeEnum: code,
          utilityPayDay: payDay,
        );
      }
      _commitRow(row);
      return;
    }

    final majorCode = _selectedMajorCode?.trim();
    final minorCode = _selectedMinorCode?.trim();
    final detail = _detailCtrl.text.trim();
    if (majorCode == null ||
        majorCode.isEmpty ||
        minorCode == null ||
        minorCode.isEmpty ||
        detail.isEmpty ||
        date.isEmpty ||
        amount.isEmpty ||
        qty.isEmpty) {
      _snack('대분류·소분류·물품명·구매일(달력)·금액·수량은 필수예요.');
      return;
    }

    final isoDate = tryParsePurchaseDateToIso(date);
    if (isoDate == null) {
      _snack(widget.isUtility
          ? '납부일을 달력에서 선택해 주세요.'
          : '구매일을 달력에서 선택해 주세요.');
      return;
    }

    final amountInt = tryParseWonAmount(amount);
    if (amountInt == null) {
      _snack('금액을 숫자로 입력해 주세요.');
      return;
    }
    if (amountInt < 0) {
      _snack('금액은 0원 이상이어야 해요.');
      return;
    }

    final qtyInt = tryParseItemQuantity(qty);
    if (qtyInt == null || qtyInt < 1) {
      _snack('수량은 1개 이상이어야 해요.');
      return;
    }

    final g = _groupForCategoryCode(majorCode);
    final sub = _subForCodes(majorCode, minorCode);
    final majorLabel = g?.categoryName ?? majorCode;
    final minorLabel = sub?.subCategoryName ?? minorCode;

    if (_editIndex != null) {
      final prev = _items[_editIndex!];
      final pid = prev.purchaseId;
      if (pid != null && pid > 0) {
        if (_submittingPurchase) return;
        setState(() => _submittingPurchase = true);
        try {
          final result = await _supplyService.updatePurchase(
            purchaseId: pid,
            itemName: detail,
            purchaseDate: isoDate,
            amount: amountInt,
            quantity: qtyInt,
            category: majorCode,
            subCategory: minorCode,
          );
          if (!mounted) return;
          _commitRow(_rowFromPurchaseResult(result));
        } on ApiException catch (e) {
          if (mounted) _snack(e.message);
        } catch (_) {
          if (mounted) {
            _snack('수정에 실패했어요. 잠시 후 다시 시도해 주세요.');
          }
        } finally {
          if (mounted) setState(() => _submittingPurchase = false);
        }
        return;
      }
      final composedName = [majorLabel, minorLabel, detail].join(' · ');
      final row = SharedExpenseTableItem(
        name: composedName,
        date: date,
        amount: amount,
        quantity: qty,
        majorCategory: majorLabel,
        minorCategory: minorLabel,
        detail: detail,
        manuallySettled: prev.manuallySettled,
        purchaseId: prev.purchaseId,
        categoryCode: majorCode,
        subCategoryCode: minorCode,
      );
      _commitRow(row);
      return;
    }

    if (_submittingPurchase) return;
    setState(() => _submittingPurchase = true);
    try {
      final result = await _supplyService.createPurchase(
        itemName: detail,
        purchaseDate: isoDate,
        amount: amountInt,
        quantity: qtyInt,
        category: majorCode,
        subCategory: minorCode,
      );
      if (!mounted) return;
      _commitRow(_rowFromPurchaseResult(result));
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('등록에 실패했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _submittingPurchase = false);
    }
  }

  void _commitRow(SharedExpenseTableItem row) {
    final wasNewAdd = _editIndex == null;
    if (widget.addOnlyEntry && wasNewAdd) {
      setState(() {
        _items.add(row);
        _editIndex = null;
      });
      widget.onApply(List<SharedExpenseTableItem>.from(_items));
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      if (wasNewAdd) {
        _items.add(row);
      } else {
        _items[_editIndex!] = row;
      }
      _isForm = false;
      _editIndex = null;
    });
  }

  Future<void> _deleteAt(int index) async {
    if (_deletingPurchase ||
        _deletingUtilityBill ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    final row = _items[index];
    final pid = row.purchaseId;
    if (widget.deletePurchasesViaApi &&
        !widget.isUtility &&
        pid != null &&
        pid > 0) {
      setState(() => _deletingPurchase = true);
      try {
        await _supplyService.deletePurchase(pid);
      } on ApiException catch (e) {
        if (mounted) _snack(e.message);
        return;
      } catch (_) {
        if (mounted) {
          _snack('삭제에 실패했어요. 잠시 후 다시 시도해 주세요.');
        }
        return;
      } finally {
        if (mounted) setState(() => _deletingPurchase = false);
      }
    } else if (widget.isUtility &&
        widget.submitUtilityViaApi &&
        row.billId != null &&
        row.billId! > 0) {
      setState(() => _deletingUtilityBill = true);
      try {
        await _utilityBillService.deleteBill(row.billId!);
      } on ApiException catch (e) {
        if (mounted) _snack(e.message);
        return;
      } catch (_) {
        if (mounted) {
          _snack('삭제에 실패했어요. 잠시 후 다시 시도해 주세요.');
        }
        return;
      } finally {
        if (mounted) setState(() => _deletingUtilityBill = false);
      }
    }
    if (!mounted) return;
    setState(() {
      _items.removeAt(index);
    });
  }

  void _applyAndClose() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('내용을 입력해 주세요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onApply(List<SharedExpenseTableItem>.from(_items));
    Navigator.of(context).pop(true);
  }

  /// 모달 제목 (18 / 블랙에 가까운 굵기로 통일)
  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    fontFamily: 'Pretendard Variable',
    height: 1.15,
  );

  static const _subtitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: 'Pretendard Variable',
    height: 1.08,
  );

  /// 텍스트 필드·카테고리 행 공통 — 카테고리만 넓던 것·텍스트만 낮던 것의 중간 높이로 통일
  static const EdgeInsets _kGlassFieldPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 6);

  static const double _kFormFieldInnerHeight = 38.0;

  /// 내역 목록 항목 제목 — 모달 제목(18)보다 작게 두어 위계 유지
  static const TextStyle _listItemTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontFamily: 'Pretendard Variable',
    height: 1.1,
  );

  static ButtonStyle _listOutlineButtonStyle({required Color foreground}) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      side: BorderSide(color: Colors.white.withOpacity(0.9), width: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(48, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    // 고정 높이(_kFormFieldInnerHeight) 안에서 한 줄 입력이 세로 가운데 오도록 대칭 패딩
    final vPad = ((_kFormFieldInnerHeight - 13 * 1.35) / 2).clamp(8.0, 14.0);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.45),
        fontSize: 13,
        fontFamily: 'Pretendard Variable',
        height: 1.35,
      ),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: vPad),
      border: InputBorder.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    final dialogW = (screenW - 32).clamp(300.0, 350.0);
    // 집안일 모달(고정 323) · 날짜 선택 등과 비슷한 비율로 제한, 내용은 스크롤
    final maxDialogH = (screenH * 0.52).clamp(300.0, 480.0);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: GestureDetector(
          onTap: () {},
          child: _showsAddOnlyForm
              ? _buildForm()
              : (_isForm ? _buildForm() : _buildList()),
        ),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isUtility ? '공과금 내역 관리' : '공용 소비 내역 관리',
          textAlign: TextAlign.center,
          style: _titleStyle,
        ),
        const SizedBox(height: 8),
        Text(
          widget.isUtility
              ? '항목을 직접 입력·수정·삭제하며 공과금 내역을 관리해요'
              : (widget.initialItems.isEmpty
                  ? '「내역 추가」로 구매를 등록해요.\n(선택한 기간에 표에 맞는 내역이 있으면 여기에도 같이 떠요.)'
                  : '항목「수정」에서 물품·날짜·금액·분류를 바꾸면 서버에 반영돼요.\n새로「내역 추가」도 할 수 있어요.'),
          textAlign: TextAlign.center,
          style: _subtitleStyle,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text(
                    '등록된 내역이 없어요.\n아래에서 내역을 추가해 관리해 보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.white.withOpacity(0.38),
                  ),
                  itemBuilder: (context, i) {
                    final e = _items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _listItemTitleStyle,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${e.date} · ${e.amount}'
                                  '${e.quantity != null && e.quantity!.isNotEmpty ? ' · ${e.quantity}' : ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 11,
                                    height: 1.2,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed:
                                (_deletingPurchase || _deletingUtilityBill)
                                    ? null
                                    : () => _openEditForm(i),
                            style: _listOutlineButtonStyle(
                              foreground: Colors.white,
                            ),
                            child: const Text(
                              '수정',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed:
                                (_deletingPurchase || _deletingUtilityBill)
                                    ? null
                                    : () => _deleteAt(i),
                            style: _listOutlineButtonStyle(
                              foreground: Colors.white,
                            ),
                            child: const Text(
                              '삭제',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 14),
        _glassPillButton(
          label: '내역 추가',
          onTap: _openAddForm,
        ),
        const SizedBox(height: 10),
        _settingsModalActionButton(
          label: '저장',
          onTap: _applyAndClose,
        ),
      ],
    );
  }

  Widget _buildForm() {
    final qtyLabel = widget.isUtility ? '비고' : '수량';
    final formTitleText = _editIndex == null
        ? (widget.isUtility ? '공과금 내역 추가' : '공용 소비 물품 추가')
        : '내역 수정';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.addOnlyEntry)
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  formTitleText,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: _titleStyle.copyWith(height: 1.15),
                ),
              ),
              PartitionModalCloseButton(
                onPressed: () => Navigator.of(context).pop(false),
                color: Colors.white.withOpacity(0.88),
              ),
            ],
          )
        else
          Text(
            formTitleText,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: _titleStyle.copyWith(height: 1.15),
          ),
        SizedBox(height: widget.addOnlyEntry ? 3 : 4),
        Text(
          widget.isUtility
              ? (widget.submitUtilityViaApi && _editIndex == null
                  ? '새로운 공과금을 등록할 수 있습니다.'
                  : widget.submitUtilityViaApi
                      ? '공용 소비 표에 반영하기 위해 새로운 내역을 입력하세요.'
                      : '저장하면 목록에 반영되어 함께 관리할 수 있어요.')
              : (_editIndex == null
                  ? '등록하고 싶은 물품의 정보를 입력해주세요.'
                  : '저장하면 목록에 반영되어 함께 관리돼요'),
          textAlign: TextAlign.center,
          style: _subtitleStyle,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: (!widget.isUtility && _categoriesLoading)
              ? const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                )
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (widget.isUtility) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '공과금 종류',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        children: UtilityBillCategory.fallbackCategories
                            .map(
                              (c) => _ManualUtilityEnumChip(
                                label: c.categoryName.isNotEmpty
                                    ? c.categoryName
                                    : c.category,
                                selected:
                                    _selectedUtilityEnum == c.category,
                                onTap: () => _toggleUtilityEnum(c.category),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                    ] else ...[
                      _buildCategoryPickerField(
                        hint: '대분류 선택',
                        value: _majorLabelForField(),
                        enabled: !_categoriesLoading &&
                            _majorLabelsForPicker().isNotEmpty,
                        onTap: () async {
                          final labels = _majorLabelsForPicker();
                          final codes = _majorCodesForPicker();
                          if (labels.isEmpty || labels.length != codes.length) {
                            return;
                          }
                          final picked = await _showGlassCodePickerModal(
                            title: '대분류',
                            labels: labels,
                            codes: codes,
                            currentCode: _selectedMajorCode,
                          );
                          if (picked != null && mounted) {
                            _onMajorCodePicked(picked);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildCategoryPickerField(
                        hint: '소분류 선택',
                        value: _minorLabelForField(),
                        enabled: _selectedMajorCode != null &&
                            _minorLabelsForPicker().isNotEmpty,
                        onTap: () async {
                          final labels = _minorLabelsForPicker();
                          final codes = _minorCodesForPicker();
                          if (labels.isEmpty || labels.length != codes.length) {
                            return;
                          }
                          final picked = await _showGlassCodePickerModal(
                            title: '소분류',
                            labels: labels,
                            codes: codes,
                            currentCode: _selectedMinorCode,
                          );
                          if (picked != null && mounted) {
                            setState(() => _selectedMinorCode = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _glassFormField(
                        child: TextField(
                          controller: _detailCtrl,
                          style: _inputStyle,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: _fieldDecoration(
                              '물품명 (예: 콘프라이트 500g)'),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (widget.isUtility) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '매달 결제일',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _glassFormField(child: _buildUtilityPayDayDropdown()),
                      const SizedBox(height: 10),
                    ] else ...[
                      _buildDatePickerField(hint: '구매일 선택'),
                      const SizedBox(height: 10),
                    ],
                    _glassFormField(
                      child: TextField(
                        controller: _amountCtrl,
                        style: _inputStyle,
                        textAlignVertical: TextAlignVertical.center,
                        keyboardType: TextInputType.text,
                        decoration: _fieldDecoration(
                          widget.isUtility
                              ? '납부액 (예: 5980 또는 5,980원)'
                              : '금액 (예: 5980 또는 5,980원)',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _glassFormField(
                      child: TextField(
                        controller: _qtyCtrl,
                        style: _inputStyle,
                        textAlignVertical: TextAlignVertical.center,
                        keyboardType: widget.isUtility
                            ? TextInputType.text
                            : TextInputType.number,
                        decoration: _fieldDecoration(
                          widget.isUtility
                              ? '$qtyLabel (선택, 예: 후불)'
                              : '$qtyLabel (필수, 예: 3)',
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _settingsModalActionButton(
          label: (_submittingPurchase || _submittingUtilityBill)
              ? '등록 중…'
              : '저장',
          onTap: (_categoriesLoading ||
                  _submittingPurchase ||
                  _submittingUtilityBill)
              ? null
              : _saveForm,
        ),
      ],
    );
  }

  /// 대분류·소분류 탭 시 중앙 글래스모피즘 모달 (표시는 [labels], 반환은 [codes])
  Future<String?> _showGlassCodePickerModal({
    required String title,
    required List<String> labels,
    required List<String> codes,
    String? currentCode,
  }) async {
    if (labels.isEmpty || labels.length != codes.length) return null;
    final mq = MediaQuery.of(context);
    final dialogW = (mq.size.width - 48).clamp(280.0, 360.0);
    final dialogH = (mq.size.height * 0.58).clamp(320.0, 520.0);

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.52),
      builder: (ctx) {
        return PartitionGlassDialog(
          constraints: BoxConstraints.tightFor(
            width: dialogW,
            height: dialogH,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Pretendard Variable',
                                height: 1.2,
                              ),
                            ),
                          ),
                          PartitionModalCloseButton(
                            onPressed: () => Navigator.pop(ctx),
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withOpacity(0.22),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 12),
                        physics: const BouncingScrollPhysics(),
                        itemCount: labels.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        itemBuilder: (c, i) {
                          final o = labels[i];
                          final code = codes[i];
                          final sel = code == currentCode;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(ctx, code),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: sel
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          fontFamily: 'Pretendard Variable',
                                          fontSize: 15,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    if (sel)
                                      const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white70,
                                        size: 22,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUtilityPayDayDropdown() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _utilityPayDay.clamp(1, 31),
        isExpanded: true,
        dropdownColor: const Color(0xE6282835),
        iconEnabledColor: Colors.white70,
        style: _inputStyle,
        items: List.generate(
          31,
          (i) => DropdownMenuItem(
            value: i + 1,
            child: Text(
              '매월 ${i + 1}일',
              style: _inputStyle,
            ),
          ),
        ),
        onChanged: (_submittingPurchase || _submittingUtilityBill)
            ? null
            : (v) {
                if (v != null) {
                  setState(() => _utilityPayDay = v);
                }
              },
      ),
    );
  }

  Widget _buildDatePickerField({required String hint}) {
    final v = _dateCtrl.text.trim();
    final has = v.isNotEmpty;
    return _glassFormField(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _pickPurchaseDate,
          borderRadius: BorderRadius.circular(18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    has ? v : hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: has ? _inputStyle : _hintStyle,
                  ),
                ),
                Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white.withOpacity(0.85),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPickerField({
    required String hint,
    required String? value,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return _glassFormField(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    value ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: value != null ? _inputStyle : _hintStyle,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withOpacity(
                    enabled ? 0.85 : 0.35,
                  ),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _inputStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontFamily: 'Pretendard Variable',
    height: 1.35,
  );

  static final _hintStyle = TextStyle(
    color: Colors.white.withOpacity(0.45),
    fontSize: 13,
    fontFamily: 'Pretendard Variable',
    height: 1.35,
  );

  Widget _glassField({required Widget child}) {
    return GlassmorphismWidget(
      borderRadius: BorderRadius.circular(20),
      backgroundOpacity: 0.1,
      borderColor: Colors.white.withOpacity(0.5),
      strokeGradient: const RadialGradient(
        center: Alignment(-0.1212, -0.1178),
        radius: 1.7145,
        colors: [
          Color.fromRGBO(255, 255, 255, 0.10),
          Color.fromRGBO(255, 255, 255, 0.15),
        ],
        stops: [0.0, 1.0],
      ),
      padding: _kGlassFieldPadding,
      child: child,
    );
  }

  /// 폼 입력·카테고리 선택 줄 — 동일 내부 높이로 시각적 통일
  Widget _glassFormField({required Widget child}) {
    return _glassField(
      child: SizedBox(
        height: _kFormFieldInnerHeight,
        child: child,
      ),
    );
  }

  Widget _glassPillButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      height: PartitionUiTokens.actionButtonHeight,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: const RadialGradient(
                  center: Alignment(-0.1212, -0.1178),
                  radius: 1.7145,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.10),
                    Color.fromRGBO(255, 255, 255, 0.15),
                  ],
                  stops: [0.0, 1.0],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(255, 255, 255, 0.25),
                    offset: Offset(4, 4),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(enabled ? 1 : 0.45),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsModalActionButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.48,
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
              child: Text(
                label,
                style: const TextStyle(
                  color: PartitionUiTokens.actionText,
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

/// 공과금 Enum 선택 칩 (`UtilityBillAddModal`과 유사 톤)
class _ManualUtilityEnumChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ManualUtilityEnumChip({
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
