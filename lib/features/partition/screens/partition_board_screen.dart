import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/partition/models/reservation_item_model.dart';
import 'package:partition_app/features/partition/models/reservation_booking_model.dart';
import 'package:partition_app/features/partition/services/reservation_items_service.dart';
import 'package:partition_app/features/partition/services/reservations_service.dart';
import 'package:partition_app/shared/widgets/frosted_panel.dart';
import 'package:partition_app/shared/widgets/glassmorphic_date_picker.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/primary_button.dart';
import 'package:partition_app/shared/utils/partition_dummy_data_policy.dart';
import 'package:partition_app/core/network/api_exception.dart';

class _BoardReservationRow {
  final String content;
  final String start;
  final String end;
  final String person;
  final bool completed;
  /// 서버 `GET /reservations/items`로 받은 예약 대상 행일 때만 설정 (삭제 시 API)
  final int? itemId;
  final bool isCatalogRow;
  /// 서버 `GET /reservations` 예약 건
  final int? reservationId;
  /// 실제 시작·종료 시각(카운트다운용). 없으면 [end] 문자열만 표시.
  final DateTime? slotStart;
  final DateTime? slotEnd;

  const _BoardReservationRow(
    this.content,
    this.start,
    this.end,
    this.person, {
    this.completed = false,
    this.itemId,
    this.isCatalogRow = false,
    this.reservationId,
    this.slotStart,
    this.slotEnd,
  });
}

/// [dummyRow] 더미 모드에서만 사용 · [serverBookingCreated] 실서버 `POST /reservations` 성공
class _ReservationFormDialogOutcome {
  final _BoardReservationRow? dummyRow;
  final bool serverBookingCreated;

  const _ReservationFormDialogOutcome._({
    this.dummyRow,
    this.serverBookingCreated = false,
  });

  factory _ReservationFormDialogOutcome.dummy(_BoardReservationRow row) =>
      _ReservationFormDialogOutcome._(dummyRow: row);

  factory _ReservationFormDialogOutcome.serverSuccess() =>
      const _ReservationFormDialogOutcome._(serverBookingCreated: true);
}


List<List<T>> _paginateRows<T>(List<T> items, int pageSize) {
  if (items.isEmpty) {
    return [[]];
  }
  final pages = <List<T>>[];
  for (var i = 0; i < items.length; i += pageSize) {
    final end = i + pageSize > items.length ? items.length : i + pageSize;
    pages.add(items.sublist(i, end));
  }
  return pages;
}

/// 공용소비와 동일한 글래스·칩·표 패턴의 게시판 (예약 관리 / 예약게시판)
class PartitionBoardScreen extends StatefulWidget {
  const PartitionBoardScreen({super.key});

  @override
  State<PartitionBoardScreen> createState() => _PartitionBoardScreenState();
}

class _PartitionBoardScreenState extends State<PartitionBoardScreen> {
  static const double _headerHeight = 87.5;
  static const double _contentPaddingHorizontal = 16.0;
  static const double _contentPaddingBottom = 16.0;
  static const double _scrollBottomInsetForTabBar = 147.0;
  static const double _scrollExtraTailSpace = 56.0;
  static const double _spacingSmall = 10.0;
  static const double _spacingMedium = 16.0;
  static const double _spacingLarge = 20.0;
  static const double _borderRadiusLarge = 32.0;
  static const double _borderRadiusSmall = 24.0;
  static const int _itemsPerPage = 5;
  static const double _tablePageViewHeight = 132.0;

  late DateTime _startDate;
  late DateTime _endDate;
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  List<_BoardReservationRow> _reservationRows = [];
  /// 로그인·실데이터: `GET /reservations/items` — 예약하기·물품 수정 다이얼로그용
  List<_BoardReservationRow> _catalogFromApi = [];
  bool? _boardDummySynced;

