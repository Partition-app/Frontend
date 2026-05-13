import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/partition/models/partition_report_model.dart';
import 'package:partition_app/features/partition/services/report_service.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/features/partition/widgets/shared_expense_filter_chip.dart';
import 'package:partition_app/shared/utils/partition_dummy_data_policy.dart';
import 'package:partition_app/shared/widgets/frosted_panel.dart';
import 'package:partition_app/shared/widgets/glassmorphic_date_picker.dart';

// --- 더미 데이터 (API 연동 시 교체) ---

class _ChoreReportItem {
  final String name;
  /// 난이도 1(쉬움) ~ 5(어려움)
  final int difficultyStars;
  final String topPerson;
  final int topCount;
  final String lowPerson;
  final int lowCount;
  final int daysSinceLast;
  /// null이면 기본 스마일 이모지로 대체
  final String? emoji;
  /// API: 조회 기간 전체 완료 횟수. null이면 카드에 표시 안 함
  final int? totalCompleted;

  const _ChoreReportItem({
    required this.name,
    required this.difficultyStars,
    required this.topPerson,
    required this.topCount,
    required this.lowPerson,
    required this.lowCount,
    required this.daysSinceLast,
    this.emoji,
    this.totalCompleted,
  });
}

class _UtilityDeltaRow {
  final String name;
  final String prevMonth;
  final String thisMonth;
  final String rateLabel;

  const _UtilityDeltaRow(
    this.name,
    this.prevMonth,
    this.thisMonth,
    this.rateLabel,
  );
}

class _ReservationReportRow {
  final String item;
  final String mostUser;
  final String leastUser;
  final String usageTime;

  const _ReservationReportRow(
    this.item,
    this.mostUser,
    this.leastUser,
    this.usageTime,
  );
}

class _SettlementReportRow {
  final String content;
  final String date;
  final String amount;
  final String note;

  const _SettlementReportRow(this.content, this.date, this.amount, this.note);
}

const List<_ChoreReportItem> _kReportDummyChoreItems = [
  _ChoreReportItem(
    name: '설거지',
    difficultyStars: 3,
    topPerson: '민지',
    topCount: 12,
    lowPerson: '우진',
    lowCount: 3,
    daysSinceLast: 1,
    emoji: '🧤',
  ),
  _ChoreReportItem(
    name: '청소기 돌리기',
    difficultyStars: 2,
    topPerson: '지원',
    topCount: 8,
    lowPerson: '민지',
    lowCount: 2,
    daysSinceLast: 4,
    emoji: '🧹',
  ),
  _ChoreReportItem(
    name: '분리수거',
    difficultyStars: 5,
    topPerson: '우진',
    topCount: 6,
    lowPerson: '지원',
    lowCount: 1,
    daysSinceLast: 2,
    emoji: '♻️',
  ),
];

const List<_UtilityDeltaRow> _kReportDummyUtilityDeltas = [
  _UtilityDeltaRow('전기세', '42,000원', '48,500원', '+15.5%'),
  _UtilityDeltaRow('가스비', '18,200원', '15,900원', '-12.6%'),
];

const List<List<String>> _kReportDummyConsumptionTopRows = [
  ['최고지출', '라면 5입 묶음 (45,000원)'],
  ['최다구매', '생수 2L (구매 8건)'],
];

const List<_ReservationReportRow> _kReportDummyReservationRows = [
  _ReservationReportRow('욕실', '우진 (12회)', '지원 (2회)', '45분'),
  _ReservationReportRow('세탁기', '민지 (9회)', '우진 (1회)', '60분'),
  _ReservationReportRow('공용 거실 TV', '지원 (6회)', '민지 (0회)', '90분'),
];

const List<_SettlementReportRow> _kReportDummySettlementGoodsRows = [
  _SettlementReportRow('콘푸라이트 500g', '25.05.04.', '5,980원', '3개'),
  _SettlementReportRow('두루마리 휴지', '25.05.05.', '8,000원', '3개'),
];

const List<_SettlementReportRow> _kReportDummySettlementUtilRows = [
  _SettlementReportRow('전기세', '15일', '45,000원', '자동이체'),
  _SettlementReportRow('월세', '5일', '600,000원', '고정'),
];

/// 파티션 리포트 — 공용소비·게시판과 동일 헤더·글래스 톤
class PartitionReportScreen extends StatefulWidget {
  const PartitionReportScreen({super.key});

  @override
  State<PartitionReportScreen> createState() => _PartitionReportScreenState();
}

