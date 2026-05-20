import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/partition/controllers/alarm_navigation_controller.dart';
import 'package:partition_app/features/partition/models/alarm_model.dart';
import 'package:partition_app/features/partition/models/shared_expense_table_item.dart';
import 'package:partition_app/features/partition/models/supply_purchase_model.dart';
import 'package:partition_app/features/partition/models/utility_bill_model.dart';
import 'package:partition_app/features/partition/widgets/shared_expense_filter_chip.dart';
import 'package:partition_app/features/partition/widgets/shared_expense_manual_modal.dart';
import 'package:partition_app/features/partition/widgets/shared_expense_item_detail_sheet.dart';
import 'package:partition_app/shared/widgets/frosted_panel.dart';
import 'package:partition_app/shared/widgets/glassmorphic_date_picker.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';
import 'package:partition_app/shared/widgets/primary_button.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/partition/services/supply_service.dart';
import 'package:partition_app/features/partition/services/utility_bill_service.dart';
import 'package:partition_app/features/partition/models/supply_category_model.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/shared/utils/partition_dummy_data_policy.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';

class PartitionSharedExpenseScreen extends StatefulWidget {
  const PartitionSharedExpenseScreen({super.key});

  @override
  State<PartitionSharedExpenseScreen> createState() =>
      _PartitionSharedExpenseScreenState();
}