  bool _reservationSelectionMode = false;
  final Set<int> _selectedReservationIndices = <int>{};
  Timer? _reservationEndCountdownTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 예약 기간: 오늘 포함 최근 7일 (이전 6일 + 오늘)
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 6));
    _reservationEndCountdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      _onReservationEndCountdownTick,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context).isAuthenticated,
    );
    if (_boardDummySynced == useDummy) return;
    _boardDummySynced = useDummy;
    setState(() {
      if (useDummy) {
        _catalogFromApi = [];
        _reservationRows = _buildDummyReservationRows();
      } else {
        _catalogFromApi = [];
        _reservationRows = [];
      }
      _pageIndex = 0;
    });
    _schedulePageJump();
    if (!useDummy) {
      _loadReservationBoardSources();
    }
  }

  /// 표 셀용: `DateTime` → `M.d HH:mm`
  String _formatReservationTableCell(DateTime d) {
    return '${d.month}.${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 더미 예약 행 — 당일 기준 [slotStart]/[slotEnd]로 종료 열 카운트다운 가능
  List<_BoardReservationRow> _buildDummyReservationRows() {
    final n = DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    final specs = <(String, int, int, int, int, String)>[
      ('욕실', 8, 30, 9, 0, '우진'),
      ('TV', 9, 50, 11, 0, '지원'),
      ('세탁기', 18, 0, 19, 0, '민지'),
      ('인덕션', 20, 0, 20, 40, '지원'),
      ('드레스룸', 21, 0, 21, 30, '우진'),
    ];
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return specs.map((t) {
      final s = DateTime(day.year, day.month, day.day, t.$2, t.$3);
      final e = DateTime(day.year, day.month, day.day, t.$4, t.$5);
      return _BoardReservationRow(
        t.$1,
        hm(s),
        hm(e),
        t.$6,
        slotStart: s,
        slotEnd: e,
      );
    }).toList();
  }

  /// 진행 중 예약의 종료 열: `N분 후 종료` / `N시간 N분 후 종료` / `N일 N시간 N분 후 종료`
  String _formatCountdownToEnd(DateTime slotEnd, DateTime now) {
    var diff = slotEnd.difference(now);
    if (diff.inSeconds <= 0) return '';
    if (diff.inSeconds < 60) {
      return '1분 미만 후 종료';
    }
    final days = diff.inDays;
    diff -= Duration(days: days);
    final hours = diff.inHours;
    diff -= Duration(hours: hours);
    final minutes = diff.inMinutes;
    if (days > 0) {
      return '${days}일 ${hours}시간 ${minutes}분 후 종료';
    }
    if (hours > 0) {
      return '${hours}시간 ${minutes}분 후 종료';
    }
    return '${minutes}분 후 종료';
  }

  String _displayEndColumn(_BoardReservationRow r) {
    if (r.completed) return r.end;
    final start = r.slotStart;
    final end = r.slotEnd;
    if (start == null || end == null) return r.end;
    final now = DateTime.now();
    if (now.isBefore(start) || !now.isBefore(end)) return r.end;
    return _formatCountdownToEnd(end, now);
  }

  /// [slotEnd] 이전이면 시작 전→진행 중·카운트다운 갱신 등 표시가 바뀔 수 있음
  bool _needsReservationEndColumnTick() {
    final now = DateTime.now();
    for (final r in _reservationRows) {
      if (r.completed) continue;
      final e = r.slotEnd;
      if (e == null) continue;
      if (now.isBefore(e)) return true;
    }
    return false;
  }

  void _onReservationEndCountdownTick(Timer timer) {
    if (!mounted) return;
    if (!_needsReservationEndColumnTick()) return;
    setState(() {});
  }

  _BoardReservationRow _rowFromReservationEntry(ReservationListEntry e) {
    return _BoardReservationRow(
      e.itemName,
      _formatReservationTableCell(e.startTime),
      _formatReservationTableCell(e.endTime),
      (e.reservedBy?.name ?? '').trim().isEmpty ? '—' : e.reservedBy!.name,
      reservationId: e.reservationId,
      slotStart: e.startTime,
      slotEnd: e.endTime,
    );
  }

  /// 예약 대상(items) + 기간 내 예약 목록(`GET /reservations`) 동시 갱신
  Future<void> _loadReservationBoardSources() async {
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    if (useDummy || !mounted) return;
    try {
      final items = await ReservationItemsService().fetchItems();
      final reservations = await ReservationsService().fetchReservations(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      setState(() {
        _catalogFromApi = items
            .map(
              (e) => _BoardReservationRow(
                e.name,
                '—',
                '—',
                '—',
                itemId: e.itemId,
                isCatalogRow: true,
              ),
            )
            .toList();
        _reservationRows =
            reservations.map(_rowFromReservationEntry).toList();
        _clampPageIndex();
      });
      _schedulePageJump();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : '예약 정보를 불러오지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  /// 날짜 범위만 바뀐 뒤 예약 목록만 다시 조회
  Future<void> _loadReservationsListOnly() async {
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    if (useDummy || !mounted) return;
    try {
      final reservations = await ReservationsService().fetchReservations(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      setState(() {
        _reservationRows =
            reservations.map(_rowFromReservationEntry).toList();
        _clampPageIndex();
      });
      _schedulePageJump();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : '예약 목록을 불러오지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  void dispose() {
    _reservationEndCountdownTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// 예약 **일정**의 예약자(예약하는 사람)는 항상 현재 로그인한 계정으로만 기록한다.
  String _reserverDisplayName(AuthProvider auth) {
    final u = auth.user;
    if (u == null) return '나';
    final n = u.name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final email = u.email.trim();
    if (email.isEmpty) return '나';
    final at = email.indexOf('@');
    if (at > 0) return email.substring(0, at);
    return email;
  }

  void _schedulePageJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        final pages = _paginateRows(_reservationRows, _itemsPerPage);
        final maxPage = pages.isEmpty ? 0 : pages.length - 1;
        final ix = _pageIndex.clamp(0, maxPage);
        _pageController.jumpToPage(ix);
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
  }

  Future<void> _selectDate(bool isStartDate) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 365));
    final selectedDate = isStartDate ? _startDate : _endDate;
    final initialDate = selectedDate.isBefore(today) ? today : selectedDate;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => GlassmorphicDatePicker(
        initialDate: initialDate,
        firstDate: today,
        lastDate: maxDate,
        isStartDate: isStartDate,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isStartDate) {
          _startDate = d;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = d;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
      _loadReservationsListOnly();
    }
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
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              _contentPaddingHorizontal,
              _spacingMedium,
              _contentPaddingHorizontal,
              scrollBottomPadding,
            ),
            children: [
              _buildMainCard(),
              const SizedBox(height: _spacingSmall),
              ..._buildActionButtons(),
              const SizedBox(height: 12),
            ],
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
                          '게시판',
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


  Widget _buildMainCard() {
    final pages = _paginateRows(_reservationRows, _itemsPerPage);
    final pageSafe = _pageIndex.clamp(0, pages.length - 1).toInt();

    return FrostedPanel(
      borderRadius: BorderRadius.circular(_borderRadiusLarge),
      backgroundOpacity: 0.0,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: Text(
                '예약 관리',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
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
            ),
          ),
          const SizedBox(height: _spacingMedium),
          _buildDateRangeGlassRow(),
          const SizedBox(height: _spacingLarge),
          FrostedPanel(
            borderRadius: BorderRadius.circular(20),
            backgroundOpacity: 0.0,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTableHeader(
                  selectionMode: _reservationSelectionMode,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: _tablePageViewHeight,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const PageScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    onPageChanged: (i) => setState(() => _pageIndex = i),
                    itemCount: pages.length,
                    itemBuilder: (context, pageIndex) {
                      return _buildReservationPage(
                        pages[pageIndex],
                        pageIndex: pageIndex,
                        itemsPerPage: _itemsPerPage,
                        selectionMode: _reservationSelectionMode,
                        selectedIndices: _selectedReservationIndices,
                        onToggleRow: _toggleReservationRowSelection,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _buildPageControl(
                  pageCount: pages.length,
                  currentIndex: pageSafe,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _buildReservationTableToolbar(),
          ),
        ],
      ),
    );
  }

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
              child: _buildDateSegment(
                label: '시작일',
                date: _formatDate(_startDate),
                isStart: true,
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
              child: _buildDateSegment(
                label: '종료일',
                date: _formatDate(_endDate),
                isStart: false,
                labelStyle: labelStyle,
                dateStyle: dateStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSegment({
    required String label,
    required String date,
    required bool isStart,
    required TextStyle labelStyle,
    required TextStyle dateStyle,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectDate(isStart),
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

  static const TextStyle _headerStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    fontSize: 12,
    height: 1.35,
  );

  static const TextStyle _cellStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  Widget _buildTableHeader({
    bool selectionMode = false,
  }) {
    const headerRowHeight = 34.0;
    const pad = 6.0;

    List<Widget> cells(List<String> labels, List<int> flexes) {
      final w = <Widget>[];
      for (var i = 0; i < labels.length; i++) {
        if (i > 0) w.add(const SizedBox(width: 4));
        w.add(
          Expanded(
            flex: flexes[i],
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
                    const EdgeInsets.symmetric(horizontal: pad, vertical: 6),
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, 0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i],
                        style: _headerStyle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return w;
    }

    const labels = ['내용', '예약 시간', '종료 시간', '예약자'];
    const flexes = [3, 3, 3, 2];

    return SizedBox(
      height: headerRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
          ...cells(labels, flexes),
        ],
      ),
    );
  }

  Widget _buildReservationPage(
    List<_BoardReservationRow> rows, {
    required int pageIndex,
    required int itemsPerPage,
    required bool selectionMode,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggleRow,
  }) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '예약 내역이 없습니다',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < rows.length; i++)
          _buildReservationRow(
            rows[i],
            selectionMode: selectionMode,
            selected: selectedIndices.contains(pageIndex * itemsPerPage + i),
            onToggle: () => onToggleRow(pageIndex * itemsPerPage + i),
          ),
      ],
    );
  }

  Widget _buildReservationRow(
    _BoardReservationRow r, {
    required bool selectionMode,
    required bool selected,
    required VoidCallback onToggle,
  }) {
    const padContent = 6.0;
    const padTime = 4.0;
    const padPerson = 4.0;

    final rowStyle = r.completed
        ? _cellStyle.copyWith(
            color: Colors.white.withOpacity(0.42),
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.white54,
          )
        : _cellStyle;

    Widget fittedCell(String text) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: rowStyle,
          ),
        ),
      );
    }

    return Padding(
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
                      value: selected,
                      onChanged: (_) => onToggle(),
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
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padContent),
              child: Text(
                r.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: rowStyle,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padTime),
              child: Center(
                child: Text(
                  r.start,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: rowStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padTime),
              child: Center(
                child: Text(
                  _displayEndColumn(r),
                  maxLines: 2,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: rowStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padPerson),
              child: fittedCell(r.person),
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
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    void goNext() {
      if (currentIndex >= pageCount - 1) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    final canPrev = pageCount > 1 && currentIndex > 0;
    final canNext = pageCount > 1 && currentIndex < pageCount - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleArrow(Icons.chevron_left, enabled: canPrev, onTap: goPrev),
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
        _circleArrow(Icons.chevron_right, enabled: canNext, onTap: goNext),
      ],
    );
  }

  Widget _circleArrow(
    IconData icon, {
    required bool enabled,
    VoidCallback? onTap,
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
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationTableToolbar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: _reservationSelectionMode
              ? '선택 종료'
              : '여러 항목 선택 후 이용완료·삭제',
          child: _circleArrow(
            _reservationSelectionMode
                ? Icons.close_rounded
                : Icons.playlist_add_check_rounded,
            enabled: true,
            onTap: _reservationSelectionMode
                ? _exitReservationSelectionMode
                : _enterReservationSelectionMode,
          ),
        ),
        if (_reservationSelectionMode)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildSelectionActionChip('전체선택', _selectAllReservations),
                  const SizedBox(width: 6),
                  _buildSelectionActionChip(
                    '이용완료',
                    _markSelectedReservationsCompleted,
                  ),
                  const SizedBox(width: 6),
                  _buildSelectionActionChip('삭제', _deleteSelectedReservations),
                ],
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }

  Widget _buildSelectionActionChip(String label, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withOpacity(0.12),
        highlightColor: Colors.white.withOpacity(0.06),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
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
                  fontSize: 11,
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

  void _enterReservationSelectionMode() {
    setState(() {
      _reservationSelectionMode = true;
      _selectedReservationIndices.clear();
    });
  }

  void _exitReservationSelectionMode() {
    setState(() {
      _reservationSelectionMode = false;
      _selectedReservationIndices.clear();
    });
  }

  void _toggleReservationRowSelection(int globalIndex) {
    setState(() {
      if (_selectedReservationIndices.contains(globalIndex)) {
        _selectedReservationIndices.remove(globalIndex);
      } else {
        _selectedReservationIndices.add(globalIndex);
      }
    });
  }

  void _selectAllReservations() {
    setState(() {
      _selectedReservationIndices.clear();
      for (var i = 0; i < _reservationRows.length; i++) {
        _selectedReservationIndices.add(i);
      }
    });
  }

  void _clampPageIndex() {
    final pages = _paginateRows(_reservationRows, _itemsPerPage);
    final maxP = pages.isEmpty ? 0 : pages.length - 1;
    if (_pageIndex > maxP) {
      _pageIndex = maxP;
    }
    if (_pageIndex < 0) _pageIndex = 0;
  }

  Future<void> _deleteSelectedReservations() async {
    if (_selectedReservationIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 항목을 선택해주세요.')),
      );
      return;
    }
    final count = _selectedReservationIndices.length;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('삭제', style: TextStyle(color: Colors.white)),
        content: Text(
          '선택한 $count개 예약을 삭제할까요?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );

    if (useDummy) {
      final sorted = _selectedReservationIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      setState(() {
        final next = List<_BoardReservationRow>.from(_reservationRows);
        for (final i in sorted) {
          if (i >= 0 && i < next.length) {
            next.removeAt(i);
          }
        }
        _reservationRows = next;
        _reservationSelectionMode = false;
        _selectedReservationIndices.clear();
        _clampPageIndex();
      });
      _schedulePageJump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count개 예약을 삭제했습니다.')),
        );
      }
      return;
    }

    final ids = <int>{};
    for (final i in _selectedReservationIndices) {
      if (i < 0 || i >= _reservationRows.length) continue;
      final id = _reservationRows[i].reservationId;
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제할 서버 예약이 선택되지 않았습니다.')),
      );
      return;
    }

    try {
      await ReservationsService().deleteReservations(ids.toList());
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : '예약 삭제에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    if (!mounted) return;
    setState(() {
      _reservationSelectionMode = false;
      _selectedReservationIndices.clear();
    });
    await _loadReservationsListOnly();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ids.length}개 예약을 삭제했습니다.')),
    );
  }

  void _markSelectedReservationsCompleted() {
    if (_selectedReservationIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 항목을 선택해주세요.')),
      );
      return;
    }
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    setState(() {
      if (useDummy) {
        final next = List<_BoardReservationRow>.from(_reservationRows);
        for (final i in _selectedReservationIndices) {
          if (i >= 0 && i < next.length) {
            final r = next[i];
            next[i] = _BoardReservationRow(
              r.content,
              r.start,
              r.end,
              r.person,
              completed: true,
              itemId: r.itemId,
              isCatalogRow: r.isCatalogRow,
              reservationId: r.reservationId,
              slotStart: r.slotStart,
              slotEnd: r.slotEnd,
            );
          }
        }
        _reservationRows = next;
      } else {
        final next = List<_BoardReservationRow>.from(_reservationRows);
        for (final i in _selectedReservationIndices) {
          if (i < 0 || i >= next.length) continue;
          final r = next[i];
          next[i] = _BoardReservationRow(
            r.content,
            r.start,
            r.end,
            r.person,
            completed: true,
            itemId: r.itemId,
            isCatalogRow: r.isCatalogRow,
            reservationId: r.reservationId,
            slotStart: r.slotStart,
            slotEnd: r.slotEnd,
          );
        }
        _reservationRows = next;
      }
      _reservationSelectionMode = false;
      _selectedReservationIndices.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('선택한 예약을 이용완료로 표시했습니다.')),
    );
  }

  Future<void> _showReservationModal() async {
    final auth = context.read<AuthProvider>();
    final reserver = _reserverDisplayName(auth);

    if (!mounted) return;
    final useDummy = usePartitionDummyData(auth.isAuthenticated);
    final outcome = await showDialog<_ReservationFormDialogOutcome>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => _ReservationFormDialog(
        reserverDisplayName: reserver,
        useDummyData: useDummy,
        onOpenReservationItemManage:
            useDummy ? null : _showReservationItemManageDialog,
      ),
    );

    if (!mounted) return;
    if (useDummy) {
      final row = outcome?.dummyRow;
      if (row == null) return;
      final fixedPerson = _reserverDisplayName(context.read<AuthProvider>());
      final fixedRow = _BoardReservationRow(
        row.content,
        row.start,
        row.end,
        fixedPerson,
        completed: row.completed,
        itemId: row.itemId,
        isCatalogRow: row.isCatalogRow,
        reservationId: row.reservationId,
        slotStart: row.slotStart,
        slotEnd: row.slotEnd,
      );
      setState(() {
        _reservationRows = [..._reservationRows, fixedRow];
        _clampPageIndex();
        final pages = _paginateRows(_reservationRows, _itemsPerPage);
        _pageIndex = pages.isEmpty ? 0 : pages.length - 1;
      });
      _schedulePageJump();
      return;
    }

    if (outcome?.serverBookingCreated == true) {
      await _loadReservationsListOnly();
      if (!mounted) return;
      setState(() {
        _clampPageIndex();
        final pages = _paginateRows(_reservationRows, _itemsPerPage);
        _pageIndex = pages.isEmpty ? 0 : pages.length - 1;
      });
      _schedulePageJump();
    }
  }

  /// 예약 물품 추가/수정 다이얼로그 — API (`POST`·`PATCH /api/reservations/items`)
  Future<void> _showReservationItemManageDialog() async {
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
    );
    if (useDummy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 연결 시 사용 가능한 기능입니다.')),
      );
      return;
    }
    final catalogItems = _catalogFromApi
        .where((r) => r.isCatalogRow && r.itemId != null)
        .map((r) => ReservationItem(itemId: r.itemId!, name: r.content))
        .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) =>
          _ReservationItemManageDialog(initialItems: catalogItems),
    );
    if (mounted) {
      await _loadReservationBoardSources();
    }
  }

  List<Widget> _buildActionButtons() {
    return [
      PrimaryButton(
        label: '예약하기',
        enabled: !_reservationSelectionMode,
        onPressed: _showReservationModal,
      ),
      const SizedBox(height: 10),
      PrimaryButton(
        label: '예약 물품 추가/수정하기',
        enabled: !_reservationSelectionMode,
        onPressed: _showReservationItemManageDialog,
      ),
    ];
  }
}