class _PartitionReportScreenState extends State<PartitionReportScreen> {
  static const double _headerHeight = 87.5;
  static const double _contentPaddingHorizontal = 16.0;
  static const double _contentPaddingBottom = 16.0;
  static const double _scrollBottomInsetForTabBar = 147.0;
  static const double _scrollExtraTailSpace = 56.0;
  static const double _chipVerticalSpacingScale = 0.5;
  static const double _spacingSmall = 10.0;
  static const double _spacingMedium = 16.0;
  static const double _spacingLarge = 20.0;
  /// 공용소비 본문 카드 사이 간격과 비슷하게 — 리포트 섹션(카드) 사이
  static const double _reportSectionGap = 24.0;
  /// 조회 기간 카드 높이(대략) — 공용소비 칩 행과 같이 대칭 여백 계산에 사용
  static const double _dateCardAnchorHeight = 158.0;
  /// 스크롤이 길어 band가 부족할 때도 상·하에 남길 최소 반쪽 여백(계산용)
  static const double _minSymmetricPadBandHalf = 14.0;
  static const double _borderRadiusLarge = 32.0;
  static const double _borderRadiusSmall = 24.0;
  static const int _settlementItemsPerPage = 5;
  static const double _settlementTablePageViewHeight = 132.0;
  static const List<String> _reservationMetricLabels = [
    '가장 많이 사용',
    '가장 적게 사용',
    '사용 시간',
  ];
  /// 리포트 전체 기간 (집안일·소비·예약)
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  /// 정산 파트 전용 기간
  late DateTime _settlementStart;
  late DateTime _settlementEnd;
  int _settlementFilter = 0; // 0 공용물품, 1 공과금

  final PageController _chorePageController = PageController();
  int _chorePageIndex = 0;
  final PageController _settlementPageController = PageController();
  int _settlementPageIndex = 0;
  int _reservationMetricIndex = 0;

  final ReportService _reportService = ReportService();

  List<_ChoreReportItem> _choreItems = [];
  /// 디버그·미로그인 시에만 더미 행 표시
  bool _reportUseDummy = false;
  bool? _reportDummySynced;

  bool _reportLoading = false;
  List<List<String>> _apiConsumptionTopRows = [];
  List<_UtilityDeltaRow> _apiUtilityDeltas = [];
  List<_ReservationReportRow> _apiReservationRows = [];