class _PartitionSharedExpenseScreenState
    extends State<PartitionSharedExpenseScreen> {
  static const Color _destructiveMuted = Color(0xFFD88A94);

  // Constants — 본문 영역 높이(상태줄 제외). 기존 125의 약 0.7로 얇게.
  static const double _headerHeight = 87.5;
  static const double _contentPaddingBottom = 16.0;

  /// 하단 글래스 탭바 등이 본문과 겹칠 때 스크롤로 버튼까지 닿게 하기 위한 추가 여백
  static const double _scrollBottomInsetForTabBar = 147.0;

  /// 스크롤 끝에서 탭바·손가락 여유까지 더 내릴 수 있게 하는 추가 하단 공간
  static const double _scrollExtraTailSpace = 56.0;

  /// 물품/공과금 칩 한 줄 높이(패딩 포함 추정) — 대칭 간격 계산용
  static const double _filterChipRowHeight = 46.0;

  /// [PartitionReportScreen] 과 동일 — band 계산 시 대칭 반쪽 높이 바닥
  static const double _minSymmetricPadBandHalf = 14.0;

  /// 리포트 `symmetricPad + 3`(조회 기간 행 상·하)과 동일
  static const double _anchorVerticalInsetBonus = 3.0;

  /// `band`에서 나눈 대칭 여백에 곱함 (리포트 `_chipVerticalSpacingScale` 과 동일)
  static const double _chipVerticalSpacingScale = 0.5;

  /// 리포트 `_reportSectionGap` 과 통일 — 메인 카드와 하단 액션 줄 사이
  static const double _betweenMainCardAndActions = 24.0;

  /// 리포트 목록 마지막 `SizedBox(16)` 과 통일
  static const double _scrollListTailGap = 16.0;
  static const double _spacingSmall = 10.0;
  static const double _spacingMedium = 16.0;
  static const double _spacingLarge = 20.0;
  static const double _borderRadiusSmall = 24.0;
  static const double _borderRadiusMedium = 28.0;
  static const double _borderRadiusLarge = 32.0;
  int _filterIndex = 0; // 0: 물품, 1: 공과금
  late DateTime _startDate;
  late DateTime _endDate;

  /// 표 데이터 (수동 추가·수정 반영). 더미는 디버그·미로그인 시에만 채움.
  List<SharedExpenseTableItem> _goodsExpenseItems = [];
  List<SharedExpenseTableItem> _utilityExpenseItems = [];
  bool? _sharedExpenseDummySynced;
  AlarmNavigationController? _alarmNav;
  bool _alarmListenerAttached = false;

  final SupplyService _supplyService = SupplyService();
  final UtilityBillService _utilityBillService = UtilityBillService();
  final AuthService _authService = AuthService();
  bool _goodsPurchasesLoading = false;
  bool _utilityBillsLoading = false;

  /// 표는 세로 스크롤 대신 좌우 페이지로 넘김
  /// (필드에서 즉시 초기화: 핫 리로드 시 initState가 다시 안 돌아 late 미초기화 방지)
  final PageController _tablePageController = PageController();
  int _tablePageIndex = 0;

  /// 수동 정산 반영: 여러 행 선택 모드 (연필 반대 버튼으로 진입)
  bool _tableSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};

  static const int _tableItemsPerPage = 5;

  /// 표 `PageView` 세로 고정 높이 — 행은 `_tableItemsPerPage`칸 위에서부터 고정 슬롯
  static const double _tablePageViewHeightFixed = 132.0;

  double get _tablePageViewHeight => _tablePageViewHeightFixed;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 오늘 포함 최근 7일 (이전 6일 + 오늘)
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryConsumeAlarmNavigationPending();
    });
  }

  void _attachAlarmNavigationListenerIfNeeded() {
    final nav = Provider.of<AlarmNavigationController>(context, listen: false);
    _alarmNav ??= nav;
    if (_alarmListenerAttached) return;
    _alarmListenerAttached = true;
    _alarmNav!.addListener(_onAlarmNavigationFromController);
  }

  void _onAlarmNavigationFromController() {
    _tryConsumeAlarmNavigationPending();
  }

  void _tryConsumeAlarmNavigationPending() {
    if (!mounted) return;
    final nav = _alarmNav ??
        Provider.of<AlarmNavigationController>(context, listen: false);
    _alarmNav = nav;
    final pending = nav.takePending();
    if (pending == null) return;
    unawaited(_openSettlementForAlarmPending(pending));
  }

  /// 알림 `referenceId`(settlementId)로 공용소비 정산 UI를 엽니다 (문서 흐름).
  Future<void> _openSettlementForAlarmPending(AlarmNavPending pending) async {
    if (!mounted) return;
    if (!_useGoodsPurchasesApi(context)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '정산번호 ${pending.settlementId} 알림입니다. 실제 로그인 후 공용소비에서 정산을 확인할 수 있어요.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final t = pending.noticeType;
    final isSupply = t == AlarmNoticeType.supplySettlementRequested ||
        t == AlarmNoticeType.supplySettlementConfirmed;
    final isBill = t == AlarmNoticeType.billSettlementRequested ||
        t == AlarmNoticeType.billSettlementConfirmed;

    if (!isSupply && !isBill) return;

    if (mounted) {
      setState(() => _filterIndex = isSupply ? 0 : 1);
    }
    _scheduleTablePageJump();

    if (isSupply) {
      await _showSupplySettlementFromAlarm(pending.settlementId);
    } else {
      await _showBillSettlementFromAlarm(pending.settlementId);
    }
  }

  Future<void> _showSupplySettlementFromAlarm(int settlementId) async {
    try {
      final detail = await _supplyService.fetchSettlementDetail(settlementId);
      if (!mounted) return;
      final shouldConfirm = await _showAlarmSettlementDialog(
        title: '공동 구매 정산',
        settlementId: detail.settlementId,
        statusLabel: detail.isConfirmed ? '확정 완료' : '확정 필요',
        statusAccent: detail.isConfirmed,
        totalAmountLabel: '총액',
        totalAmountValue: '${detail.totalAmount}원',
        splitAmountLabel: '1인 부담',
        splitAmountValue: '${detail.amountPerMember}원',
        itemLabel: '구매 항목',
        items: detail.items
            .map(
              (e) => (
                title: e.itemName,
                value: '${e.amount}원',
              ),
            )
            .toList(),
        confirmLabel: detail.isConfirmed ? null : '정산 확정',
      );
      if (shouldConfirm != true) return;

      try {
        await _supplyService.confirmSettlement(settlementId);
        if (!mounted) return;
        await _loadGoodsPurchases();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('정산을 확정했습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        final msg = e is ApiException ? e.message : '정산 확정에 실패했습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : '정산 정보를 불러오지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showBillSettlementFromAlarm(int settlementId) async {
    try {
      final detail =
          await _utilityBillService.fetchBillSettlementDetail(settlementId);
      if (!mounted) return;
      if (detail.isConfirmed) {
        context.read<AlarmNavigationController>().registerBillSettlementConfirmedForAlarmUi(
              detail.settlementId,
            );
      }
      final shouldConfirm = await _showAlarmSettlementDialog(
        title: '공과금 정산',
        settlementId: detail.settlementId,
        statusLabel: detail.isConfirmed ? '정산 완료' : '정산 필요',
        statusAccent: detail.isConfirmed,
        totalAmountLabel: '총액',
        totalAmountValue: '${detail.totalAmount}원',
        splitAmountLabel: '1인 부담',
        splitAmountValue: '${detail.amountPerMember}원',
        itemLabel: '청구 항목',
        items: detail.items
            .map(
              (e) => (
                title: e.utilityTypeName,
                value: '${e.amount}원',
              ),
            )
            .toList(),
        confirmLabel: detail.isConfirmed ? null : '정산 완료',
      );
      if (shouldConfirm != true) return;

      try {
        await _utilityBillService.confirmBillSettlement(settlementId);
        if (!mounted) return;
        context.read<AlarmNavigationController>().registerBillSettlementConfirmedForAlarmUi(
              settlementId,
            );
        await _loadUtilityBills();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('정산을 완료했습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        final msg = e is ApiException ? e.message : '정산 완료에 실패했습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : '정산 정보를 불러오지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<bool?> _showAlarmSettlementDialog({
    required String title,
    required int settlementId,
    required String statusLabel,
    required bool statusAccent,
    required String totalAmountLabel,
    required String totalAmountValue,
    required String splitAmountLabel,
    required String splitAmountValue,
    required String itemLabel,
    required List<({String title, String value})> items,
    String? confirmLabel,
  }) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final listHeight = (screenHeight * 0.28).clamp(140.0, 240.0);

    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.56),
      builder: (ctx) => PartitionGlassDialog.modal(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  Positioned(
                    right: -8,
                    child: PartitionModalCloseButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '알림으로 도착한 정산 내역이에요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.68),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: 'Pretendard Variable',
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.16),
                  width: 0.6,
                ),
                color: Colors.white.withOpacity(0.05),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '정산번호 #$settlementId',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusAccent
                                ? HomeShareStyle.point
                                : Colors.white.withOpacity(0.78),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: statusAccent
                          ? HomeShareStyle.pointFillSoft(0.16)
                          : Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color: statusAccent
                            ? HomeShareStyle.pointStroke(0.32)
                            : Colors.white.withOpacity(0.12),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      statusAccent ? '완료' : '진행 중',
                      style: TextStyle(
                        color: statusAccent
                            ? HomeShareStyle.point
                            : Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildAlarmSettlementInfoCard(
                    label: totalAmountLabel,
                    value: totalAmountValue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildAlarmSettlementInfoCard(
                    label: splitAmountLabel,
                    value: splitAmountValue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              itemLabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.94),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                  width: 0.6,
                ),
                color: Colors.white.withOpacity(0.04),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: listHeight),
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '표시할 항목이 없습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.52),
                            fontSize: 12,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Pretendard Variable',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  item.value,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildAlarmSettlementActionButton(
                    label: '닫기',
                    filled: false,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                if (confirmLabel != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAlarmSettlementActionButton(
                      label: confirmLabel,
                      filled: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmSettlementInfoCard({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
          width: 0.6,
        ),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: 'Pretendard Variable',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmSettlementActionButton({
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: filled ? Colors.white.withOpacity(0.12) : Colors.transparent,
            border: Border.all(
              color: Colors.white.withOpacity(filled ? 0.2 : 0.14),
              width: 0.6,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.96),
                fontSize: 14,
                fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAlarmNavigationListenerIfNeeded();
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context).isAuthenticated,
    );
    if (_sharedExpenseDummySynced == useDummy) return;
    _sharedExpenseDummySynced = useDummy;
    setState(() {
      if (useDummy) {
        _goodsExpenseItems = List<SharedExpenseTableItem>.from(
            _dummyItemsForSharedExpenseTable(0));
        _utilityExpenseItems = List<SharedExpenseTableItem>.from(
            _dummyItemsForSharedExpenseTable(1));
      } else {
        _goodsExpenseItems = [];
        _utilityExpenseItems = [];
      }
      _tableSelectionMode = false;
      _selectedRowIndices.clear();
      _clampTablePageIndex();
    });
    if (!useDummy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadGoodsPurchases();
        _loadUtilityBills();
      });
    }
    _scheduleTablePageJump();
  }

  List<SharedExpenseTableItem> _itemsForCurrentFilter() =>
      _filterIndex == 0 ? _goodsExpenseItems : _utilityExpenseItems;

  bool _useGoodsPurchasesApi(BuildContext context) {
    return !usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
  }

  String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadGoodsPurchases() async {
    if (!mounted) return;
    if (!_useGoodsPurchasesApi(context)) return;
    setState(() => _goodsPurchasesLoading = true);
    try {
      final result = await _supplyService.fetchPurchases(
        startDate: _dateToIso(_startDate),
        endDate: _dateToIso(_endDate),
      );
      if (!mounted) return;
      setState(() {
        _goodsExpenseItems =
            result.purchases.map((e) => e.toSharedExpenseTableItem()).toList();
        _goodsPurchasesLoading = false;
        _clampTablePageIndex();
      });
      _scheduleTablePageJump();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _goodsPurchasesLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _goodsPurchasesLoading = false);
    }
  }

  Future<void> _loadUtilityBills() async {
    if (!mounted) return;
    if (!_useGoodsPurchasesApi(context)) return;
    setState(() => _utilityBillsLoading = true);
    try {
      final bills = await _utilityBillService.fetchBills(
        startDate: _dateToIso(_startDate),
        endDate: _dateToIso(_endDate),
      );
      if (!mounted) return;
      setState(() {
        final items = bills.map((e) => e.toSharedExpenseTableItem()).toList();
        items.sort((a, b) {
          final dueDateA =
              utilityBillNextDueDate(_startDate, a.utilityPayDay ?? 32);
          final dueDateB =
              utilityBillNextDueDate(_startDate, b.utilityPayDay ?? 32);
          return dueDateA.compareTo(dueDateB);
        });
        _utilityExpenseItems = items;
        _utilityBillsLoading = false;
        _clampTablePageIndex();
      });
      _scheduleTablePageJump();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _utilityBillsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _utilityBillsLoading = false);
    }
  }

  Future<void> _onPullToRefresh() async {
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    if (useDummy) {
      if (!mounted) return;
      setState(() {
        _goodsExpenseItems = List<SharedExpenseTableItem>.from(
            _dummyItemsForSharedExpenseTable(0));
        _utilityExpenseItems = List<SharedExpenseTableItem>.from(
            _dummyItemsForSharedExpenseTable(1));
        _clampTablePageIndex();
      });
      _scheduleTablePageJump();
      return;
    }
    await Future.wait<void>([
      _loadGoodsPurchases(),
      _loadUtilityBills(),
    ]);
  }

  /// 연필 모달 닫은 뒤: GET으로 맞추되, 새로 등록·수정한 행은 응답에 없으면 모달 상태를 합침 (빈 배열 필터 버그 등 대비).
  Future<void> _syncUtilityExpenseItemsAfterManualModal(
    List<SharedExpenseTableItem> modalItems,
  ) async {
    if (!mounted || !_useGoodsPurchasesApi(context)) return;
    await _loadUtilityBills();
    if (!mounted) return;
    final serverIds = _utilityExpenseItems
        .map((e) => e.billId)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    final missingFromGet = modalItems
        .where((e) =>
            e.billId != null && e.billId! > 0 && !serverIds.contains(e.billId!))
        .toList();
    if (missingFromGet.isEmpty) return;
    setState(() {
      _utilityExpenseItems = [...missingFromGet, ..._utilityExpenseItems];
      _clampTablePageIndex();
    });
    _scheduleTablePageJump();
  }

  void _clampTablePageIndex() {
    final pages = _paginateSharedExpenseItems(
      _itemsForCurrentFilter(),
      _tableItemsPerPage,
    );
    final maxPage = pages.isEmpty ? 0 : pages.length - 1;
    if (_tablePageIndex > maxPage) {
      _tablePageIndex = maxPage;
    }
  }

  void _scheduleTablePageJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tablePageController.hasClients) {
        final pages = _paginateSharedExpenseItems(
          _itemsForCurrentFilter(),
          _tableItemsPerPage,
        );
        final maxPage = pages.isEmpty ? 0 : pages.length - 1;
        final ix = _tablePageIndex.clamp(0, maxPage);
        _tablePageController.jumpToPage(ix);
      }
    });
  }

  void _showManualSharedExpenseModal({
    int? initialEditIndex,
    bool addOnlyEntry = false,
  }) {
    final goodsFromApi = _filterIndex == 0 && _useGoodsPurchasesApi(context);
    final utilityFromApi = _filterIndex == 1 && _useGoodsPurchasesApi(context);
    showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => SharedExpenseManualModal(
        isUtility: _filterIndex == 1,
        deletePurchasesViaApi: goodsFromApi,
        submitUtilityViaApi: utilityFromApi,
        utilityPaymentsRangeStartIso:
            utilityFromApi ? _dateToIso(_startDate) : null,
        utilityPaymentsRangeEndIso:
            utilityFromApi ? _dateToIso(_endDate) : null,

        /// 서버(공용소비) 물품도 표와 동일 목록을 넣어 [purchaseId]로 PATCH 수정 가능
        initialItems: List<SharedExpenseTableItem>.from(
          _itemsForCurrentFilter(),
        ),
        initialOpenEditIndex: initialEditIndex,
        addOnlyEntry: addOnlyEntry,
        onApply: (next) {
          if (goodsFromApi) {
            _loadGoodsPurchases();
          } else if (utilityFromApi) {
            Future<void>.microtask(
              () => _syncUtilityExpenseItemsAfterManualModal(next),
            );
          } else {
            setState(() {
              if (_filterIndex == 0) {
                _goodsExpenseItems = next;
              } else {
                _utilityExpenseItems = next;
              }
              _clampTablePageIndex();
            });
            _scheduleTablePageJump();
          }
        },
      ),
    ).then((applied) {
      if (applied == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _filterIndex == 1 ? '공과금 내역을 반영했어요.' : '공용 소비 내역을 반영했어요.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<List<int>> _fetchHouseholdMemberIds() async {
    final members = await _authService.fetchHouseholdMembers();
    final memberIds = members.map((e) => e.userId).toList();
    if (memberIds.isEmpty) {
      throw ApiException(
        message: '정산에 포함할 멤버를 찾지 못했어요. 로그인·그룹 상태를 확인해 주세요.',
      );
    }
    return memberIds;
  }

  /// 공동 구매 정산: 멤버 알림 동의 후 POST → PATCH 완료까지 진행.
  Future<bool?> _confirmSettlementNotifyDialog() async {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogCtx) => _SharedGlassDialogShell(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      '정산 알림',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                    Positioned(
                      right: -8,
                      child: PartitionModalCloseButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.16),
                    width: 0.6,
                  ),
                  color: Colors.white.withOpacity(0.05),
                ),
                child: Text(
                  '다른 멤버에게 정산 알림을 보낼까요?\n'
                  '「예, 보내기」를 누르면 정산 요청이 진행되며 멤버에게 안내될 수 있어요.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.84),
                    fontSize: 14,
                    height: 1.45,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildAlarmSettlementActionButton(
                      label: '아니요',
                      filled: false,
                      onTap: () => Navigator.of(dialogCtx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAlarmSettlementActionButton(
                      label: '예, 보내기',
                      filled: true,
                      onTap: () => Navigator.of(dialogCtx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
      ),
    );
  }

  Future<int> _requestGoodsSettlement({
    required List<int> purchaseIds,
  }) async {
    final memberIds = await _fetchHouseholdMemberIds();
    final req = await _supplyService.requestSettlement(
      purchaseIds: purchaseIds,
      memberIds: memberIds,
    );
    return req.settlementId;
  }

  Future<void> _executeGoodsSettlementPostAndConfirm({
    required List<int> purchaseIds,
  }) async {
    final settlementId = await _requestGoodsSettlement(purchaseIds: purchaseIds);
    await _supplyService.confirmSettlement(settlementId);
    try {
      final detail = await _supplyService.fetchSettlementDetail(settlementId);
      if (!detail.isConfirmed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '정산은 접수되었지만 완료 확인이 되지 않았어요. 잠시 후 목록을 새로고침해 주세요.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // POST/PATCH 성공 후 상세 조회만 실패한 경우 무시
    }
  }

  Future<List<int>> _unsettledUtilityPaymentIdsForBillIds(
      List<int> billIds) {
    return _utilityBillService.fetchUnsettledPaymentIds(
      startDate: _dateToIso(_startDate),
      endDate: _dateToIso(_endDate),
      billIds: billIds,
    );
  }

  Future<int> _requestUtilityBillSettlement({
    required List<int> paymentIds,
  }) async {
    final memberIds = await _fetchHouseholdMemberIds();
    final req = await _utilityBillService.requestBillSettlement(
      paymentIds: paymentIds,
      memberIds: memberIds,
    );
    return req.settlementId;
  }

  Future<void> _executeUtilityBillSettlementPostAndConfirm({
    required List<int> billIds,
  }) async {
    final paymentIds = await _unsettledUtilityPaymentIdsForBillIds(billIds);
    if (paymentIds.isEmpty) {
      throw ApiException(
        message:
            '해당 기간에 정산 요청 가능한 미정산(UNSETTLED) 납부 기록이 없습니다. 공용소비 표의 기간이나 변동 공과금 금액 입력을 확인해 주세요.',
      );
    }
    final settlementId =
        await _requestUtilityBillSettlement(paymentIds: paymentIds);
    await _utilityBillService.confirmBillSettlement(settlementId);
    if (mounted) {
      context.read<AlarmNavigationController>().registerBillSettlementConfirmedForAlarmUi(
            settlementId,
          );
    }
    try {
      final detail =
          await _utilityBillService.fetchBillSettlementDetail(settlementId);
      if (!detail.isConfirmed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '정산은 접수되었지만 완료 확인이 되지 않았어요. 잠시 후 목록을 새로고침해 주세요.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // POST/PATCH 성공 후 상세 조회만 실패한 경우 무시
    }
  }

  void _showItemDetailSheet(SharedExpenseTableItem item, int globalIndex) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => SharedExpenseItemDetailSheet(
        key: ValueKey(
          '${item.purchaseId ?? item.paymentId ?? item.billId ?? 'local'}_${globalIndex}_${item.manuallySettled}',
        ),
        item: item,
        isUtility: _filterIndex == 1,
        onSettlementRequest: item.manuallySettled
            ? null
            : () async {
                final goodsApi =
                    _filterIndex == 0 && _useGoodsPurchasesApi(context);
                final utilityApi =
                    _filterIndex == 1 && _useGoodsPurchasesApi(context);
                final pid = item.purchaseId;
                final bid = item.billId;

                try {
                  if (goodsApi && pid != null && pid > 0) {
                    final agreed = await _confirmSettlementNotifyDialog();
                    if (agreed != true || !mounted) return;
                    await _requestGoodsSettlement(purchaseIds: [pid]);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    await _loadGoodsPurchases();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('정산 요청을 보냈어요. 그룹원에게 알림이 전달됩니다.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (utilityApi && bid != null && bid > 0) {
                    final agreed = await _confirmSettlementNotifyDialog();
                    if (agreed != true || !mounted) return;
                    final paymentIds =
                        await _unsettledUtilityPaymentIdsForBillIds([bid]);
                    if (paymentIds.isEmpty) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '정산할 미정산 납부 기록을 찾지 못했어요. 표 기간을 넓히거나 변동 공과금 금액을 입력한 뒤 다시 시도해 주세요.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    await _requestUtilityBillSettlement(
                        paymentIds: paymentIds);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    await _loadUtilityBills();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('정산 요청을 보냈어요. 그룹원에게 알림이 전달됩니다.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('정산 요청은 실제 서버 연동 항목에서만 사용할 수 있어요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } on ApiException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
        onSettlementComplete: item.manuallySettled
            ? null
            : () async {
                final goodsApi =
                    _filterIndex == 0 && _useGoodsPurchasesApi(context);
                final utilityApi =
                    _filterIndex == 1 && _useGoodsPurchasesApi(context);
                final pid = item.purchaseId;
                final bid = item.billId;

                try {
                  if (goodsApi && pid != null && pid > 0) {
                    final agreed = await _confirmSettlementNotifyDialog();
                    if (agreed != true || !mounted) return;
                    await _executeGoodsSettlementPostAndConfirm(
                      purchaseIds: [pid],
                    );
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    await _loadGoodsPurchases();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('정산 완료 처리했어요.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (utilityApi && bid != null && bid > 0) {
                    final agreed = await _confirmSettlementNotifyDialog();
                    if (agreed != true || !mounted) return;
                    await _executeUtilityBillSettlementPostAndConfirm(
                      billIds: [bid],
                    );
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    await _loadUtilityBills();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('정산 완료 처리했어요.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (!mounted) return;
                  setState(() {
                    final list =
                        List<SharedExpenseTableItem>.from(_itemsForCurrentFilter());
                    if (globalIndex >= 0 && globalIndex < list.length) {
                      list[globalIndex] = list[globalIndex].copyWith(
                        manuallySettled: true,
                      );
                      if (_filterIndex == 0) {
                        _goodsExpenseItems = list;
                      } else {
                        _utilityExpenseItems = list;
                      }
                    }
                  });
                } on ApiException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
        onEditRequested: () => _showManualSharedExpenseModal(
          initialEditIndex: globalIndex,
        ),
        onDeleteRequested: () => _deleteRowsAtIndices({globalIndex}),
      ),
    );
  }

  @override
  void dispose() {
    if (_alarmListenerAttached) {
      _alarmNav?.removeListener(_onAlarmNavigationFromController);
    }
    _tablePageController.dispose();
    super.dispose();
  }

  /// 핫 리로드 후에도 API 목록·정산 여부가 다시 반영되도록 (State 유지 시 didChangeDependencies는 조기 return)
  @override
  void reassemble() {
    super.reassemble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_useGoodsPurchasesApi(context)) {
        _loadGoodsPurchases();
        _loadUtilityBills();
      }
    });
  }

  Future<void> _selectDate(bool isStartDate) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 과거 구매·납부 내역 조회 가능 (수동 등록 모달과 동일한 하한)
    final firstDate = DateTime(today.year - 20, 1, 1);
    final maxDate = today.add(const Duration(days: 365)); // 1년 후까지

    final selectedDate = isStartDate ? _startDate : _endDate;
    var initialDate = selectedDate;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(maxDate)) initialDate = maxDate;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => GlassmorphicDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: maxDate,
        isStartDate: isStartDate,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final selectedDate = DateTime(picked.year, picked.month, picked.day);
        if (isStartDate) {
          _startDate = selectedDate;
          // 시작일이 종료일보다 늦으면 종료일도 같이 변경
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = selectedDate;
          // 종료일이 시작일보다 이전이면 시작일도 같이 변경
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
      if (mounted && _useGoodsPurchasesApi(context)) {
        _loadGoodsPurchases();
        _loadUtilityBills();
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
  }

  /// 메인 글래스 카드(제목~표~페이지) — HUG 레이아웃에 맞춘 대략 높이 (칩 간격 계산용)
  double _estimateMainCardContentHeightForFilter(int _) {
    const outerPadV = 20.0 + 18.0;
    const titleBlock = 26.0 + _spacingMedium;
    const dateRowH = 52.0;
    // 물품·공과금 모두 날짜 아래에 정산하기 버튼 한 줄 (동일 높이)
    const settlementButtonBlock = _spacingMedium + 46.0;
    const beforeTable = _spacingLarge;
    // 표 패널 + 페이지 컨트롤 + 표 바깥(오른쪽) 추가·수정 원형 줄
    const tablePanel = 6.0 +
        8.0 +
        44.0 +
        8.0 +
        _tablePageViewHeightFixed +
        8.0 +
        36.0 +
        12.0 +
        32.0;
    return outerPadV +
        titleBlock +
        dateRowH +
        settlementButtonBlock +
        beforeTable +
        tablePanel;
  }

  /// 칩 아래(카드+하단 버튼) 고정 블록 높이 — 칩 위·아래 대칭 여백 계산용
  /// 정산하기는 카드 안(날짜 아래) / 하단 액션은 탭당 버튼 1개
  double _estimatedBelowChipsContentHeightForFilter(int filterIndex) {
    final cardH = _estimateMainCardContentHeightForFilter(filterIndex);
    final actionCount = 1;
    final actionsH = 46 * actionCount +
        _spacingSmall * (actionCount > 1 ? actionCount - 1 : 0);
    return cardH + _betweenMainCardAndActions + actionsH + _scrollListTailGap;
  }

  @override
  Widget build(BuildContext context) {
    final scrollBottomPadding = _contentPaddingBottom +
        MediaQuery.viewPaddingOf(context).bottom +
        _scrollBottomInsetForTabBar +
        _scrollExtraTailSpace;

    // 패턴: Column(헤더 고정) + Expanded(남은 높이) + ListView — 스크롤 안에 Expanded 넣지 않음
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 제약이 비정상이면(무한 높이·0 등) 본문 전체가 사라지지 않도록 화면 기준으로 대체.
              // 부모 변경·탭 전환 등으로 `LayoutBuilder`만 유한 높이를 못 받는 경우가 있음.
              final mq = MediaQuery.sizeOf(context);
              final rawH = constraints.maxHeight;
              final viewportH =
                  (constraints.hasBoundedHeight && rawH.isFinite && rawH > 0)
                      ? rawH
                      : (mq.height -
                              _headerHeight -
                              MediaQuery.paddingOf(context).top -
                              MediaQuery.paddingOf(context).bottom -
                              150)
                          .clamp(120.0, 100000.0);
              // 물품/공과금 전환 시 칩이 위아래로 움직이지 않도록, 더 큰 쪽 레이아웃 높이로만 여백 계산
              final hGoods = _estimatedBelowChipsContentHeightForFilter(0);
              final hUtility = _estimatedBelowChipsContentHeightForFilter(1);
              final belowChipsContentH = hGoods > hUtility ? hGoods : hUtility;
              final band =
                  viewportH - belowChipsContentH - _contentPaddingBottom;
              // 리포트: `(band - _dateCardAnchorHeight) / 2` + `_minSymmetricPadBandHalf`
              final symmetricPadRaw = (band - _filterChipRowHeight) / 2.0;
              final symmetricPadFull =
                  symmetricPadRaw < _minSymmetricPadBandHalf
                      ? _minSymmetricPadBandHalf
                      : symmetricPadRaw;
              final symmetricPad =
                  (symmetricPadFull * _chipVerticalSpacingScale)
                      .clamp(12.0, 88.0);
              final anchorVerticalInset =
                  ((symmetricPad + _anchorVerticalInsetBonus) * 0.7)
                      .clamp(8.0, 64.0);

              final horizontalPadding =
                  PartitionUiTokens.resolveHorizontalPadding(
                    constraints.maxWidth.isFinite && constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : mq.width,
                  );

              return RefreshIndicator(
                onRefresh: _onPullToRefresh,
                color: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.15),
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    scrollBottomPadding,
                  ),
                  children: [
                    SizedBox(height: anchorVerticalInset),
                    _buildFilterChips(),
                    SizedBox(height: anchorVerticalInset),
                    _buildMainCard(),
                    const SizedBox(height: _betweenMainCardAndActions),
                    ..._buildActionButtons(),
                    const SizedBox(height: _scrollListTailGap),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final topInset = MediaQuery.paddingOf(context).top;
    return SizedBox(
      width: double.infinity,
      height: topInset + _headerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            height: topInset + _headerHeight,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color.fromRGBO(214, 218, 226, 0.8),
                  width: 0.65,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                SizedBox(height: topInset),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '공용소비',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Pretendard Variable',
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const SizedBox(height: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    // 표·모달 인풋과 동일한 가로 폭(스크롤 패딩 안에서 전체 너비)으로 1:1 분할
    // ListView/SliverList 자식은 세로 max가 무한 → Row.stretch는 무한 높이 제약과 충돌
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SharedExpenseFilterChip(
            label: '물품',
            selected: _filterIndex == 0,
            width: double.infinity,
            horizontalPadding: 14,
            onTap: () {
              setState(() {
                _filterIndex = 0;
                _tablePageIndex = 0;
                _tableSelectionMode = false;
                _selectedRowIndices.clear();
              });
              if (_useGoodsPurchasesApi(context)) {
                _loadGoodsPurchases();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_tablePageController.hasClients) {
                  _tablePageController.jumpToPage(0);
                }
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SharedExpenseFilterChip(
            label: '공과금',
            selected: _filterIndex == 1,
            width: double.infinity,
            horizontalPadding: 14,
            onTap: () {
              setState(() {
                _filterIndex = 1;
                _tablePageIndex = 0;
                _tableSelectionMode = false;
                _selectedRowIndices.clear();
              });
              if (_useGoodsPurchasesApi(context)) {
                _loadUtilityBills();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_tablePageController.hasClients) {
                  _tablePageController.jumpToPage(0);
                }
              });
            },
          ),
        ),
      ],
    );
  }

  /// 바깥 카드 높이는 내용에 맞춤(HUG). `Expanded` 없음 → 스크롤 `Column` 안에서 안전
  Widget _buildMainCard() {
    final isUtility = _filterIndex == 1;
    final tablePages = _paginateSharedExpenseItems(
      _itemsForCurrentFilter(),
      _tableItemsPerPage,
    );
    final tablePageIndexSafe =
        _tablePageIndex.clamp(0, tablePages.length - 1).toInt();
    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      // 14+6(제목만)=20 — 날짜·시작·종료 줄과 표가 같은 폭으로 조금 더 넓게
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: Text(
                isUtility ? '공과금 관리' : '공용 물품 관리',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Pretendard Variable',
                  height: 1.2,
                  letterSpacing: -0.15,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.28),
                      offset: const Offset(0, 0.5),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: _spacingMedium),
          _buildDateRangeGlassRow(),
          if (isUtility) ...[
            const SizedBox(height: _spacingMedium),
            PrimaryButton(
              label: '공과금 정산하기',
              enabled: !_tableSelectionMode,
              onPressed: _showUtilityBillSettlementFlow,
            ),
          ] else ...[
            const SizedBox(height: _spacingMedium),
            PrimaryButton(
              label: '공용 구매 물품 정산 요청',
              enabled: !_tableSelectionMode,
              onPressed: _showSharedExpenseSettlementFlow,
            ),
          ],
          const SizedBox(height: _spacingLarge),
          FrostedPanel(
            borderRadius: BorderRadius.circular(20),
            backgroundOpacity: 0.0,
            // 좌우(6)와 동일하게 상단 인셋 축소 — 레이블~테두리 간격 통일
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTableHeader(selectionMode: _tableSelectionMode),
                const SizedBox(height: 8),
                SizedBox(
                  height: _tablePageViewHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView.builder(
                        controller: _tablePageController,
                        physics: const PageScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        onPageChanged: (i) {
                          setState(() => _tablePageIndex = i);
                        },
                        itemCount: tablePages.length,
                        itemBuilder: (context, pageIndex) {
                          final pageItems = tablePages[pageIndex];
                          // 정산 여부·행 구성이 바뀌면 PageView 자식이 확실히 갱신되도록
                          final pageKey = pageItems.isEmpty
                              ? 'p$pageIndex'
                              : pageItems
                                  .map(
                                    (e) =>
                                        '${e.purchaseId ?? e.paymentId ?? e.billId ?? e.name.hashCode}_${e.manuallySettled}',
                                  )
                                  .join('|');
                          return _SharedExpenseTableBody(
                            key: ValueKey(pageKey),
                            filterIndex: _filterIndex,
                            items: pageItems,
                            onNameTap: _showItemDetailSheet,
                            selectionMode: _tableSelectionMode,
                            pageIndex: pageIndex,
                            itemsPerPage: _tableItemsPerPage,
                            rowSlotHeight:
                                _tablePageViewHeight / _tableItemsPerPage,
                            selectedIndices: _selectedRowIndices,
                            onToggleRow: _toggleRowSelection,
                          );
                        },
                      ),
                      if (((!isUtility && _goodsPurchasesLoading) ||
                              (isUtility && _utilityBillsLoading)) &&
                          _useGoodsPurchasesApi(context))
                        Container(
                          color: Colors.black.withOpacity(0.25),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildPageControl(
                  pageCount: tablePages.length,
                  currentIndex: tablePageIndexSafe,
                ),
              ],
            ),
          ),
          // 표 아래: 왼쪽 = 선택 모드 진입·종료, 오른쪽 = `+`(직접 추가) 또는 전체선택·삭제
          // 가로 패딩은 표 FrostedPanel(6)과 같게 — 오른쪽 끝 버튼이 표 수량 열과 세로 정렬
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Tooltip(
                  message:
                      _tableSelectionMode ? '선택 종료' : '여러 항목 선택 후 삭제',
                  child: _buildCircleArrow(
                    _tableSelectionMode
                        ? Icons.close_rounded
                        : Icons.playlist_add_check_rounded,
                    onTap: _tableSelectionMode
                        ? _exitTableSelectionMode
                        : _enterTableSelectionMode,
                  ),
                ),
                const Spacer(),
                if (_tableSelectionMode)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildSelectionActionChip(
                            '전체선택',
                            _selectAllRowsInFilter,
                          ),
                          const SizedBox(width: 10),
                          _buildSelectionActionChip(
                            '삭제',
                            () => _deleteSelectedRows(),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Tooltip(
                    message: isUtility ? '공과금 직접 추가' : '소비 내역 직접 추가',
                    child: _buildCircleArrow(
                      Icons.add_rounded,
                      onTap: () => _showManualSharedExpenseModal(
                        addOnlyEntry: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons() {
    final isUtility = _filterIndex == 1;

    if (isUtility) {
      return [];
    } else {
      return [
        PrimaryButton(
          label: '파티션 AI 영수증 인식',
          onPressed: _showAiReceiptRecognitionFlow,
        ),
      ];
    }
  }

  /// 시작일·종료일을 한 줄에 두고, 카드·칩과 동일한 글래스 패널로 감쌈
  Widget _buildDateRangeGlassRow() {
    const labelStyle = TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      fontFamily: 'Pretendard Variable',
    );
    const dateStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFamily: 'Pretendard Variable',
    );

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusSmall),
      backgroundOpacity: 0.08,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildDateInlineSegment(
                label: '시작일',
                date: _formatDate(_startDate),
                isStartDate: true,
                labelStyle: labelStyle,
                dateStyle: dateStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.white.withOpacity(0.22),
              ),
            ),
            Expanded(
              child: _buildDateInlineSegment(
                label: '종료일',
                date: _formatDate(_endDate),
                isStartDate: false,
                labelStyle: labelStyle,
                dateStyle: dateStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateInlineSegment({
    required String label,
    required String date,
    required bool isStartDate,
    required TextStyle labelStyle,
    required TextStyle dateStyle,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectDate(isStartDate),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                date,
                textAlign: TextAlign.center,
                style: dateStyle,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader({required bool selectionMode}) {
    // 데이터 행과 동일 fontSize·height (굵기만 헤더 강조) — 살짝 축소해 날짜·금액·수량 한 줄 표시
    const headerStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      height: 1.35,
    );

    final isUtility = _filterIndex == 1;
    final lastHeaderLabel = isUtility ? '비고' : '수량';
    final dateHeaderLabel = isUtility ? '납부일' : '날짜';
    final amountHeaderLabel = isUtility ? '납부액' : '금액';
    // 공과금: 납부일 가독성을 위해 내용 폭을 줄이고 날짜 폭을 늘림.
    // 물품은 기존 비율 유지.
    final contentFlex = isUtility ? 3 : 4;
    final dateFlex = isUtility ? 3 : 3;
    final lastColFlex = isUtility ? 3 : 2;

    // 내용 : 날짜 : 금액 : 마지막열
    const padContent = 4.0;
    const padDate = 3.0;
    const padAmount = 3.0;
    const padQty = 3.0;

    const headerRowHeight = 34.0;
    return SizedBox(
      height: headerRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 선택 모드에서도 행 체크박스 열 너비만 맞추고, 상단 체크 레이블은 표시하지 않음
          if (selectionMode) ...[
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 3),
          ],
          Expanded(
            flex: contentFlex,
            child: Padding(
              // 표 제목 캡슐만 좌우 1px씩 좁게 (데이터 행과 동일 레이아웃 유지)
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FrostedPanel(
                borderRadius: BorderRadius.circular(18),
                backgroundOpacity: 0.08,
                borderColor: const Color.fromRGBO(255, 255, 255, 0.12),
                strokeGradient: const RadialGradient(
                  center: Alignment(0.1, -0.8),
                  radius: 2.2,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.11),
                    Color.fromRGBO(255, 255, 255, 0.01),
                  ],
                  stops: [0.0, 1.0],
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: padContent, vertical: 6),
                child: const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Center(
                    child: Text(
                      '내용',
                      style: headerStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: dateFlex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FrostedPanel(
                borderRadius: BorderRadius.circular(18),
                backgroundOpacity: 0.08,
                borderColor: const Color.fromRGBO(255, 255, 255, 0.12),
                strokeGradient: const RadialGradient(
                  center: Alignment(0.1, -0.8),
                  radius: 2.2,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.11),
                    Color.fromRGBO(255, 255, 255, 0.01),
                  ],
                  stops: [0.0, 1.0],
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: padDate, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Center(
                    child: Text(
                      dateHeaderLabel,
                      style: headerStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FrostedPanel(
                borderRadius: BorderRadius.circular(18),
                backgroundOpacity: 0.08,
                borderColor: const Color.fromRGBO(255, 255, 255, 0.12),
                strokeGradient: const RadialGradient(
                  center: Alignment(0.1, -0.8),
                  radius: 2.2,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.11),
                    Color.fromRGBO(255, 255, 255, 0.01),
                  ],
                  stops: [0.0, 1.0],
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: padAmount, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Center(
                    child: Text(
                      amountHeaderLabel,
                      style: headerStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: lastColFlex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FrostedPanel(
                borderRadius: BorderRadius.circular(18),
                backgroundOpacity: 0.08,
                borderColor: const Color.fromRGBO(255, 255, 255, 0.12),
                strokeGradient: const RadialGradient(
                  center: Alignment(0.1, -0.8),
                  radius: 2.2,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.11),
                    Color.fromRGBO(255, 255, 255, 0.01),
                  ],
                  stops: [0.0, 1.0],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: padQty, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        lastHeaderLabel,
                        style: headerStyle,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageControl({
    required int pageCount,
    required int currentIndex,
  }) {
    void goPrev() {
      if (currentIndex <= 0) return;
      _tablePageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    void goNext() {
      if (currentIndex >= pageCount - 1) return;
      _tablePageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    final canPrev = pageCount > 1 && currentIndex > 0;
    final canNext = pageCount > 1 && currentIndex < pageCount - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleArrow(
          Icons.chevron_left,
          enabled: canPrev,
          onTap: canPrev ? goPrev : null,
        ),
        if (pageCount > 1) ...[
          const SizedBox(width: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(pageCount, (i) {
              final active = i == currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withOpacity(active ? 0.95 : 0.35),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 14),
        ] else
          const SizedBox(width: 16),
        _buildCircleArrow(
          Icons.chevron_right,
          enabled: canNext,
          onTap: canNext ? goNext : null,
        ),
      ],
    );
  }

  Widget _buildCircleArrow(
    IconData icon, {
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.14),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// 선택 모드 — 텍스트 너비에 맞춘 작은 글래스 pill (한 줄 배치용, FrostedPanel 무한 너비 방지)
  Widget _buildSelectionActionChip(String label, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(23),
        splashColor: Colors.white.withOpacity(0.12),
        highlightColor: Colors.white.withOpacity(0.06),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                color: Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: Colors.white.withOpacity(0.85),
                  width: 1,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontFamily: 'Pretendard Variable',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _enterTableSelectionMode() {
    setState(() {
      _tableSelectionMode = true;
      _selectedRowIndices.clear();
    });
  }

  void _exitTableSelectionMode() {
    setState(() {
      _tableSelectionMode = false;
      _selectedRowIndices.clear();
    });
  }

  void _toggleRowSelection(int globalIndex) {
    setState(() {
      if (_selectedRowIndices.contains(globalIndex)) {
        _selectedRowIndices.remove(globalIndex);
      } else {
        _selectedRowIndices.add(globalIndex);
      }
    });
  }

  void _selectAllRowsInFilter() {
    setState(() {
      final n = _itemsForCurrentFilter().length;
      _selectedRowIndices.clear();
      for (var i = 0; i < n; i++) {
        _selectedRowIndices.add(i);
      }
    });
  }

  Future<void> _deleteSelectedRows() async {
    if (_selectedRowIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 항목을 선택해주세요.')),
      );
      return;
    }
    await _deleteRowsAtIndices(Set<int>.from(_selectedRowIndices));
  }

  /// 설정 모달과 동일한 글래스 확인 다이얼로그.
  Future<bool> _confirmGlassDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        constraints: const BoxConstraints(maxWidth: 360),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        fillColor: const Color.fromRGBO(255, 255, 255, 0.12),
        borderColor: const Color.fromRGBO(255, 255, 255, 0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  color: Colors.white.withOpacity(0.88),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 14,
                height: 1.45,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 20),
            _confirmGlassDialogButton(
              label: '취소',
              foregroundColor: PartitionUiTokens.actionText,
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 10),
            _confirmGlassDialogButton(
              label: confirmLabel,
              foregroundColor:
                  destructive ? _destructiveMuted : PartitionUiTokens.actionText,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Widget _confirmGlassDialogButton({
    required String label,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.05),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: PartitionUiTokens.actionFontSize,
                fontWeight: PartitionUiTokens.actionWeight,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRowsAtIndices(Set<int> indices) async {
    if (indices.isEmpty) return;
    final count = indices.length;
    final message = count == 1
        ? '이 항목을 삭제할까요?'
        : '선택한 $count개 항목을 삭제할까요?';
    final ok = await _confirmGlassDialog(
      title: '삭제',
      message: message,
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final goodsApi = _filterIndex == 0 && _useGoodsPurchasesApi(context);
    if (goodsApi) {
      final list = List<SharedExpenseTableItem>.from(_itemsForCurrentFilter());
      final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
      final ids = <int>[];
      for (final i in sorted) {
        if (i < 0 || i >= list.length) continue;
        final pid = list[i].purchaseId;
        if (pid == null || pid <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('서버에 등록된 구매만 삭제할 수 있어요.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        ids.add(pid);
      }
      try {
        for (final pid in ids) {
          await _supplyService.deletePurchase(pid);
        }
        if (!mounted) return;
        setState(() {
          _selectedRowIndices.clear();
          _clampTablePageIndex();
        });
        _scheduleTablePageJump();
        _loadGoodsPurchases();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('선택한 $count개 항목을 삭제했어요.')),
        );
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadGoodsPurchases();
        }
      }
      return;
    }

    final billsApi = _filterIndex == 1 && _useGoodsPurchasesApi(context);
    if (billsApi) {
      final list = List<SharedExpenseTableItem>.from(_itemsForCurrentFilter());
      final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
      final billIds = <int>[];
      for (final i in sorted) {
        if (i < 0 || i >= list.length) continue;
        final bid = list[i].billId;
        if (bid == null || bid <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('서버에 등록된 공과금만 삭제할 수 있어요.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        billIds.add(bid);
      }
      try {
        for (final bid in billIds) {
          await _utilityBillService.deleteBill(bid);
        }
        if (!mounted) return;
        setState(() {
          _selectedRowIndices.clear();
          _clampTablePageIndex();
        });
        _scheduleTablePageJump();
        await _loadUtilityBills();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('선택한 $count개 항목을 삭제했어요.')),
        );
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadUtilityBills();
        }
      }
      return;
    }

    setState(() {
      final list = List<SharedExpenseTableItem>.from(_itemsForCurrentFilter());
      final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
      for (final i in sorted) {
        if (i >= 0 && i < list.length) list.removeAt(i);
      }
      if (_filterIndex == 0) {
        _goodsExpenseItems = list;
      } else {
        _utilityExpenseItems = list;
      }
      _selectedRowIndices.clear();
      _clampTablePageIndex();
    });
    _scheduleTablePageJump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 항목을 삭제했어요.')),
      );
    }
  }

  /// AI 영수증 인식 — 카메라/앨범 → 이미지 분석 API → 품목 편집·등록
  Future<void> _showAiReceiptRecognitionFlow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => _AiReceiptRecognitionFlowDialog(
        onPurchasesRegistered: () {
          if (_useGoodsPurchasesApi(context)) {
            _loadGoodsPurchases();
          }
        },
      ),
    );
  }

  /// 공용 구매 물품 정산 요청 — 정산 목록 GET + 인원(로컬 UI). 일괄 반영은 표 선택 모드
  Future<void> _showSharedExpenseSettlementFlow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => _SharedExpenseSettlementFlowDialog(
        initialRangeStart: _startDate,
        initialRangeEnd: _endDate,
        loadFromSettlementApi: _useGoodsPurchasesApi(context),
        onFinished: () {
          if (!mounted) return;
          if (_useGoodsPurchasesApi(context)) {
            _loadGoodsPurchases();
          }
        },
      ),
    );
  }

  /// 공과금 정산 — 기간·항목 선택(페이지) → 1인당 금액
  Future<void> _showUtilityBillSettlementFlow() async {
    final api = _useGoodsPurchasesApi(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => _UtilityBillSettlementFlowDialog(
        fallbackItems: List<SharedExpenseTableItem>.from(_utilityExpenseItems),
        fetchSettlementListViaApi: api,
        initialRangeStart: _startDate,
        initialRangeEnd: _endDate,
        onFinished: api
            ? () {
                if (!mounted) return;
                _loadUtilityBills();
              }
            : null,
      ),
    );
  }
}

class _SharedExpenseTableBody extends StatelessWidget {
  /// 표 데이터 행 — 동일 TextStyle; 날짜만 고정 크기, 금액·수량은 길면 FittedBox로 맞춤
  static const TextStyle _cellTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  final int filterIndex;
  final List<SharedExpenseTableItem> items;
  final void Function(SharedExpenseTableItem item, int globalIndex) onNameTap;
  final bool selectionMode;
  final int pageIndex;
  final int itemsPerPage;

  /// 한 페이지당 행 슬롯 높이 (`PageView` 높이 / `itemsPerPage`)
  final double rowSlotHeight;
  final Set<int> selectedIndices;
  final ValueChanged<int> onToggleRow;

  const _SharedExpenseTableBody({
    super.key,
    required this.filterIndex,
    required this.items,
    required this.onNameTap,
    required this.selectionMode,
    required this.pageIndex,
    required this.itemsPerPage,
    required this.rowSlotHeight,
    required this.selectedIndices,
    required this.onToggleRow,
  });

  @override
  Widget build(BuildContext context) {
    final isUtility = filterIndex == 1;

    if (items.isEmpty) {
      return Center(
        child: Text(
          '내역이 없습니다',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itemsPerPage; i++)
          SizedBox(
            height: rowSlotHeight,
            child: i < items.length
                ? Align(
                    alignment: Alignment.center,
                    child: _buildItemRow(
                      context,
                      isUtility,
                      items[i],
                      pageIndex * itemsPerPage + i,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  TextStyle _styleFor(SharedExpenseTableItem item) {
    if (!item.manuallySettled) return _cellTextStyle;
    return _cellTextStyle.copyWith(
      color: Colors.white.withOpacity(0.55),
    );
  }

  TextStyle _contentStyleFor(SharedExpenseTableItem item) {
    return _styleFor(item).copyWith(
      fontWeight: FontWeight.w700,
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    bool isUtility,
    SharedExpenseTableItem item,
    int globalIndex,
  ) {
    // 내용 열: 카테고리 제외 실제 품목명만 (분류는 상세 시트에서)
    final label = item.displayLabel;
    final rowStyle = _styleFor(item);
    final contentStyle = _contentStyleFor(item);

    // 헤더 셀과 동일한 가로 패딩·flex (_buildTableHeader와 맞출 것)
    const padContent = 4.0;
    const padDate = 3.0;
    const padAmount = 3.0;
    const padQty = 3.0;
    final contentFlex = isUtility ? 3 : 4;
    final dateFlex = isUtility ? 3 : 3;
    final lastColFlex = isUtility ? 3 : 2;

    /// 물품 품목명: 6자 초과 시 앞 6자 + … (공과금은 전체 표시용 FittedBox)
    final displayName =
        !isUtility && label.length > 6 ? '${label.substring(0, 6)}...' : label;

    /// 금액·수량 등 긴 문자열용 (날짜는 축소 없이 고정 글자 크기)
    Widget fittedCell(String text, TextStyle style) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      );
    }

    Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: selectionMode ? 1 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selectionMode) ...[
            Expanded(
              flex: 1,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Transform.scale(
                    scale: 0.82,
                    alignment: Alignment.center,
                    child: Checkbox(
                      value: selectedIndices.contains(globalIndex),
                      onChanged: (_) => onToggleRow(globalIndex),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.65),
                        width: 1.0,
                      ),
                      fillColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Colors.transparent;
                      }),
                      checkColor: const Color(0xFF2A2A2A),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
          ],
          Expanded(
            flex: contentFlex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padContent),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onNameTap(item, globalIndex),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: double.infinity,
                    child: isUtility
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: contentStyle,
                            ),
                          )
                        : Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: contentStyle,
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: dateFlex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padDate),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    item.date,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: rowStyle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padAmount),
              child: fittedCell(item.amount, rowStyle),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: lastColFlex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padQty),
              child: fittedCell(
                isUtility ? (item.quantity ?? '—') : (item.quantity ?? ''),
                rowStyle,
              ),
            ),
          ),
        ],
      ),
    );

    return row;
  }
}

List<SharedExpenseTableItem> _dummyItemsForSharedExpenseTable(int filterIndex) {
  final isUtility = filterIndex == 1;
  if (isUtility) {
    return [
      const SharedExpenseTableItem(
          name: 'TV 수신료', date: '매달 1일', amount: '2,500원', quantity: '자동이체'),
      const SharedExpenseTableItem(
          name: '주차비', date: '매달 5일', amount: '50,000원', quantity: '고정'),
      const SharedExpenseTableItem(
          name: '월세', date: '매달 6일', amount: '60만원', quantity: '고정'),
      const SharedExpenseTableItem(
          name: '인터넷', date: '매달 8일', amount: '33,000원', quantity: '자동이체'),
      const SharedExpenseTableItem(
          name: '수도세', date: '매달 10일', amount: '알 수 없음', quantity: '후불'),
      const SharedExpenseTableItem(
          name: '관리비', date: '매달 12일', amount: '15만원', quantity: '고정'),
      const SharedExpenseTableItem(
          name: '전기세', date: '매달 15일', amount: '45,000원', quantity: '자동이체'),
      const SharedExpenseTableItem(
          name: '공용 전기', date: '매달 18일', amount: '8,200원', quantity: '후불'),
      const SharedExpenseTableItem(
          name: '가스세', date: '매달 20일', amount: '30,000원', quantity: '자동이체'),
      const SharedExpenseTableItem(
          name: '건물 보험', date: '매달 25일', amount: '12,000원', quantity: '연납'),
    ];
  }
  return [
    const SharedExpenseTableItem(
        name: '콘푸라이트 500g',
        date: '25.05.04.',
        amount: '5,980원',
        quantity: '3개',
        manuallySettled: true),
    const SharedExpenseTableItem(
        name: '두루마리 휴지',
        date: '25.05.05.',
        amount: '8,000원',
        quantity: '3개',
        majorCategory: '욕실용품',
        minorCategory: '휴지',
        manuallySettled: false),
    const SharedExpenseTableItem(
        name: '10W 충전기', date: '25.05.14.', amount: '9,000원', quantity: '2개'),
    const SharedExpenseTableItem(
        name: '그래놀라 450g',
        date: '25.05.16.',
        amount: '12,000원',
        quantity: '3개'),
    const SharedExpenseTableItem(
        name: '인덕션용 냄비', date: '25.05.17.', amount: '20,000원', quantity: '1개'),
    const SharedExpenseTableItem(
        name: '커피 원두 1kg',
        date: '25.05.18.',
        amount: '18,500원',
        quantity: '2개'),
    const SharedExpenseTableItem(
        name: '주방 세제 세트', date: '25.05.19.', amount: '6,400원', quantity: '1개'),
    const SharedExpenseTableItem(
        name: '라면 5입 묶음', date: '25.05.20.', amount: '4,200원', quantity: '4개'),
    const SharedExpenseTableItem(
        name: '우유 900ml', date: '25.05.21.', amount: '3,100원', quantity: '5개'),
    const SharedExpenseTableItem(
        name: '계란 30구', date: '25.05.22.', amount: '7,800원', quantity: '2개'),
  ];
}

/// 한 페이지에 `pageSize`개씩 나눔. 빈 목록이면 빈 페이지 1장.
List<List<SharedExpenseTableItem>> _paginateSharedExpenseItems(
  List<SharedExpenseTableItem> items,
  int pageSize,
) {
  if (items.isEmpty) {
    return [[]];
  }
  final pages = <List<SharedExpenseTableItem>>[];
  for (var i = 0; i < items.length; i += pageSize) {
    final end = i + pageSize > items.length ? items.length : i + pageSize;
    pages.add(items.sublist(i, end));
  }
  return pages;
}

/// 추가/확인/정산 요청 등 공용소비 모달 공통 글래스 프레임 (예약하기·날짜 피커와 동일 톤)
class _SharedGlassDialogShell extends StatelessWidget {
  final Widget child;
  final BoxConstraints constraints;
  final EdgeInsetsGeometry? padding;

  const _SharedGlassDialogShell({
    required this.child,
    required this.constraints,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return PartitionGlassDialog.modal(
      constraints: constraints,
      padding: padding,
      child: child,
    );
  }
}

String _formatKrwSettlement(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

double _settlementMemberAmountFieldWidth({
  required String digits,
  required TextStyle style,
}) {
  final t = digits.isEmpty ? '0' : digits;
  final painter = TextPainter(
    text: TextSpan(text: t, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(minWidth: 0, maxWidth: double.infinity);
  // 컨테이너 좌우 패딩(4+4) + 필드 안쪽(2+2) + 커서 여유
  const extra = 14.0;
  return (painter.size.width + extra).clamp(24.0, 128.0);
}

/// 정산 멤버 행 오른쪽: 숫자만 입력, `원`은 필드 밖 고정, 폭은 글자에 맞춤
Widget _buildSettlementMemberAmountTrailing({
  required TextEditingController controller,
  required bool selected,
  required VoidCallback onAmountChanged,
}) {
  final amountStyle = TextStyle(
    color: selected ? Colors.white : Colors.white.withOpacity(0.45),
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFamily: 'Pretendard Variable',
    height: 1.05,
  );
  final hintStyle = TextStyle(
    color: Colors.white.withOpacity(0.35),
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFamily: 'Pretendard Variable',
    height: 1.05,
  );
  final w = _settlementMemberAmountFieldWidth(
    digits: controller.text,
    style: amountStyle,
  );

  return Expanded(
    child: Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: w,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(selected ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(selected ? 0.45 : 0.22),
                ),
              ),
              child: TextField(
                controller: controller,
                enabled: selected,
                onChanged: (_) => onAmountChanged(),
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: amountStyle,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  hintText: selected ? null : '0',
                  hintStyle: hintStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '원',
            style: TextStyle(
              color: selected
                  ? Colors.white.withOpacity(0.95)
                  : Colors.white.withOpacity(0.4),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettlementSelectableLine {
  final String name;
  final int amountWon;
  final int? purchaseId;
  final String? statusLabel;
  bool selected;

  _SettlementSelectableLine({
    required this.name,
    this.amountWon = 0,
    this.purchaseId,
    this.statusLabel,
    this.selected = true,
  });
}

/// 공용 구매 물품 정산 요청: 기간·항목(GET 정산 목록) → 인원 → 정산 요청(POST) 후 닫기 (공과금 정산과 동일)
class _SharedExpenseSettlementFlowDialog extends StatefulWidget {
  const _SharedExpenseSettlementFlowDialog({
    required this.initialRangeStart,
    required this.initialRangeEnd,
    required this.loadFromSettlementApi,
    this.onFinished,
  });

  final DateTime initialRangeStart;
  final DateTime initialRangeEnd;
  final bool loadFromSettlementApi;
  final VoidCallback? onFinished;

  @override
  State<_SharedExpenseSettlementFlowDialog> createState() =>
      _SharedExpenseSettlementFlowDialogState();
}

class _SharedExpenseSettlementFlowDialogState
    extends State<_SharedExpenseSettlementFlowDialog> {
  /// 0: 항목 선택, 1: 정산할 인원, 2: 정산 요청 완료
  int _step = 0;

  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  List<_SettlementSelectableLine> _lines = [];

  bool _loadingSettlement = false;
  String? _settlementLoadError;

  List<HouseholdMemberBrief> _members = [];
  List<bool> _memberSelected = [];
  final List<TextEditingController> _memberAmountCtrls = [];
  bool _loadingMembers = true;

  bool _submittingSettlementRequest = false;
  SupplySettlementRequestResult? _postedSettlementRequestResult;
  bool _confirmingSettlement = false;

  final AuthService _authService = AuthService();
  final SupplyService _supplyService = SupplyService();

  String _toIsoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _rangeStart = DateTime(
      widget.initialRangeStart.year,
      widget.initialRangeStart.month,
      widget.initialRangeStart.day,
    );
    _rangeEnd = DateTime(
      widget.initialRangeEnd.year,
      widget.initialRangeEnd.month,
      widget.initialRangeEnd.day,
    );
    if (widget.loadFromSettlementApi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSettlementPurchases();
      });
    }
    _loadMembers();
  }

  Future<void> _loadSettlementPurchases() async {
    if (!widget.loadFromSettlementApi || !mounted) return;
    setState(() {
      _loadingSettlement = true;
      _settlementLoadError = null;
    });
    try {
      final result = await _supplyService.fetchSettlementPurchases(
        startDate: _toIsoDate(_rangeStart),
        endDate: _toIsoDate(_rangeEnd),
      );
      if (!mounted) return;
      setState(() {
        _lines = result.purchases.map((e) {
          final row = e.toSharedExpenseTableItem();
          return _SettlementSelectableLine(
            name: row.displayLabel,
            amountWon: e.amount,
            purchaseId: e.purchaseId,
            statusLabel: e.status?.trim().isNotEmpty == true ? e.status : null,
            selected: true,
          );
        }).toList();
        _loadingSettlement = false;
        _settlementLoadError = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _lines = [];
          _loadingSettlement = false;
          _settlementLoadError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _lines = [];
          _loadingSettlement = false;
          _settlementLoadError = '정산 대상 목록을 불러오지 못했습니다.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _memberAmountCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureMemberAmountControllers() {
    while (_memberAmountCtrls.length < _members.length) {
      _memberAmountCtrls.add(TextEditingController());
    }
    while (_memberAmountCtrls.length > _members.length) {
      _memberAmountCtrls.removeLast().dispose();
    }
  }

  void _syncMemberAmountFields() {
    _ensureMemberAmountControllers();
    final per = _getGoodsPerPersonWon();
    for (var i = 0; i < _members.length; i++) {
      if (_memberSelected[i]) {
        _memberAmountCtrls[i].text = per > 0 ? '$per' : '0';
      } else {
        _memberAmountCtrls[i].text = '0';
      }
    }
  }

  Future<void> _loadMembers() async {
    final list = await _authService.fetchHouseholdMembers();
    if (!mounted) return;
    setState(() {
      _members = list;
      _memberSelected = List<bool>.filled(list.length, list.isNotEmpty);
      _loadingMembers = false;
      _ensureMemberAmountControllers();
      _syncMemberAmountFields();
    });
  }

  int _getSelectedGoodsTotalWon() {
    var sum = 0;
    for (final line in _lines) {
      if (line.selected) sum += line.amountWon;
    }
    return sum;
  }

  int _getSelectedMemberCount() {
    var n = 0;
    for (final s in _memberSelected) {
      if (s) n++;
    }
    return n;
  }

  int _getGoodsPerPersonWon() {
    final total = _getSelectedGoodsTotalWon();
    final n = _getSelectedMemberCount();
    if (n <= 0 || total <= 0) return 0;
    return (total / n).ceil();
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(today.year - 20, 1, 1);
    final maxDate = today.add(const Duration(days: 365));
    final selected = isStart ? _rangeStart : _rangeEnd;
    var initialDate = selected;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(maxDate)) initialDate = maxDate;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => GlassmorphicDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: maxDate,
        isStartDate: isStart,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isStart) {
          _rangeStart = d;
          if (_rangeEnd.isBefore(_rangeStart)) {
            _rangeEnd = _rangeStart;
          }
        } else {
          _rangeEnd = d;
          if (_rangeEnd.isBefore(_rangeStart)) {
            _rangeStart = _rangeEnd;
          }
        }
      });
      if (widget.loadFromSettlementApi) {
        _loadSettlementPurchases();
      }
    }
  }

  Widget _buildDateChip(String label, DateTime date, bool isStart) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _pickDate(isStart),
        child: FrostedPanel(
          borderRadius: BorderRadius.circular(20),
          backgroundOpacity: 0.08,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatDate(date),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(_SettlementSelectableLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => line.selected = !line.selected),
        behavior: HitTestBehavior.opaque,
        child: FrostedPanel(
          borderRadius: BorderRadius.circular(22),
          backgroundOpacity: 0.08,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                line.selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: line.selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.45),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                    if (line.amountWon > 0 ||
                        (line.statusLabel != null &&
                            line.statusLabel!.isNotEmpty)) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (line.amountWon > 0)
                            '${_formatKrwSettlement(line.amountWon)}원',
                          if (line.statusLabel != null &&
                              line.statusLabel!.isNotEmpty)
                            line.statusLabel!,
                        ].join(' · '),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepSelect(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '공용 구매 물품 정산 요청',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '어떤 소비 물품을 정산하실 건가요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildDateChip('시작일', _rangeStart, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '~',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _buildDateChip('종료일', _rangeEnd, false),
              ],
            ),
            const SizedBox(height: 18),
            if (widget.loadFromSettlementApi && _loadingSettlement)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ),
              )
            else if (widget.loadFromSettlementApi &&
                _settlementLoadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _settlementLoadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _loadingSettlement
                            ? null
                            : () => _loadSettlementPurchases(),
                        child: const Text(
                          '다시 시도',
                          style: TextStyle(
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  widget.loadFromSettlementApi
                      ? '이 기간에 정산할 물품이 없어요.\n기간을 바꿔 보세요.'
                      : '로그인 후 이 기간의 미정산 구매 내역을 불러올 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard Variable',
                    height: 1.4,
                  ),
                ),
              )
            else
              ..._lines.map(_buildItemRow),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: 0.35,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 8,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                const SizedBox(width: 14),
                Opacity(
                  opacity: 0.35,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: '다음',
              enabled: !widget.loadFromSettlementApi ||
                  (!_loadingSettlement && _settlementLoadError == null),
              onPressed: () {
                if (_lines.isEmpty || !_lines.any((e) => e.selected)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('정산할 물품을 하나 이상 선택해주세요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (widget.loadFromSettlementApi &&
                    !_loadingMembers &&
                    _members.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '하우스 멤버를 불러오지 못했어요. 네트워크·로그인 상태를 확인해 주세요.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                setState(() {
                  _step = 1;
                  _syncMemberAmountFields();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow(BuildContext context, int index) {
    final name = _members[index].name;
    final sel = _memberSelected[index];
    final maxNameW = (MediaQuery.sizeOf(context).width - 32) * 0.38;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostedPanel(
        borderRadius: BorderRadius.circular(22),
        backgroundOpacity: 0.08,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _memberSelected[index] = !sel;
                _syncMemberAmountFields();
              }),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: sel ? Colors.white : Colors.white.withOpacity(0.45),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxNameW),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildSettlementMemberAmountTrailing(
              controller: _memberAmountCtrls[index],
              selected: sel,
              onAmountChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepMembers(BuildContext context) {
    final total = _getSelectedGoodsTotalWon();
    final n = _getSelectedMemberCount();
    final per = _getGoodsPerPersonWon();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _submittingSettlementRequest
                      ? null
                      : () => setState(() => _step = 0),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                const Expanded(
                  child: Text(
                    '정산할 인원 선택',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.2,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: _submittingSettlementRequest
                      ? null
                      : () => Navigator.of(context).pop(),
                  iconSize: 22,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '같은 그룹 멤버 중 정산에 참여할 인원을 선택하세요.\n'
              '(선택한 인원으로 N분의 1)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 16),
            if (_loadingMembers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            else if (widget.loadFromSettlementApi && _members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '하우스 멤버를 불러오지 못했어요.\n로그인·네트워크를 확인해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard Variable',
                    height: 1.4,
                  ),
                ),
              )
            else ...[
              Text(
                '선택 물품 합계: ${_formatKrwSettlement(total)}원 · 1인당: ${_formatKrwSettlement(per)}원 (${n > 0 ? n : '-'}명)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard Variable',
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              ...List.generate(
                _members.length,
                (i) => _buildMemberRow(context, i),
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: _submittingSettlementRequest ? '요청 중...' : '정산 요청',
              enabled: !_submittingSettlementRequest && !_loadingMembers,
              onPressed: () async {
                if (_loadingMembers || _submittingSettlementRequest) return;
                if (_getSelectedMemberCount() == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('정산에 참여할 인원을 한 명 이상 선택해주세요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                if (!widget.loadFromSettlementApi) {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산 요청 알림을 보냈어요. (데모 모드)'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                if (_members.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '하우스 멤버 정보가 없어 정산 요청을 보낼 수 없어요.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final purchaseIds = <int>[];
                for (final line in _lines) {
                  if (!line.selected) continue;
                  final id = line.purchaseId;
                  if (id == null || id <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '선택한 줄 중 서버에 등록되지 않은 구매가 있어요.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  purchaseIds.add(id);
                }

                final memberIds = <int>[];
                for (var i = 0; i < _members.length; i++) {
                  if (_memberSelected[i]) {
                    memberIds.add(_members[i].userId);
                  }
                }

                final messenger = ScaffoldMessenger.of(context);
                setState(() => _submittingSettlementRequest = true);
                try {
                  final result = await _supplyService.requestSettlement(
                    purchaseIds: purchaseIds,
                    memberIds: memberIds,
                  );
                  if (!context.mounted) return;
                  if (result.settlementId <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          '정산 요청은 되었지만 번호를 확인하지 못했어요. 목록을 새로고침해 주세요.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  widget.onFinished?.call();
                  setState(() {
                    _postedSettlementRequestResult = result;
                    _step = 2;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        '정산 요청을 보냈어요. 그룹원에게 알림이 전달됩니다.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3),
                    ),
                  );
                } on ApiException catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _submittingSettlementRequest = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepAfterRequest(BuildContext context) {
    final r = _postedSettlementRequestResult;
    if (r == null) {
      return const SizedBox.shrink();
    }
    final messenger = ScaffoldMessenger.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '정산 요청 완료',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
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
              '내용을 확인한 뒤 정산 완료 처리를 눌러 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '총액 ${_formatKrwSettlement(r.totalAmount)}원 · 1인 ${_formatKrwSettlement(r.amountPerMember)}원 · '
              '${r.memberCount}명',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            ...r.items.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FrostedPanel(
                  borderRadius: BorderRadius.circular(18),
                  backgroundOpacity: 0.08,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    '${e.itemName} · ${_formatKrwSettlement(e.amount)}원',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _confirmingSettlement ? '처리 중...' : '정산 완료 처리',
              enabled: !_confirmingSettlement,
              onPressed: () async {
                if (_confirmingSettlement) return;
                setState(() => _confirmingSettlement = true);
                try {
                  await _supplyService.confirmSettlement(r.settlementId);
                  if (!context.mounted) return;
                  widget.onFinished?.call();
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산을 완료했습니다.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } on ApiException catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산 완료 처리에 실패했습니다.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _confirmingSettlement = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final sh = MediaQuery.sizeOf(context).height;

    return _SharedGlassDialogShell(
      constraints: BoxConstraints(
        maxWidth: sw - 32,
        maxHeight: sh * 0.72,
      ),
      child: _step == 0
          ? _buildStepSelect(context)
          : _step == 1
              ? _buildStepMembers(context)
              : _buildStepAfterRequest(context),
    );
  }
}

class _UtilitySelectableLine {
  final SharedExpenseTableItem item;
  bool selected;

  _UtilitySelectableLine({required this.item}) : selected = true;
}

/// 공과금 정산: 기간·항목 선택 → 정산할 인원 선택
/// API 모드: `GET /api/bills/settlement/list` 로 UNSETTLED 후보 조회
class _UtilityBillSettlementFlowDialog extends StatefulWidget {
  final List<SharedExpenseTableItem> fallbackItems;
  final bool fetchSettlementListViaApi;
  final DateTime? initialRangeStart;
  final DateTime? initialRangeEnd;

  /// POST 정산 요청 성공 후 부모가 목록을 다시 불러올 때
  final VoidCallback? onFinished;

  const _UtilityBillSettlementFlowDialog({
    required this.fallbackItems,
    this.fetchSettlementListViaApi = false,
    this.initialRangeStart,
    this.initialRangeEnd,
    this.onFinished,
  });

  @override
  State<_UtilityBillSettlementFlowDialog> createState() =>
      _UtilityBillSettlementFlowDialogState();
}

class _UtilityBillSettlementFlowDialogState
    extends State<_UtilityBillSettlementFlowDialog> {
  int _step = 0;

  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  List<_UtilitySelectableLine> _lines = [];

  late int _perPersonWon;
  int? _lastServerAmountPerMember;

  bool _settlementListLoading = false;
  String? _settlementLoadError;

  List<String> _memberNames = [];
  List<bool> _memberSelected = [];
  final List<TextEditingController> _memberAmountCtrls = [];
  bool _loadingMembers = true;
  List<HouseholdMemberBrief> _memberBriefs = [];
  bool _submittingBillSettlement = false;
  BillSettlementRequestResult? _postedRequestResult;
  bool _confirmingBillSettlement = false;

  final AuthService _authService = AuthService();
  final UtilityBillService _utilityBillService = UtilityBillService();

  static String _dateToIsoYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (widget.initialRangeStart != null && widget.initialRangeEnd != null) {
      _rangeStart = widget.initialRangeStart!;
      _rangeEnd = widget.initialRangeEnd!;
    } else if (widget.fetchSettlementListViaApi) {
      _rangeStart = today.subtract(const Duration(days: 30));
      _rangeEnd = today;
    } else {
      _rangeStart = DateTime(2025, 8, 15);
      _rangeEnd = DateTime(2025, 8, 15);
    }
    if (!widget.fetchSettlementListViaApi) {
      _lines = widget.fallbackItems
          .map((e) => _UtilitySelectableLine(item: e))
          .toList();
    }
    _perPersonWon = 8000;
    _loadMembers();
    if (widget.fetchSettlementListViaApi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadSettlementLines();
      });
    }
  }

  Future<void> _reloadSettlementLines() async {
    if (!widget.fetchSettlementListViaApi) return;
    setState(() {
      _settlementListLoading = true;
      _settlementLoadError = null;
    });
    try {
      final summary = await _utilityBillService.fetchSettlementList(
        startDate: _dateToIsoYmd(_rangeStart),
        endDate: _dateToIsoYmd(_rangeEnd),
      );
      if (!mounted) return;
      setState(() {
        _lines = summary.bills
            .map(
              (b) => _UtilitySelectableLine(item: b.toSharedExpenseTableItem()),
            )
            .toList();
        _lastServerAmountPerMember =
            summary.amountPerMember > 0 ? summary.amountPerMember : null;
        _settlementListLoading = false;
        _recalculatePerPerson();
        _ensureMemberAmountControllers();
        _syncMemberAmountFields();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _settlementListLoading = false;
        _settlementLoadError = e.message;
        _lines = [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settlementListLoading = false;
        _settlementLoadError = '정산 대상 목록을 불러오지 못했습니다.';
        _lines = [];
      });
    }
  }

  @override
  void dispose() {
    for (final c in _memberAmountCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureMemberAmountControllers() {
    while (_memberAmountCtrls.length < _memberNames.length) {
      _memberAmountCtrls.add(TextEditingController());
    }
    while (_memberAmountCtrls.length > _memberNames.length) {
      _memberAmountCtrls.removeLast().dispose();
    }
  }

  void _syncMemberAmountFields() {
    _ensureMemberAmountControllers();
    for (var i = 0; i < _memberNames.length; i++) {
      if (_memberSelected[i]) {
        _memberAmountCtrls[i].text = _perPersonWon > 0 ? '$_perPersonWon' : '0';
      } else {
        _memberAmountCtrls[i].text = '0';
      }
    }
  }

  Future<void> _loadMembers() async {
    if (widget.fetchSettlementListViaApi) {
      final briefs = await _authService.fetchHouseholdMembers();
      if (!mounted) return;
      setState(() {
        _memberBriefs = briefs;
        _memberNames = briefs.map((e) => e.name).toList();
        _memberSelected =
            List<bool>.filled(_memberNames.length, _memberNames.isNotEmpty);
        _loadingMembers = false;
        _recalculatePerPerson();
        _ensureMemberAmountControllers();
        _syncMemberAmountFields();
      });
    } else {
      final names = await _authService.fetchHouseholdMemberNames();
      if (!mounted) return;
      setState(() {
        _memberBriefs = [];
        _memberNames = names;
        _memberSelected = List<bool>.filled(names.length, names.isNotEmpty);
        _loadingMembers = false;
        _recalculatePerPerson();
        _ensureMemberAmountControllers();
        _syncMemberAmountFields();
      });
    }
  }

  int _getSelectedMemberCount() {
    var n = 0;
    for (final s in _memberSelected) {
      if (s) n++;
    }
    return n;
  }

  int _getSelectedUtilitySumWon() {
    var sum = 0;
    for (final line in _lines) {
      if (!line.selected) continue;
      final w = _parseAmountToWon(line.item.amount);
      if (w != null) sum += w;
    }
    return sum;
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
  }

  int? _parseAmountToWon(String amount) {
    final t = amount.trim();
    if (t.isEmpty ||
        t.contains('알 수 없음') ||
        t.contains('미입력')) {
      return null;
    }
    final man = RegExp(r'(\d+)\s*만').firstMatch(t);
    if (man != null) {
      final v = int.tryParse(man.group(1)!);
      return v != null ? v * 10000 : null;
    }
    final digitsOnly = t.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return null;
    return int.tryParse(digitsOnly);
  }

  String _formatKrw(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _recalculatePerPerson() {
    var sum = 0;
    var any = false;
    for (final line in _lines) {
      if (!line.selected) continue;
      final w = _parseAmountToWon(line.item.amount);
      if (w != null) {
        sum += w;
        any = true;
      }
    }
    final n = _getSelectedMemberCount();
    if (n <= 0) {
      _perPersonWon = (_lastServerAmountPerMember != null &&
              _lastServerAmountPerMember! > 0)
          ? _lastServerAmountPerMember!
          : 8000;
      return;
    }
    if (!any || sum <= 0) {
      _perPersonWon = (_lastServerAmountPerMember != null &&
              _lastServerAmountPerMember! > 0)
          ? _lastServerAmountPerMember!
          : 8000;
      return;
    }
    _perPersonWon = (sum / n).ceil();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(today.year - 20, 1, 1);
    final maxDate = today.add(const Duration(days: 365));
    final selected = isStart ? _rangeStart : _rangeEnd;
    var initialDate = selected;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(maxDate)) initialDate = maxDate;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => GlassmorphicDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: maxDate,
        isStartDate: isStart,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isStart) {
          _rangeStart = d;
          if (_rangeEnd.isBefore(_rangeStart)) {
            _rangeEnd = _rangeStart;
          }
        } else {
          _rangeEnd = d;
          if (_rangeEnd.isBefore(_rangeStart)) {
            _rangeStart = _rangeEnd;
          }
        }
      });
      if (mounted && widget.fetchSettlementListViaApi) {
        _reloadSettlementLines();
      }
    }
  }

  Widget _buildDateChip(String label, DateTime date, bool isStart) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _pickDate(isStart),
        child: FrostedPanel(
          borderRadius: BorderRadius.circular(20),
          backgroundOpacity: 0.08,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatDate(date),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(_UtilitySelectableLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => line.selected = !line.selected),
        behavior: HitTestBehavior.opaque,
        child: FrostedPanel(
          borderRadius: BorderRadius.circular(22),
          backgroundOpacity: 0.08,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                line.selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: line.selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.45),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  line.item.displayLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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

  Widget _buildStepSelect(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Text(
                      '공과금 정산',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '어떤 공과금을 정산하실 건가요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildDateChip('시작일', _rangeStart, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '~',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _buildDateChip('종료일', _rangeEnd, false),
              ],
            ),
            const SizedBox(height: 18),
            if (_settlementListLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                ),
              )
            else if (_settlementLoadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _settlementLoadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              )
            else if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  widget.fetchSettlementListViaApi
                      ? '해당 기간에 정산할 공과금이 없어요.'
                      : '표에 공과금 내역을 먼저 추가해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              )
            else
              ..._lines.map(_buildItemRow),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: 0.35,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 8,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                const SizedBox(width: 14),
                Opacity(
                  opacity: 0.35,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: '다음',
              onPressed: () {
                if (_settlementListLoading) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('목록을 불러오는 중이에요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_settlementLoadError != null &&
                    widget.fetchSettlementListViaApi) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_settlementLoadError!),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_lines.isEmpty || !_lines.any((e) => e.selected)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _lines.isEmpty
                            ? '정산할 공과금 내역이 없습니다.'
                            : '정산할 공과금을 하나 이상 선택해주세요.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                setState(() {
                  _recalculatePerPerson();
                  _step = 1;
                  _syncMemberAmountFields();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilityMemberRow(BuildContext context, int index) {
    final name = _memberNames[index];
    final sel = _memberSelected[index];
    final maxNameW = (MediaQuery.sizeOf(context).width - 32) * 0.38;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostedPanel(
        borderRadius: BorderRadius.circular(22),
        backgroundOpacity: 0.08,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _memberSelected[index] = !sel;
                _recalculatePerPerson();
                _syncMemberAmountFields();
              }),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: sel ? Colors.white : Colors.white.withOpacity(0.45),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxNameW),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildSettlementMemberAmountTrailing(
              controller: _memberAmountCtrls[index],
              selected: sel,
              onAmountChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepMembers(BuildContext context) {
    final total = _getSelectedUtilitySumWon();
    final n = _getSelectedMemberCount();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(() => _step = 0),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                const Expanded(
                  child: Text(
                    '정산할 인원 선택',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.2,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                  iconSize: 22,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '같은 그룹 멤버 중 정산에 참여할 인원을 선택하세요.\n'
              '(선택한 인원으로 N분의 1)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 16),
            if (_loadingMembers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            else ...[
              Text(
                '선택 항목 합계: ${_formatKrw(total)}원 · 1인당: ${_formatKrw(_perPersonWon)}원 (${n > 0 ? n : '-'}명)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard Variable',
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              ...List.generate(
                _memberNames.length,
                (i) => _buildUtilityMemberRow(context, i),
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: _submittingBillSettlement ? '요청 중...' : '정산 요청',
              enabled: !_submittingBillSettlement && !_loadingMembers,
              onPressed: () async {
                if (_loadingMembers || _submittingBillSettlement) return;
                if (_getSelectedMemberCount() == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('정산에 참여할 인원을 한 명 이상 선택해주세요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                _recalculatePerPerson();
                final messenger = ScaffoldMessenger.of(context);

                if (!widget.fetchSettlementListViaApi) {
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산 요청 알림을 보냈어요.'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                if (_memberBriefs.length != _memberNames.length ||
                    _memberBriefs.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        '하우스 멤버 정보가 없어 정산 요청을 보낼 수 없어요.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final paymentIds = <int>[];
                for (final line in _lines) {
                  if (!line.selected) continue;
                  final pid = line.item.paymentId;
                  if (pid == null || pid <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          '선택한 항목에 납부 기록 ID가 없어요. 정산 대상 목록을 다시 불러온 뒤 선택해 주세요.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  paymentIds.add(pid);
                }

                final memberIds = <int>[];
                for (var i = 0; i < _memberBriefs.length; i++) {
                  if (i < _memberSelected.length && _memberSelected[i]) {
                    memberIds.add(_memberBriefs[i].userId);
                  }
                }
                if (memberIds.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산 대상 멤버를 선택해주세요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                setState(() => _submittingBillSettlement = true);
                try {
                  final result =
                      await _utilityBillService.requestBillSettlement(
                    paymentIds: paymentIds,
                    memberIds: memberIds,
                  );
                  if (!context.mounted) return;
                  if (result.settlementId <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          '정산 요청은 되었지만 번호를 확인하지 못했어요. 목록을 새로고침해 주세요.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  widget.onFinished?.call();
                  setState(() {
                    _postedRequestResult = result;
                    _step = 2;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        '정산 요청을 보냈어요. 그룹원에게 알림이 전달됩니다.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3),
                    ),
                  );
                } on ApiException catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _submittingBillSettlement = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepAfterRequest(BuildContext context) {
    final r = _postedRequestResult;
    if (r == null) {
      return const SizedBox.shrink();
    }
    final messenger = ScaffoldMessenger.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '정산 요청 완료',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
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
              '내용을 확인한 뒤 정산 완료를 눌러 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard Variable',
                height: 1.22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '총액 ${_formatKrw(r.totalAmount)}원 · 1인 ${_formatKrw(r.amountPerMember)}원 · '
              '${r.memberCount}명',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            ...r.items.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FrostedPanel(
                  borderRadius: BorderRadius.circular(18),
                  backgroundOpacity: 0.08,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    '${e.utilityTypeName} · ${_formatKrw(e.amount)}원',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _confirmingBillSettlement ? '처리 중...' : '정산 완료 처리',
              enabled: !_confirmingBillSettlement,
              onPressed: () async {
                if (_confirmingBillSettlement) return;
                setState(() => _confirmingBillSettlement = true);
                try {
                  await _utilityBillService.confirmBillSettlement(
                    r.settlementId,
                  );
                  if (!context.mounted) return;
                  context.read<AlarmNavigationController>().registerBillSettlementConfirmedForAlarmUi(
                        r.settlementId,
                      );
                  widget.onFinished?.call();
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산을 완료했습니다.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } on ApiException catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('정산 완료에 실패했습니다.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _confirmingBillSettlement = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final sh = MediaQuery.sizeOf(context).height;

    return _SharedGlassDialogShell(
      constraints: BoxConstraints(
        maxWidth: sw - 32,
        maxHeight: sh * 0.72,
      ),
      child: _step == 0
          ? _buildStepSelect(context)
          : _step == 1
              ? _buildStepMembers(context)
              : _buildStepAfterRequest(context),
    );
  }
}

class _ExtractedReceiptLine {
  String name;
  DateTime date;
  int amountWon;
  int qty;
  bool selected;

  /// API가 준 category / subCategory 코드 (null이면 등록 시 기본값 사용)
  String? categoryCode;
  String? subCategoryCode;

  _ExtractedReceiptLine({
    required this.name,
    required this.date,
    required this.amountWon,
    required this.qty,
    this.selected = true,
    this.categoryCode,
    this.subCategoryCode,
  });
}

/// AI 영수증: 카메라/앨범 → 분석 API → 추출·수정 → 선택 등록
class _AiReceiptRecognitionFlowDialog extends StatefulWidget {
  const _AiReceiptRecognitionFlowDialog({this.onPurchasesRegistered});

  final void Function()? onPurchasesRegistered;

  @override
  State<_AiReceiptRecognitionFlowDialog> createState() =>
      _AiReceiptRecognitionFlowDialogState();
}

class _AiReceiptRecognitionFlowDialogState
    extends State<_AiReceiptRecognitionFlowDialog> {
  /// 서버(nginx) 업로드 한도(413)에 걸리지 않도록 가장자리·품질 제한
  static const double _kReceiptImageMaxEdge = 1600;
  static const int _kReceiptImageQuality = 72;

  /// 0: 촬영 안내, 1: 분석 확인, 2: 추출 내용
  int _step = 0;

  final ImagePicker _imagePicker = ImagePicker();
  final SupplyService _supplyService = SupplyService();

  /// 촬영·앨범에서 선택한 영수증
  XFile? _capturedReceipt;

  List<_ExtractedReceiptLine> _lines = [];
  bool _analyzing = false;
  bool _registering = false;

  /// 다이얼로그 닫기: 포커스 해제 후 다음 프레임에 pop 해 라이프사이클·의존성 assert 방지
  void _closeReceiptFlowDialog() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
    });
  }

  void _disposeEditControllerNextFrame(TextEditingController c) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.dispose();
    });
  }

  @override
  void initState() {
    super.initState();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<_ExtractedReceiptLine> _linesFromApiItems(
    List<ReceiptRecognizedItem> items,
  ) {
    final now = _dateOnly(DateTime.now());
    return items.map((e) {
      var dt = e.purchaseDate != null && e.purchaseDate!.trim().isNotEmpty
          ? DateTime.tryParse(e.purchaseDate!.trim())
          : null;
      if (dt != null) {
        dt = _dateOnly(dt);
      } else {
        dt = now;
      }
      final name = e.itemName.trim();
      var amount = e.amount;
      if (amount == null || amount < 1) {
        amount = 1;
      }
      var qty = e.quantity;
      if (qty == null || qty < 1) {
        qty = 1;
      }
      return _ExtractedReceiptLine(
        name: name.isEmpty ? '(이름 없음)' : name,
        date: dt,
        amountWon: amount,
        qty: qty,
        selected: true,
        categoryCode: e.category,
        subCategoryCode: e.subCategory,
      );
    }).toList();
  }

  Future<void> _analyzeAndGoToExtract() async {
    final file = _capturedReceipt;
    if (file == null || !mounted) return;
    setState(() => _analyzing = true);
    try {
      final result = await _supplyService.analyzeReceiptImage(file);
      if (!mounted) return;
      if (result.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('인식된 품목이 없어요. 다른 이미지로 시도해 주세요.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _lines = _linesFromApiItems(result.items);
        _step = 2;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('분석에 실패했어요. ($e)'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  Future<void> _openGallery() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _kReceiptImageMaxEdge,
        maxHeight: _kReceiptImageMaxEdge,
        imageQuality: _kReceiptImageQuality,
      );
      if (!mounted) return;
      if (file == null) return;
      setState(() {
        _capturedReceipt = file;
        _step = 1;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final denied =
          e.code == 'photo_access_denied' || e.code == 'camera_access_denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? '사진 보관함 접근이 거부되었어요. 설정에서 허용해 주세요.'
                : '사진을 열 수 없습니다. (${e.message ?? e.code})',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사진을 선택할 수 없습니다. ($e)'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _registerSelectedLines() async {
    final selected = _lines.where((e) => e.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('선택된 항목이 없어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    for (final line in selected) {
      if (line.amountWon < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('금액이 0인 품목이 있어요. 금액을 수정한 뒤 다시 시도해 주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final useApi = !usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    if (!useApi) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).maybePop();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              '${selected.length}건 (더미/미로그인: 서버 등록은 로그인 후 가능해요)',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
      return;
    }

    final defMaj = kDefaultSupplyCategoryGroups.first.category;
    final defMin =
        kDefaultSupplyCategoryGroups.first.subCategories.first.subCategory;

    setState(() => _registering = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      for (final line in selected) {
        final cat = (line.categoryCode != null && line.categoryCode!.isNotEmpty)
            ? line.categoryCode!
            : defMaj;
        final sub =
            (line.subCategoryCode != null && line.subCategoryCode!.isNotEmpty)
                ? line.subCategoryCode!
                : defMin;
        final isoDate =
            '${line.date.year}-${line.date.month.toString().padLeft(2, '0')}-'
            '${line.date.day.toString().padLeft(2, '0')}';
        await _supplyService.createPurchase(
          itemName: line.name,
          purchaseDate: isoDate,
          amount: line.amountWon,
          quantity: line.qty,
          category: cat,
          subCategory: sub,
        );
      }
      widget.onPurchasesRegistered?.call();
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      final n = selected.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).maybePop();
        messenger?.showSnackBar(
          SnackBar(
            content: Text('$n건을 등록했어요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('등록에 실패했어요. ($e)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _registering = false);
      }
    }
  }

  /// 앱 내 동의 후 시스템 카메라 실행. iOS/Android는 OS가 권한·허용 범위를 처리합니다.
  Future<void> _openCameraAfterConsent() async {
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '카메라 촬영 동의',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFamily: 'Pretendard Variable',
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              '영수증 인식을 위해 카메라로 촬영합니다.\n'
              '촬영 전 Partition 앱에서 동의가 필요하며, 이후 기기에서 카메라 접근 허용 여부를 선택할 수 있습니다.\n\n'
              '(iOS 등에서는 시스템이 「허용 안 함」「허용」 등의 선택 화면을 보여 줍니다.)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 14,
                height: 1.4,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                '동의하지 않음',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '동의하고 촬영',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            ),
          ],
        );
      },
    );

    if (agreed != true || !mounted) return;

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: _kReceiptImageMaxEdge,
        maxHeight: _kReceiptImageMaxEdge,
        imageQuality: _kReceiptImageQuality,
      );
      if (!mounted) return;
      if (file == null) return;
      setState(() {
        _capturedReceipt = file;
        _step = 1;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'camera_access_denied'
                ? '카메라 접근이 거부되었어요. 설정에서 허용해 주세요.'
                : '카메라를 열 수 없습니다. (${e.message ?? e.code})',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('카메라를 열 수 없습니다. ($e)'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final sh = MediaQuery.sizeOf(context).height;
    // 추출 단계는 이전 대비 높이 절반 — 목록은 ListView로 스크롤
    final maxH = _step == 2 ? sh * 0.37 : sh * 0.52;

    if (_step == 2) {
      return _SharedGlassDialogShell(
        constraints: BoxConstraints(maxWidth: sw - 32, maxHeight: maxH),
        child: SizedBox(
          height: maxH,
          child: _buildStepExtract(context),
        ),
      );
    }

    return _SharedGlassDialogShell(
      constraints: BoxConstraints(maxWidth: sw - 32, maxHeight: maxH),
      child:
          _step == 0 ? _buildStepCapture(context) : _buildStepAnalyze(context),
    );
  }

  Widget _buildStepCapture(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 40),
              const Expanded(
                child: Text(
                  'AI 영수증 인식',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              ),
              PartitionModalCloseButton(
                onPressed: _closeReceiptFlowDialog,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            kIsWeb
                ? '브라우저에서 영수증 이미지를 선택해 구매 내역을 등록하시겠어요?'
                : '영수증을 촬영해 구매 내역을 등록하시겠어요?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFamily: 'Pretendard Variable',
              height: 1.22,
            ),
          ),
          const SizedBox(height: 20),
          if (kIsWeb)
            PrimaryButton(
              label: '이미지에서 선택',
              onPressed: _openGallery,
            )
          else ...[
            PrimaryButton(
              label: '촬영하기',
              onPressed: _openCameraAfterConsent,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _openGallery,
              child: Text(
                '앨범에서 선택',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepAnalyze(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '분석하시겠습니까?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'Pretendard Variable',
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _capturedReceipt != null
                ? '선택한 영수증 이미지 품목을 추출합니다.'
                : '영수증 이미지 품목을 추출합니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontFamily: 'Pretendard Variable',
              height: 1.35,
            ),
          ),
          if (_analyzing) ...[
            const SizedBox(height: 28),
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '이미지를 분석하는 중…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 28),
          ],
          if (!_analyzing) const SizedBox(height: 28),
          PrimaryButton(
            label: '분석하기',
            enabled: !_analyzing,
            onPressed: _analyzeAndGoToExtract,
          ),
          if (!_analyzing) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _closeReceiptFlowDialog,
                child: Text(
                  '취소',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatExtractReceiptDate(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}.';
  }

  Future<void> _editExtractLineName(int index) async {
    final line = _lines[index];
    final controller = TextEditingController(text: line.name);
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text(
          '품목명',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Pretendard Variable',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: 'Pretendard Variable',
          ),
          decoration: InputDecoration(
            hintText: '텍스트로 입력',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: Colors.white.withOpacity(0.75)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '확인',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    _disposeEditControllerNextFrame(controller);
    if (!mounted) return;
    if (ok == true && text.isNotEmpty) {
      setState(() => line.name = text);
    }
  }

  Future<void> _editExtractLineDate(int index) async {
    final line = _lines[index];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(2018, 1, 1);
    final last = today.add(const Duration(days: 365 * 3));

    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => _ReceiptExtractDatePickerDialog(
        initialDate: line.date.isBefore(first)
            ? first
            : (line.date.isAfter(last) ? last : line.date),
        firstDate: first,
        lastDate: last,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        line.date = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _editExtractLineAmountWon(int index) async {
    final line = _lines[index];
    final controller = TextEditingController(text: line.amountWon.toString());
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text(
          '금액 (원)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Pretendard Variable',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: 'Pretendard Variable',
          ),
          decoration: InputDecoration(
            hintText: '정수만 입력 (원)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            suffixText: '원',
            suffixStyle: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontFamily: 'Pretendard Variable',
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: Colors.white.withOpacity(0.75)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '확인',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ],
      ),
    );
    final raw = controller.text.trim();
    _disposeEditControllerNextFrame(controller);
    if (!mounted || ok != true) return;
    final v = int.tryParse(raw);
    if (v == null) return;
    setState(() => line.amountWon = v.clamp(0, 999999999));
  }

  Future<void> _editExtractLineQty(int index) async {
    final line = _lines[index];
    final controller = TextEditingController(text: line.qty.toString());
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text(
          '수량',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Pretendard Variable',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: 'Pretendard Variable',
          ),
          decoration: InputDecoration(
            hintText: '정수만 입력 (개)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            suffixText: '개',
            suffixStyle: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontFamily: 'Pretendard Variable',
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: Colors.white.withOpacity(0.75)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '확인',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ],
      ),
    );
    final raw = controller.text.trim();
    _disposeEditControllerNextFrame(controller);
    if (!mounted || ok != true) return;
    final v = int.tryParse(raw);
    if (v == null || v < 1) return;
    setState(() => line.qty = v.clamp(1, 99999));
  }

  Widget _buildEditableExtractPill({
    required String text,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: FrostedPanel(
            borderRadius: BorderRadius.circular(14),
            backgroundOpacity: 0.06,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Center(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepExtract(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      '추출 내용',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '내용을 클릭해 수정할 수 있고, 원하는 리스트만 선택하여 등록할 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              PartitionModalCloseButton(
                onPressed: _closeReceiptFlowDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            itemCount: _lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final line = _lines[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => line.selected = !line.selected),
                    child: Icon(
                      line.selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: line.selected
                          ? Colors.white
                          : Colors.white.withOpacity(0.45),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        _buildEditableExtractPill(
                          text: line.name,
                          onTap: () => _editExtractLineName(index),
                        ),
                        const SizedBox(width: 6),
                        _buildEditableExtractPill(
                          text: _formatExtractReceiptDate(line.date),
                          onTap: () => _editExtractLineDate(index),
                        ),
                        const SizedBox(width: 6),
                        _buildEditableExtractPill(
                          text: '${line.amountWon}원',
                          onTap: () => _editExtractLineAmountWon(index),
                        ),
                        const SizedBox(width: 6),
                        _buildEditableExtractPill(
                          text: '${line.qty}개',
                          onTap: () => _editExtractLineQty(index),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: '선택한 내용 등록하기',
                enabled: !_registering,
                onPressed: _registerSelectedLines,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _closeReceiptFlowDialog,
                  child: Text(
                    '영수증 분석 내용 취소',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptExtractDatePickerDialog extends StatefulWidget {
  const _ReceiptExtractDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_ReceiptExtractDatePickerDialog> createState() =>
      _ReceiptExtractDatePickerDialogState();
}

class _ReceiptExtractDatePickerDialogState
    extends State<_ReceiptExtractDatePickerDialog> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _clampDate(widget.initialDate);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _clampDate(DateTime date) {
    final first = _dateOnly(widget.firstDate);
    final last = _dateOnly(widget.lastDate);
    final target = _dateOnly(date);
    if (target.isBefore(first)) return first;
    if (target.isAfter(last)) return last;
    return target;
  }

  List<int> get _years => [
        for (int y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
      ];

  List<int> get _months {
    final year = _selectedDate.year;
    final startMonth =
        year == widget.firstDate.year ? widget.firstDate.month : 1;
    final endMonth = year == widget.lastDate.year ? widget.lastDate.month : 12;
    return [for (int m = startMonth; m <= endMonth; m++) m];
  }

  void _updateYear(int? year) {
    if (year == null) return;
    final daysInMonth = DateTime(year, _selectedDate.month + 1, 0).day;
    final next = DateTime(
      year,
      _selectedDate.month,
      _selectedDate.day.clamp(1, daysInMonth),
    );
    setState(() => _selectedDate = _clampDate(next));
  }

  void _updateMonth(int? month) {
    if (month == null) return;
    final daysInMonth = DateTime(_selectedDate.year, month + 1, 0).day;
    final next = DateTime(
      _selectedDate.year,
      month,
      _selectedDate.day.clamp(1, daysInMonth),
    );
    setState(() => _selectedDate = _clampDate(next));
  }

  @override
  Widget build(BuildContext context) {
    final visibleMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final firstWeekday = visibleMonth.weekday % 7;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final totalCells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    final screen = MediaQuery.sizeOf(context);
    final dialogW = (screen.width - 48).clamp(300.0, 360.0);

    return PartitionGlassDialog.modal(
      constraints: BoxConstraints.tightFor(width: dialogW),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '날짜 선택',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              ),
              PartitionModalCloseButton(
                onPressed: () => Navigator.pop(context),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSelectorField<int>(
                  value: _selectedDate.year,
                  items: _years,
                  labelBuilder: (year) => '$year년',
                  onChanged: _updateYear,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSelectorField<int>(
                  value: _selectedDate.month,
                  items: _months,
                  labelBuilder: (month) => '$month월',
                  onChanged: _updateMonth,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              _ReceiptWeekdayLabel('일'),
              _ReceiptWeekdayLabel('월'),
              _ReceiptWeekdayLabel('화'),
              _ReceiptWeekdayLabel('수'),
              _ReceiptWeekdayLabel('목'),
              _ReceiptWeekdayLabel('금'),
              _ReceiptWeekdayLabel('토'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.1,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final day = index - firstWeekday + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(
                visibleMonth.year,
                visibleMonth.month,
                day,
              );
              final selectable = !date.isBefore(_dateOnly(widget.firstDate)) &&
                  !date.isAfter(_dateOnly(widget.lastDate));
              final selected = _dateOnly(date) == _dateOnly(_selectedDate);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: selectable ? () => Navigator.pop(context, date) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected
                          ? Colors.white.withOpacity(0.18)
                          : Colors.white.withOpacity(0.06),
                      border: Border.all(
                        color: selected
                            ? Colors.white.withOpacity(0.42)
                            : Colors.white.withOpacity(0.12),
                        width: 0.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: selectable
                            ? Colors.white
                            : Colors.white.withOpacity(0.24),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${_selectedDate.year}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 13,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorField<T>({
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF2C2C2E),
          iconEnabledColor: Colors.white70,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard Variable',
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelBuilder(item)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ReceiptWeekdayLabel extends StatelessWidget {
  const _ReceiptWeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'Pretendard Variable',
          ),
        ),
      ),
    );
  }
}