/// 예약 추가 — 공용소비 내역 모달과 동일 폭·글래스 톤, 콘텐츠 높이에 맞춤
///
/// **예약자(예약하는 사람)**는 [reserverDisplayName]으로만 기록한다. (현재 로그인 계정 고정)
///
/// 실서버: `POST /api/reservations` — 물품은 [ReservationItemsService] 목록에서 선택(리스트 UI).
class _ReservationFormDialog extends StatefulWidget {
  final String reserverDisplayName;
  final bool useDummyData;
  /// 실서버: 예약 물품 추가/수정 다이얼로그(게시판과 동일). 닫힌 뒤 목록을 다시 불러온다.
  final Future<void> Function()? onOpenReservationItemManage;

  const _ReservationFormDialog({
    required this.reserverDisplayName,
    required this.useDummyData,
    this.onOpenReservationItemManage,
  });

  @override
  State<_ReservationFormDialog> createState() => _ReservationFormDialogState();
}

class _ReservationFormDialogState extends State<_ReservationFormDialog> {
  late final TextEditingController _nameCtrl;
  late DateTime _start;
  late DateTime _end;
  final ReservationItemsService _reservationItemsService =
      ReservationItemsService();
  final ReservationsService _reservationsService = ReservationsService();

  List<ReservationItem> _items = [];
  bool _itemsLoading = false;
  int? _selectedItemId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    final n = DateTime.now();
    final m = (n.minute ~/ 30) * 30;
    _start = DateTime(n.year, n.month, n.day, n.hour, m);
    _end = _start.add(const Duration(hours: 1));
    if (!widget.useDummyData) {
      _loadReservationItems();
    }
  }

  Future<void> _loadReservationItems() async {
    setState(() => _itemsLoading = true);
    try {
      final list = await _reservationItemsService.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = list;
        _itemsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _itemsLoading = false;
      });
    }
  }

  Future<void> _openReservationItemManage() async {
    final open = widget.onOpenReservationItemManage;
    if (open == null) return;
    await open();
    if (mounted) await _loadReservationItems();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _formatField(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}. '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 표 셀용 짧은 문자열
  String _formatTableCell(DateTime d) {
    return '${d.month}.${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 365));
    var init = initial;
    if (init.isBefore(today)) init = today;

    final date = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => GlassmorphicDatePicker(
        initialDate: init,
        firstDate: today,
        lastDate: maxDate,
        isStartDate: true,
      ),
    );
    if (!mounted || date == null) return null;

    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Color(0xFF2C2C2E),
              hourMinuteTextColor: Colors.white,
              dialTextColor: Colors.white,
            ),
            colorScheme: const ColorScheme.dark(
              primary: Colors.white70,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || tod == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      tod.hour,
      tod.minute,
    );
  }

  Future<void> _pickStart() async {
    final d = await _pickDateTime(_start);
    if (d != null) {
      setState(() {
        _start = d;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(minutes: 30));
        }
      });
    }
  }

  Future<void> _pickEnd() async {
    final base = _end.isAfter(_start) ? _end : _start.add(const Duration(minutes: 30));
    final d = await _pickDateTime(base);
    if (d != null) {
      setState(() => _end = d);
    }
  }

  Future<void> _submit() async {
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 시간이 시작 시간보다 이후여야 합니다.')),
      );
      return;
    }

    if (widget.useDummyData) {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('예약 물품·공간 이름을 입력해 주세요.')),
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        _ReservationFormDialogOutcome.dummy(
          _BoardReservationRow(
            name,
            _formatTableCell(_start),
            _formatTableCell(_end),
            widget.reserverDisplayName,
            slotStart: _start,
            slotEnd: _end,
          ),
        ),
      );
      return;
    }

    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약할 물품을 목록에서 선택해 주세요.')),
      );
      return;
    }
    ReservationItem? match;
    for (final e in _items) {
      if (e.itemId == _selectedItemId) {
        match = e;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목록에서 예약 대상을 선택해 주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _reservationsService.createReservation(
        itemId: match.itemId,
        startTime: _start,
        endTime: _end,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약이 등록되었습니다.')),
      );
      Navigator.of(context).pop(_ReservationFormDialogOutcome.serverSuccess());
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e is ApiException ? e.message : '예약 등록에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    // 공용소비 모달 기준 폭에 약 +20% — 날짜·시간 칸(Expanded)이 함께 넓어짐
    final baseW = (screenW - 40).clamp(300.0, 350.0);
    final dialogW = (baseW * 1.2).clamp(320.0, 420.0);
    final btnW = (dialogW - 16).clamp(280.0, 404.0);

    final fieldStyle = TextStyle(
      color: Colors.white.withOpacity(0.95),
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFamily: 'Pretendard Variable',
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog(
        constraints: BoxConstraints(
          maxWidth: dialogW,
          minWidth: dialogW,
        ),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        borderColor: Colors.white.withOpacity(0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text(
                        '예약하기',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '예약할 대상과 시간을 설정하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 12,
                      fontFamily: 'Pretendard Variable',
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!widget.useDummyData) ...[
                    if (_itemsLoading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ),
                      ),
                    FrostedPanel(
                      borderRadius: BorderRadius.circular(20),
                      backgroundOpacity: 0.1,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: _items.isEmpty && !_itemsLoading
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '등록된 예약 물품이 없습니다.\n아래 + 버튼으로 등록해 주세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontSize: 12,
                                  height: 1.35,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                            )
                          : SizedBox(
                              height: 200,
                              child: ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.white.withOpacity(0.12),
                                ),
                                itemBuilder: (context, i) {
                                  final e = _items[i];
                                  final sel = _selectedItemId == e.itemId;
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setState(
                                        () => _selectedItemId = e.itemId,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              sel
                                                  ? Icons.radio_button_checked
                                                  : Icons.radio_button_off,
                                              size: 20,
                                              color: sel
                                                  ? Colors.white
                                                  : Colors.white
                                                      .withOpacity(0.45),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                e.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: fieldStyle.copyWith(
                                                  fontWeight: sel
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '예약 대상 물품 추가',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: widget.onOpenReservationItemManage == null
                                  ? null
                                  : _openReservationItemManage,
                              customBorder: const CircleBorder(),
                              child: Opacity(
                                opacity:
                                    widget.onOpenReservationItemManage == null
                                        ? 0.35
                                        : 1,
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
                                    Icons.add_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (widget.useDummyData) ...[
                  FrostedPanel(
                    borderRadius: BorderRadius.circular(20),
                    backgroundOpacity: 0.1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: TextField(
                      controller: _nameCtrl,
                      style: fieldStyle,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: '예: 욕실, TV, 세탁기',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 13,
                          fontFamily: 'Pretendard Variable',
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _pickStart,
                            borderRadius: BorderRadius.circular(18),
                            child: FrostedPanel(
                              borderRadius: BorderRadius.circular(18),
                              backgroundOpacity: 0.1,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Center(
                                  child: Text(
                                    _formatField(_start),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: fieldStyle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '~',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _pickEnd,
                            borderRadius: BorderRadius.circular(18),
                            child: FrostedPanel(
                              borderRadius: BorderRadius.circular(18),
                              backgroundOpacity: 0.1,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Center(
                                  child: Text(
                                    _formatField(_end),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: fieldStyle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: PrimaryButton(
                      label: _submitting ? '등록 중…' : '예약하기',
                      width: btnW,
                      enabled: !_submitting,
                      onPressed: () => _submit(),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 예약 물품 추가(POST) / 수정(PATCH) 통합 다이얼로그
///
/// - 추가 탭: 이름 입력 → `POST /api/reservations/items`
/// - 수정 탭: 목록에서 선택 후 이름 변경 → `PATCH /api/reservations/items/{itemId}`
class _ReservationItemManageDialog extends StatefulWidget {
  final List<ReservationItem> initialItems;

  const _ReservationItemManageDialog({required this.initialItems});

  @override
  State<_ReservationItemManageDialog> createState() =>
      _ReservationItemManageDialogState();
}

class _ReservationItemManageDialogState
    extends State<_ReservationItemManageDialog> {
  static const double _kNameFieldHeight = 46;
  int _modeIndex = 0; // 0 = 추가, 1 = 수정
  late List<ReservationItem> _items;
  final TextEditingController _addNameCtrl = TextEditingController();
  final TextEditingController _editNameCtrl = TextEditingController();
  int? _selectedEditItemId;
  final ReservationItemsService _service = ReservationItemsService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    if (_items.isNotEmpty) {
      _selectedEditItemId = _items.first.itemId;
      _editNameCtrl.text = _items.first.name;
    }
  }

  @override
  void dispose() {
    _addNameCtrl.dispose();
    _editNameCtrl.dispose();
    super.dispose();
  }

  void _syncEditFieldToSelection() {
    final item = _items.firstWhere(
      (e) => e.itemId == _selectedEditItemId,
      orElse: () => _items.first,
    );
    _editNameCtrl.text = item.name;
    _editNameCtrl.selection =
        TextSelection.collapsed(offset: _editNameCtrl.text.length);
  }

  Future<void> _addItem() async {
    final name = _addNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('추가할 물품 이름을 입력해주세요.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final created = await _service.createItem(name);
      if (!mounted) return;
      final newItem = ReservationItem(itemId: created.itemId, name: created.name);
      setState(() {
        _items = [..._items, newItem];
        _addNameCtrl.clear();
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'${created.name}'이(가) 추가되었습니다.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e is ApiException ? e.message : '물품 추가에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _editItem() async {
    if (_selectedEditItemId == null) return;
    final name = _editNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수정할 이름을 입력해주세요.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final updated = await _service.updateItem(_selectedEditItemId!, name);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (e) => e.itemId == _selectedEditItemId
                  ? ReservationItem(itemId: e.itemId, name: updated.name)
                  : e,
            )
            .toList();
        _editNameCtrl.text = updated.name;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'${updated.name}'으로 수정되었습니다.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e is ApiException ? e.message : '물품 수정에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final baseW = (screenW - 40).clamp(300.0, 350.0);
    final dialogW = (baseW * 1.2).clamp(320.0, 420.0);
    final btnW = (dialogW - 16).clamp(280.0, 404.0);

    final fieldStyle = TextStyle(
      color: Colors.white.withOpacity(0.95),
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFamily: 'Pretendard Variable',
    );

    final isAdd = _modeIndex == 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog(
        constraints: BoxConstraints(maxWidth: dialogW, minWidth: dialogW),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        borderColor: Colors.white.withOpacity(0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    '예약 물품 추가/수정',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  Positioned(
                    right: -8,
                    top: -8,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isAdd
                    ? '예약할 물품을 새로 등록하세요.'
                    : '등록된 물품 이름을 수정하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  fontFamily: 'Pretendard Variable',
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTab('추가', 0),
                        _buildTab('수정', 1),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isAdd) ...[
                FrostedPanel(
                  borderRadius: BorderRadius.circular(20),
                  backgroundOpacity: 0.1,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  child: SizedBox(
                    height: _kNameFieldHeight,
                    child: TextField(
                      controller: _addNameCtrl,
                      style: fieldStyle,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: '새 예약 물품 이름 (예: 욕실, 세탁기)',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 13,
                          fontFamily: 'Pretendard Variable',
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  )
                else
                  Center(
                    child: PrimaryButton(
                      label: '추가하기',
                      width: btnW,
                      onPressed: _addItem,
                    ),
                  ),
              ] else ...[
                if (_items.isEmpty)
                  FrostedPanel(
                    borderRadius: BorderRadius.circular(20),
                    backgroundOpacity: 0.1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      '등록된 예약 물품이 없습니다.\n먼저 추가 탭에서 물품을 등록해주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontFamily: 'Pretendard Variable',
                        height: 1.45,
                      ),
                    ),
                  )
                else ...[
                  FrostedPanel(
                    borderRadius: BorderRadius.circular(20),
                    backgroundOpacity: 0.1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int>(
                      value: _selectedEditItemId,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3A3A3C),
                      iconEnabledColor: Colors.white70,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: fieldStyle,
                      items: _items
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e.itemId,
                              child: Text(
                                e.name,
                                overflow: TextOverflow.ellipsis,
                                style: fieldStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _selectedEditItemId = id;
                          _syncEditFieldToSelection();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  FrostedPanel(
                    borderRadius: BorderRadius.circular(20),
                    backgroundOpacity: 0.1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    child: SizedBox(
                      height: _kNameFieldHeight,
                      child: TextField(
                        controller: _editNameCtrl,
                        style: fieldStyle,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: '수정할 이름',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 13,
                            fontFamily: 'Pretendard Variable',
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: PrimaryButton(
                        label: '수정하기',
                        width: btnW,
                        onPressed: _editItem,
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final selected = _modeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_modeIndex == index) return;
          setState(() => _modeIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? Colors.white.withOpacity(0.22)
                : Colors.transparent,
            border: selected
                ? Border.all(color: Colors.white.withOpacity(0.2), width: 0.5)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withOpacity(0.5),
              fontSize: 13,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ),
      ),
    );
  }
}