  /// GET `/reports/settlement` — 정산 완료 공용물품·공과금
  List<_SettlementReportRow> _apiSettlementGoodsRows = [];
  List<_SettlementReportRow> _apiSettlementBillRows = [];
  bool _settlementLoading = false;
  String? _settlementError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _rangeStart = today.subtract(const Duration(days: 14));
    _rangeEnd = today;
    _settlementStart = DateTime(today.year, today.month, 1);
    _settlementEnd = today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context).isAuthenticated,
    );
    if (_reportDummySynced == useDummy) return;
    _reportDummySynced = useDummy;
    setState(() {
      _reportUseDummy = useDummy;
      _choreItems = useDummy
          ? List<_ChoreReportItem>.from(_kReportDummyChoreItems)
          : <_ChoreReportItem>[];
      _chorePageIndex = 0;
      _settlementPageIndex = 0;
      if (useDummy) {
        _apiConsumptionTopRows = [];
        _apiUtilityDeltas = [];
        _apiReservationRows = [];
        _apiSettlementGoodsRows = [];
        _apiSettlementBillRows = [];
        _settlementLoading = false;
        _settlementError = null;
        _reportLoading = false;
      } else {
        _apiSettlementGoodsRows = [];
        _apiSettlementBillRows = [];
        _settlementError = null;
        _settlementLoading = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_chorePageController.hasClients) {
        _chorePageController.jumpToPage(0);
      }
      _syncSettlementPageToCurrentRows();
      if (!useDummy) {
        _scheduleReportLoad();
        _scheduleSettlementLoad();
      }
    });
  }

  bool _shouldUseLiveReportApi(BuildContext context) =>
      !usePartitionDummyData(
        Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
      );

  String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// API `purchaseDate` yyyy-MM-dd → 테이블용 yy.MM.dd.
  String _formatPurchaseDateShort(String iso) {
    final parts = iso.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]) ?? 0;
      final yy = (y % 100).toString().padLeft(2, '0');
      return '$yy.${parts[1]}.${parts[2]}.';
    }
    return iso;
  }

  /// API `billingMonth` yyyy-MM → 테이블용 yyyy.MM.
  String _formatBillingMonthShort(String ym) {
    final parts = ym.split('-');
    if (parts.length >= 2) {
      return '${parts[0]}.${parts[1].padLeft(2, '0')}.';
    }
    return ym;
  }

  String? _emojiForChore({
    required String choreType,
    required String choreName,
  }) {
    switch (choreType.toUpperCase()) {
      case 'DISH_WASHING':
      case 'DISHWASHING':
        return '🧤';
      case 'COOKING':
        return '🧑‍🍳';
      case 'TRASH':
      case 'FOODTRASH':
        return '🗑️';
      case 'TRASH_RECYCLING':
      case 'RECYCLING':
        return '♻️';
      case 'VACUUM_CLEANING':
      case 'VACUUM':
      case 'CLEANING':
        return '🧹';
      case 'MOPPING':
        return '🧽';
      case 'WINDOW':
        return '🪟';
      case 'BATHROOM':
        return '🚽';
      case 'FRIDGE':
        return '🧊';
      case 'LAUNDRY':
        return '🧺';
      case 'PET_CARE':
        return '🐾';
      default:
        final normalizedName = choreName.trim();
        if (normalizedName.contains('일반쓰레기') ||
            normalizedName.contains('음식물')) {
          return '🗑️';
        }
        if (normalizedName.contains('설거지')) return '🧤';
        if (normalizedName.contains('요리')) return '🧑‍🍳';
        if (normalizedName.contains('청소기')) return '🧹';
        if (normalizedName.contains('창문') ||
            normalizedName.contains('창틀')) {
          return '🪟';
        }
        if (normalizedName.contains('화장실')) return '🚽';
        if (normalizedName.contains('바닥')) return '🧽';
        if (normalizedName.contains('냉장고')) return '🧊';
        if (normalizedName.contains('빨래')) return '🧺';
        if (normalizedName.contains('분리수거')) return '♻️';
        return null;
    }
  }

  String _commaWon(int n) =>
      '${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

  String _billChangeRateLabel(double rate) =>
      '${rate > 0 ? '+' : ''}${rate.toStringAsFixed(1)}%';

  List<_ChoreReportItem> _mapChoresFromApi(List<ChoreReportEntry> list) =>
      list
          .map(
            (e) => _ChoreReportItem(
              name: e.choreName,
              difficultyStars:
                  e.avgDifficulty.round().clamp(1, 5),
              topPerson:
                  e.topPerformer?.userName.isNotEmpty == true
                      ? e.topPerformer!.userName
                      : '-',
              topCount: e.topPerformer?.count ?? 0,
              lowPerson:
                  e.bottomPerformer?.userName.isNotEmpty == true
                      ? e.bottomPerformer!.userName
                      : '-',
              lowCount: e.bottomPerformer?.count ?? 0,
              daysSinceLast: e.lastPerformedDaysAgo ?? -1,
              emoji: _emojiForChore(
                choreType: e.choreType,
                choreName: e.choreName,
              ),
              totalCompleted: e.totalCount,
            ),
          )
          .toList();

  List<List<String>> _rowsFromSupplies(ReportSupplies s) {
    final rows = <List<String>>[];
    final hi = s.highestAmountItem;
    if (hi != null && hi.itemName.isNotEmpty) {
      rows.add([
        '최고지출',
        '${hi.itemName} (${_commaWon(hi.amount)})',
      ]);
    }
    final mp = s.mostPurchasedItem;
    if (mp != null && mp.itemName.isNotEmpty) {
      rows.add([
        '최다구매',
        '${mp.itemName} (구매 ${mp.purchaseCount}건)',
      ]);
    }
    return rows;
  }

  List<_UtilityDeltaRow> _rowsFromBills(List<ReportBillDelta> bills) => bills
      .map(
        (b) => _UtilityDeltaRow(
          b.utilityTypeName.isNotEmpty ? b.utilityTypeName : b.utilityType,
          _commaWon(b.previousAmount),
          _commaWon(b.currentAmount),
          _billChangeRateLabel(b.changeRate),
        ),
      )
      .toList();

  String _reservationPerfLabel(ReportPerformer? p) =>
      p != null && p.userName.isNotEmpty ? '${p.userName} (${p.count}회)' : '-';

  List<_ReservationReportRow> _rowsFromReservations(
    List<ReservationReportEntry> list,
  ) =>
      list
          .map(
            (e) => _ReservationReportRow(
              e.itemName,
              _reservationPerfLabel(e.topPerformer),
              _reservationPerfLabel(e.bottomPerformer),
              e.avgDurationMinutes != null
                  ? '${e.avgDurationMinutes}분'
                  : '-',
            ),
          )
          .toList();

  List<_SettlementReportRow> _settlementRowsForCurrentFilter() {
    final goodsRows = _reportUseDummy
        ? _kReportDummySettlementGoodsRows
        : _apiSettlementGoodsRows;
    final utilRows = _reportUseDummy
        ? _kReportDummySettlementUtilRows
        : _apiSettlementBillRows;
    return _settlementFilter == 0 ? goodsRows : utilRows;
  }

  void _syncSettlementPageToCurrentRows() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_settlementPageController.hasClients) return;
      final pages = _paginateSettlementRows(
        _settlementRowsForCurrentFilter(),
        _settlementItemsPerPage,
      );
      final maxPage = pages.isEmpty ? 0 : pages.length - 1;
      final target = _settlementPageIndex.clamp(0, maxPage).toInt();
      if (_settlementPageIndex != target) {
        setState(() => _settlementPageIndex = target);
      }
      _settlementPageController.jumpToPage(target);
    });
  }

  void _selectSettlementFilter(int index) {
    if (_settlementFilter == index) return;
    setState(() {
      _settlementFilter = index;
      _settlementPageIndex = 0;
    });
    _syncSettlementPageToCurrentRows();
  }

  String _reservationMetricValue(_ReservationReportRow row) {
    switch (_reservationMetricIndex) {
      case 0:
        return row.mostUser;
      case 1:
        return row.leastUser;
      case 2:
        return row.usageTime;
      default:
        return row.mostUser;
    }
  }

  void _scheduleReportLoad() {
    if (!mounted || !_shouldUseLiveReportApi(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadReport());
    });
  }

  void _scheduleSettlementLoad() {
    if (!mounted || !_shouldUseLiveReportApi(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSettlementReport());
    });
  }

  Future<void> _loadSettlementReport() async {
    if (!mounted || !_shouldUseLiveReportApi(context)) return;
    setState(() {
      _settlementLoading = true;
      _settlementError = null;
    });
    try {
      final result = await _reportService.fetchSettlementReport(
        startDate: _dateToIso(_settlementStart),
        endDate: _dateToIso(_settlementEnd),
      );
      if (!mounted) return;
      setState(() {
        _settlementLoading = false;
        _settlementPageIndex = 0;
        _apiSettlementGoodsRows = result.supplies
            .map(
              (s) => _SettlementReportRow(
                s.itemName.isNotEmpty ? s.itemName : '-',
                _formatPurchaseDateShort(s.purchaseDate),
                _commaWon(s.amount),
                '${s.quantity}개',
              ),
            )
            .toList();
        _apiSettlementBillRows = result.bills
            .map(
              (b) => _SettlementReportRow(
                b.utilityTypeName.isNotEmpty
                    ? b.utilityTypeName
                    : b.utilityType,
                _formatBillingMonthShort(b.billingMonth),
                _commaWon(b.amount),
                '-',
              ),
            )
            .toList();
      });
      _syncSettlementPageToCurrentRows();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _settlementLoading = false;
        _settlementPageIndex = 0;
        _settlementError = e.message;
        _apiSettlementGoodsRows = [];
        _apiSettlementBillRows = [];
      });
      _syncSettlementPageToCurrentRows();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settlementLoading = false;
        _settlementPageIndex = 0;
        _settlementError = '정산 리포트를 불러오지 못했습니다.';
        _apiSettlementGoodsRows = [];
        _apiSettlementBillRows = [];
      });
      _syncSettlementPageToCurrentRows();
    }
  }

  Future<void> _loadReport() async {
    if (!mounted || !_shouldUseLiveReportApi(context)) return;
    setState(() => _reportLoading = true);
    try {
      final result = await _reportService.fetchReport(
        startDate: _dateToIso(_rangeStart),
        endDate: _dateToIso(_rangeEnd),
      );
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _choreItems = _mapChoresFromApi(result.chores);
        _apiConsumptionTopRows = _rowsFromSupplies(result.supplies);
        _apiUtilityDeltas = _rowsFromBills(result.bills);
        _apiReservationRows = _rowsFromReservations(result.reservations);
        _chorePageIndex = 0;
      });
      if (_chorePageController.hasClients) {
        _chorePageController.jumpToPage(0);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reportLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  Future<void> _onPullToRefresh() async {
    if (!_shouldUseLiveReportApi(context)) {
      if (!mounted) return;
      setState(() {
        _choreItems = List<_ChoreReportItem>.from(_kReportDummyChoreItems);
        _chorePageIndex = 0;
      });
      if (_chorePageController.hasClients) {
        _chorePageController.jumpToPage(0);
      }
      return;
    }
    await Future.wait<void>([
      _loadReport(),
      _loadSettlementReport(),
    ]);
  }

  @override
  void dispose() {
    _chorePageController.dispose();
    _settlementPageController.dispose();
    super.dispose();
  }

  bool get _withinOneMonth {
    final span = _rangeEnd.difference(_rangeStart).inDays + 1;
    return span <= 31;
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
  }

  Future<void> _pickRangeDate(bool isStart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 365));
    final cur = isStart ? _rangeStart : _rangeEnd;
    final initial = cur.isBefore(today) ? today : cur;

    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => GlassmorphicDatePicker(
        initialDate: initial,
        firstDate: DateTime(2020, 1, 1),
        lastDate: maxDate,
        isStartDate: isStart,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isStart) {
          _rangeStart = d;
          if (_rangeEnd.isBefore(_rangeStart)) _rangeEnd = _rangeStart;
        } else {
          _rangeEnd = d;
          if (_rangeEnd.isBefore(_rangeStart)) _rangeStart = _rangeEnd;
        }
      });
      _scheduleReportLoad();
    }
  }

  Future<void> _pickSettlementDate(bool isStart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 365));
    final cur = isStart ? _settlementStart : _settlementEnd;
    final initial = cur.isBefore(today) ? today : cur;

    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => GlassmorphicDatePicker(
        initialDate: initial,
        firstDate: DateTime(2020, 1, 1),
        lastDate: maxDate,
        isStartDate: isStart,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isStart) {
          _settlementStart = d;
          if (_settlementEnd.isBefore(_settlementStart)) {
            _settlementEnd = _settlementStart;
          }
        } else {
          _settlementEnd = d;
          if (_settlementEnd.isBefore(_settlementStart)) {
            _settlementStart = _settlementEnd;
          }
        }
      });
      _scheduleSettlementLoad();
    }
  }

  /// 조회 기간 카드 아래(집안일·소비·예약·정산) 스크롤 블록 추정 높이 — 공용소비 `belowChips`와 동일 역할
  double _estimatedBelowDateCardContentHeight() {
    const choreBlock = 366.0;
    final consumptionBlock = _withinOneMonth ? 440.0 : 296.0;
    const reservationBlock = 284.0;
    const settlementBlock = 440.0;
    return choreBlock +
        _reportSectionGap +
        consumptionBlock +
        _reportSectionGap +
        reservationBlock +
        _reportSectionGap +
        settlementBlock +
        12.0;
  }

  @override
  Widget build(BuildContext context) {
    final scrollBottomPadding = _contentPaddingBottom +
        MediaQuery.viewPaddingOf(context).bottom +
        _scrollBottomInsetForTabBar +
        _scrollExtraTailSpace;

    return Column(
      children: [
        _buildHeader(),
        if (!_reportUseDummy && _reportLoading)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Color(0x33FFFFFF),
            color: Colors.white70,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mq = MediaQuery.sizeOf(context);
              final rawH = constraints.maxHeight;
              final viewportH = (constraints.hasBoundedHeight &&
                      rawH.isFinite &&
                      rawH > 0)
                  ? rawH
                  : (mq.height -
                          _headerHeight -
                          MediaQuery.paddingOf(context).top -
                          MediaQuery.paddingOf(context).bottom -
                          150)
                      .clamp(120.0, 100000.0);
              final belowH = _estimatedBelowDateCardContentHeight();
              final band = viewportH - belowH - _contentPaddingBottom;
              final symmetricPadRaw =
                  (band - _dateCardAnchorHeight) / 2.0;
              final symmetricPadFull = symmetricPadRaw < _minSymmetricPadBandHalf
                  ? _minSymmetricPadBandHalf
                  : symmetricPadRaw;
              final symmetricPad =
                  (symmetricPadFull * _chipVerticalSpacingScale)
                      .clamp(12.0, 88.0);

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
                    _contentPaddingHorizontal,
                    0,
                    _contentPaddingHorizontal,
                    scrollBottomPadding,
                  ),
                  children: [
                    SizedBox(height: symmetricPad + 3),
                    _buildGlobalDateRow(),
                    SizedBox(height: symmetricPad + 3),
                    _buildChoreSection(),
                    const SizedBox(height: _reportSectionGap),
                    _buildConsumptionSection(),
                    const SizedBox(height: _reportSectionGap),
                    _buildReservationSection(),
                    const SizedBox(height: _reportSectionGap),
                    _buildSettlementSection(),
                    const SizedBox(height: 16),
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
                          '파티션 리포트',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Pretendard Variable',
                            fontSize: 22,
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

  Widget _buildGlobalDateRow() {
    const labelStyle = TextStyle(
      color: Colors.white70,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      fontFamily: 'Pretendard Variable',
    );
    const dateStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      fontFamily: 'Pretendard Variable',
    );

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '조회 기간',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                fontFamily: 'Pretendard Variable',
                height: 1.2,
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
          const SizedBox(height: 12),
          Text(
            '집안일·소비·예약 요약은 아래 기간을 기준으로 표시돼요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 13,
              fontFamily: 'Pretendard Variable',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          FrostedPanel(
            borderRadius: BorderRadius.circular(_borderRadiusSmall),
            backgroundOpacity: 0.08,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _dateSegment(
                      label: '시작일',
                      date: _formatDate(_rangeStart),
                      labelStyle: labelStyle,
                      dateStyle: dateStyle,
                      onTap: () => _pickRangeDate(true),
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
                    child: _dateSegment(
                      label: '종료일',
                      date: _formatDate(_rangeEnd),
                      labelStyle: labelStyle,
                      dateStyle: dateStyle,
                      onTap: () => _pickRangeDate(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateSegment({
    required String label,
    required String date,
    required TextStyle labelStyle,
    required TextStyle dateStyle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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

  Widget _buildChoreSection() {
    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('집안일'),
          const SizedBox(height: 6),
          Text(
            '집안일별 수행 내용을 확인해요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 14,
              fontFamily: 'Pretendard Variable',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 216,
            child: _choreItems.isEmpty
                ? Center(
                    child: Text(
                      '집안일 요약이 없어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 15,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  )
                : PageView.builder(
                    controller: _chorePageController,
                    itemCount: _choreItems.length,
                    onPageChanged: (i) => setState(() => _chorePageIndex = i),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _choreCard(_choreItems[i]),
                    ),
                  ),
          ),
          if (_choreItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPager(
              controller: _chorePageController,
              pageCount: _choreItems.length,
              currentIndex: _chorePageIndex,
            ),
          ],
        ],
      ),
    );
  }

  /// 난이도 1~5 — 왼쪽부터 채워진 별 개수로 표현
  Widget _choreDifficultyStarsRow(int starsOutOf5) {
    final n = starsOutOf5.clamp(1, 5);
    return Semantics(
      label: '난이도 $n점',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final filled = i < n;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 26.4,
              color: filled
                  ? HomeShareStyle.point
                  : Colors.white.withOpacity(0.32),
              shadows: filled
                  ? [
                      Shadow(
                        color: HomeShareStyle.point.withOpacity(0.72),
                        blurRadius: 10,
                        offset: const Offset(0, 0),
                      ),
                      Shadow(
                        color: Colors.white.withOpacity(0.32),
                        blurRadius: 4,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _choreCard(_ChoreReportItem c) {
    return FrostedPanel(
      borderRadius: BorderRadius.circular(20),
      backgroundOpacity: 0.06,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  c.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeShareStyle.point,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
                const SizedBox(height: 6),
                _choreDifficultyStarsRow(c.difficultyStars),
                const SizedBox(height: 10),
                _choreLine(
                  '가장 많이 한 멤버',
                  c.topPerson == '-' ? '-' : '${c.topPerson} · ${c.topCount}회',
                ),
                _choreLine(
                  '가장 적게 한 멤버',
                  c.lowPerson == '-' ? '-' : '${c.lowPerson} · ${c.lowCount}회',
                ),
                _choreLine(
                  '마지막 완료',
                  c.daysSinceLast < 0 ? '데이터 없음' : '${c.daysSinceLast}일 전',
                ),
                if (c.totalCompleted != null)
                  _choreLine('전체 완료 횟수', '${c.totalCompleted}회'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choreLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        textAlign: TextAlign.center,
        softWrap: true,
        TextSpan(
          style: const TextStyle(height: 1.35),
          children: [
            TextSpan(
              text: k,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: v,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumptionSection() {
    final topRows = _reportUseDummy
        ? _kReportDummyConsumptionTopRows
        : _apiConsumptionTopRows;

    final utilityDeltaRows = _reportUseDummy
        ? _kReportDummyUtilityDeltas
        : _apiUtilityDeltas;

    final showUtilityDummy = _reportUseDummy && _withinOneMonth;
    final showUtilityApi =
        !_reportUseDummy && utilityDeltaRows.isNotEmpty;

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('공용 소비'),
          const SizedBox(height: 14),
          if (topRows.isEmpty && !_reportUseDummy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '해당 기간 공용 소비 요약이 없어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 14,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            )
          else
            _simpleTable(
              headers: const ['구분', '내용'],
              flexes: const [2, 5],
              rows: topRows,
            ),
          if (showUtilityDummy || showUtilityApi) ...[
            const SizedBox(height: 28),
            _sectionTitle('공과금 변동'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                _reportUseDummy
                    ? '전월 대비 ±10% 이상, 기간 31일 이내'
                    : '전월 대비 ±10% 이상 변동만 표시돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _simpleTable(
              headers: const ['항목', '전월 금액', '당월 금액', '변동률'],
              flexes: const [2, 2, 2, 2],
              rows: utilityDeltaRows
                  .map((e) => [e.name, e.prevMonth, e.thisMonth, e.rateLabel])
                  .toList(),
            ),
          ] else if (_reportUseDummy && !_withinOneMonth) ...[
            const SizedBox(height: 10),
            Text(
              '공과금 변동 요약은 조회 기간이 31일 이내일 때만 표시돼요.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ] else if (!_reportUseDummy) ...[
            const SizedBox(height: 20),
            Text(
              '전월 대비 ±10% 이상 변동된 공과금이 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReservationSection() {
    final rows = _reportUseDummy
        ? _kReportDummyReservationRows
        : _apiReservationRows;
    final metricLabel = _reservationMetricLabels[_reservationMetricIndex];

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('예약'),
          const SizedBox(height: 8),
          if (rows.isEmpty && !_reportUseDummy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '해당 기간 예약 요약이 없어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 14,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
            )
          else ...[
            Text(
              '물품은 유지하고 보고 싶은 기준만 선택해서 확인해요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 14,
                fontFamily: 'Pretendard Variable',
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var index = 0;
                    index < _reservationMetricLabels.length;
                    index++) ...[
                  Expanded(
                    child: SharedExpenseFilterChip(
                      label: _reservationMetricLabels[index],
                      selected: _reservationMetricIndex == index,
                      width: double.infinity,
                      horizontalPadding: 6,
                      verticalPadding: 7,
                      minHeight: 38,
                      borderRadius: 19,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      onTap: () => setState(
                        () => _reservationMetricIndex = index,
                      ),
                    ),
                  ),
                  if (index < _reservationMetricLabels.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _simpleTable(
              headers: ['물품', metricLabel],
              flexes: const [2, 3],
              rows: rows
                  .map((e) => [e.item, _reservationMetricValue(e)])
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettlementSection() {
    final rows = _settlementRowsForCurrentFilter();
    final pagedRows = _paginateSettlementRows(rows, _settlementItemsPerPage);
    final pageIndexSafe =
        _settlementPageIndex.clamp(0, pagedRows.length - 1).toInt();
    final isUtility = _settlementFilter == 1;

    final utilHeaders = _reportUseDummy
        ? const ['내용', '납부일', '납부액', '비고']
        : const ['내용', '청구월', '금액', '비고'];

    final showLiveEmptyHint = !_reportUseDummy &&
        !_settlementLoading &&
        _settlementError == null &&
        rows.isEmpty;

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('정산'),
          const SizedBox(height: 6),
          Text(
            '정산 내역은 아래 기간으로 다시 고를 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 13,
              fontFamily: 'Pretendard Variable',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildSettlementDateRow(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SharedExpenseFilterChip(
                  label: '공용물품',
                  selected: _settlementFilter == 0,
                  width: double.infinity,
                  horizontalPadding: 12,
                  onTap: () => _selectSettlementFilter(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SharedExpenseFilterChip(
                  label: '공과금',
                  selected: _settlementFilter == 1,
                  width: double.infinity,
                  horizontalPadding: 12,
                  onTap: () => _selectSettlementFilter(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_reportUseDummy && _settlementLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
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
            ),
          ] else if (!_reportUseDummy && _settlementError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _settlementError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 14,
                  fontFamily: 'Pretendard Variable',
                  height: 1.35,
                ),
              ),
            )
          else if (showLiveEmptyHint)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '해당 기간에 정산 완료된 내역이 없어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 14,
                  fontFamily: 'Pretendard Variable',
                  height: 1.35,
                ),
              ),
            )
          else
            Column(
              children: [
                Text(
                  '좌우로 넘기거나 화살표로 정산 내역을 볼 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard Variable',
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSettlementPagedTable(
                  headers: isUtility
                      ? utilHeaders
                      : const ['내용', '날짜', '금액', '수량'],
                  flexes: isUtility
                      ? const [4, 2, 3, 3]
                      : const [4, 3, 3, 2],
                  pages: pagedRows,
                ),
                const SizedBox(height: 10),
                _buildPager(
                  controller: _settlementPageController,
                  pageCount: pagedRows.length,
                  currentIndex: pageIndexSafe,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSettlementDateRow() {
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _dateSegment(
                label: '시작일',
                date: _formatDate(_settlementStart),
                labelStyle: labelStyle,
                dateStyle: dateStyle,
                onTap: () => _pickSettlementDate(true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.white.withOpacity(0.22),
              ),
            ),
            Expanded(
              child: _dateSegment(
                label: '종료일',
                date: _formatDate(_settlementEnd),
                labelStyle: labelStyle,
                dateStyle: dateStyle,
                onTap: () => _pickSettlementDate(false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettlementPagedTable({
    required List<String> headers,
    required List<int> flexes,
    required List<List<_SettlementReportRow>> pages,
  }) {
    final rowSlotHeight =
        _settlementTablePageViewHeight / _settlementItemsPerPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCompactTableHeader(headers: headers, flexes: flexes),
        const SizedBox(height: 8),
        SizedBox(
          height: _settlementTablePageViewHeight,
          child: PageView.builder(
            controller: _settlementPageController,
            physics: const PageScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            itemCount: pages.length,
            onPageChanged: (index) =>
                setState(() => _settlementPageIndex = index),
            itemBuilder: (context, pageIndex) {
              final pageRows = pages[pageIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _settlementItemsPerPage; i++)
                    SizedBox(
                      height: rowSlotHeight,
                      child: i < pageRows.length
                          ? Align(
                              alignment: Alignment.center,
                              child: _buildSettlementRow(
                                pageRows[i],
                                flexes: flexes,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTableHeader({
    required List<String> headers,
    required List<int> flexes,
  }) {
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < headers.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              flex: flexes[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FrostedPanel(
                  borderRadius: BorderRadius.circular(20),
                  backgroundOpacity: 0.4,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Center(
                      child: Text(
                        headers[i],
                        style: _th,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettlementRow(
    _SettlementReportRow row, {
    required List<int> flexes,
  }) {
    const rowStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.35,
      fontFamily: 'Pretendard Variable',
    );
    const contentStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.35,
      fontFamily: 'Pretendard Variable',
    );

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

    final values = [row.content, row.date, row.amount, row.note];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            flex: flexes[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: i == 0
                  ? Text(
                      values[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: contentStyle,
                    )
                  : fittedCell(values[i], rowStyle),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPager({
    required PageController controller,
    required int pageCount,
    required int currentIndex,
  }) {
    void goPrev() {
      if (currentIndex <= 0) return;
      controller.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    void goNext() {
      if (currentIndex >= pageCount - 1) return;
      controller.nextPage(
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
            children: List.generate(pageCount, (index) {
              final active = index == currentIndex;
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

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
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
    );
  }

  static const TextStyle _th = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    fontSize: 12,
    height: 1.3,
    fontFamily: 'Pretendard Variable',
  );

  static const TextStyle _td = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
    fontFamily: 'Pretendard Variable',
  );

  Widget _simpleTable({
    required List<String> headers,
    required List<int> flexes,
    required List<List<String>> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < headers.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: flexes[i],
                  child: FrostedPanel(
                    borderRadius: BorderRadius.circular(20),
                    backgroundOpacity: 0.35,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Center(
                      child: Text(
                        headers[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: _th,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < r.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    flex: flexes[i],
                    child: Center(
                      child: Text(
                        r[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _td,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

List<List<_SettlementReportRow>> _paginateSettlementRows(
  List<_SettlementReportRow> rows,
  int pageSize,
) {
  if (rows.isEmpty) {
    return [[]];
  }
  final pages = <List<_SettlementReportRow>>[];
  for (var i = 0; i < rows.length; i += pageSize) {
    final end = i + pageSize > rows.length ? rows.length : i + pageSize;
    pages.add(rows.sublist(i, end));
  }
  return pages;
}
