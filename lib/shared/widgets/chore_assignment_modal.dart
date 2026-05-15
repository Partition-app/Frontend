import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/partition/services/chore_service.dart';
import 'package:partition_app/features/partition/services/calendar_service.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 집안일 자동 배정 모달
class ChoreAssignmentModal extends StatefulWidget {
  final VoidCallback? onSuccess; // 배정 성공 시 호출될 콜백

  const ChoreAssignmentModal({
    super.key,
    this.onSuccess,
  });

  @override
  State<ChoreAssignmentModal> createState() => _ChoreAssignmentModalState();
}

class _ChoreAssignmentModalState extends State<ChoreAssignmentModal> {
  static const double _kModalMinHeight = 460;
  static const double _kModalMaxHeight = 620;
  static const int _kCalendarColumns = 7;
  static const double _kCalendarCellGap = 4;

  final Set<String> _selectedChores = {};
  final Set<DateTime> _selectedDates = {};
  late DateTime _visibleMonth;
  final ChoreService _choreService = ChoreService();
  final CalendarService _calendarService = CalendarService();
  bool _isLoading = false;
  bool _isDraggingDates = false;
  bool? _dragSelectMode;
  DateTime? _lastDraggedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDates.add(today);
  }

  final List<String> _allChores = [
    '설거지',
    '요리',
    '빨래',
    '음식물 쓰레기 버리기',
    '분리수거',
    '청소기 돌리기',
    '바닥 닦기',
    '창문, 창틀 닦기',
    '화장실 청소',
    '냉장고 청소',
  ];

  /// 집안일 이름을 API enum 값으로 변환
  /// 프론트엔드 한국어 이름 -> 서버 enum 값
  List<String> _convertChoreNamesToEnum(List<String> choreNames) {
    // 집안일 이름 매핑 (프론트엔드 이름 -> API enum 값)
    final nameMapping = {
      '설거지': 'DISH_WASHING',
      '요리': 'COOKING',
      '빨래': 'LAUNDRY',
      '음식물 쓰레기 버리기': 'FOODTRASH',
      '분리수거': 'RECYCLING',
      '청소기 돌리기': 'VACUUM',
      '바닥 닦기': 'MOPPING',
      '창문, 창틀 닦기': 'WINDOW',
      '화장실 청소': 'BATHROOM',
      '냉장고 청소': 'FRIDGE',
    };

    return choreNames.map((name) => nameMapping[name] ?? name).toList();
  }

  /// API enum 값에서 집안일 이름으로 역변환
  /// 서버 enum 값 -> 프론트엔드 한국어 이름
  String _convertEnumToChoreName(String enumValue) {
    final enumMapping = {
      'DISH_WASHING': '설거지',
      'COOKING': '요리',
      'LAUNDRY': '빨래',
      'FOODTRASH': '음식물 쓰레기 버리기',
      'RECYCLING': '분리수거',
      'VACUUM': '청소기 돌리기',
      'MOPPING': '바닥 닦기',
      'WINDOW': '창문, 창틀 닦기',
      'BATHROOM': '화장실 청소',
      'FRIDGE': '냉장고 청소',
    };

    return enumMapping[enumValue] ?? enumValue;
  }

  /// 날짜 범위 내에 이미 배정된 집안일이 있는지 확인
  /// 반환: (중복 여부, 중복된 집안일 이름, 중복된 날짜)
  Future<Map<String, dynamic>?> _checkDuplicateChores(
    List<String> choreTypes,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // 날짜 범위 내의 모든 날짜 확인
      DateTime currentDate = startDate;
      while (!currentDate.isAfter(endDate)) {
        final dateString = _formatDateForApi(currentDate);

        // 해당 날짜의 일간 캘린더 조회
        final response =
            await _calendarService.getDailyCalendar(date: dateString);

        if (response.isSuccess && response.result != null) {
          // CHORE 카테고리 아이템만 필터링
          final existingChores = response.result!
              .where((item) => item.category.trim().toUpperCase() == 'CHORE')
              .toList();

          // 선택된 집안일과 중복 확인
          for (final choreType in choreTypes) {
            final choreName = _convertEnumToChoreName(choreType);

            // 이미 배정된 집안일 중에서 같은 이름이 있는지 확인
            for (final existingChore in existingChores) {
              // title에 집안일 이름이 포함되어 있는지 확인 (예: "빨래 하기", "빨래" 등)
              if (existingChore.title.contains(choreName) ||
                  choreName.contains(existingChore.title.split(' ').first)) {
                return {
                  'hasDuplicate': true,
                  'choreName': choreName,
                  'date': dateString,
                };
              }
            }
          }
        }

        // 다음 날짜로 이동
        currentDate = currentDate.add(const Duration(days: 1));
      }

      return null; // 중복 없음
    } catch (e) {
      // 에러 발생 시 체크 실패로 간주하고 진행
      debugPrint('중복 체크 실패: $e');
      return null;
    }
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _lastSelectableDate => _today.add(const Duration(days: 14));

  bool _isDateSelectable(DateTime date) {
    final normalized = _dateOnly(date);
    return !normalized.isBefore(_today) &&
        !normalized.isAfter(_lastSelectableDate);
  }

  bool _isVisibleMonthDateSelectable(DateTime date) {
    final normalized = _dateOnly(date);
    final isVisibleMonth = normalized.year == _visibleMonth.year &&
        normalized.month == _visibleMonth.month;
    return isVisibleMonth && _isDateSelectable(normalized);
  }

  bool _isDateSelected(DateTime date) =>
      _selectedDates.contains(_dateOnly(date));

  bool _canGoPreviousMonth() {
    final previousMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    final firstMonth = DateTime(_today.year, _today.month);
    return !previousMonth.isBefore(firstMonth);
  }

  bool _canGoNextMonth() {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    final lastMonth = DateTime(
      _lastSelectableDate.year,
      _lastSelectableDate.month,
    );
    return !nextMonth.isAfter(lastMonth);
  }

  void _goToPreviousMonth() {
    if (!_canGoPreviousMonth()) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    if (!_canGoNextMonth()) return;
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  List<DateTime> _getVisibleCalendarDays() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final lastDay = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final leadingDays = firstDay.weekday % 7;
    final totalVisibleDays = leadingDays + lastDay.day;
    final totalCells = totalVisibleDays <= 35 ? 35 : 42;

    return List<DateTime>.generate(totalCells, (index) {
      return firstDay.subtract(Duration(days: leadingDays - index));
    });
  }

  String _monthYearLabel(DateTime date) => '${date.year}년 ${date.month}월';

  void _toggleSingleDate(DateTime date) {
    final normalized = _dateOnly(date);
    if (!_isVisibleMonthDateSelectable(normalized)) return;

    setState(() {
      if (_selectedDates.contains(normalized)) {
        _selectedDates.remove(normalized);
      } else {
        _selectedDates.add(normalized);
      }
    });
  }

  void _applyDateSelection(DateTime date, bool shouldSelect) {
    final normalized = _dateOnly(date);
    if (!_isDateSelectable(normalized)) return;

    if (shouldSelect) {
      _selectedDates.add(normalized);
    } else {
      _selectedDates.remove(normalized);
    }
  }

  Iterable<DateTime> _iterateInclusiveDates(
      DateTime start, DateTime end) sync* {
    DateTime cursor = _dateOnly(start);
    final target = _dateOnly(end);
    final step = cursor.isAfter(target) ? -1 : 1;

    while (true) {
      yield cursor;
      if (_isSameDate(cursor, target)) break;
      cursor = cursor.add(Duration(days: step));
    }
  }

  void _handleDragSelectionAt(DateTime date) {
    final normalized = _dateOnly(date);
    if (!_isVisibleMonthDateSelectable(normalized)) return;

    setState(() {
      final shouldSelect =
          _dragSelectMode ?? !_selectedDates.contains(normalized);
      if (_lastDraggedDate == null) {
        _dragSelectMode = shouldSelect;
        _applyDateSelection(normalized, shouldSelect);
        _lastDraggedDate = normalized;
        return;
      }

      for (final day in _iterateInclusiveDates(_lastDraggedDate!, normalized)) {
        _applyDateSelection(day, shouldSelect);
      }
      _lastDraggedDate = normalized;
    });
  }

  void _startDateDrag(DateTime date) {
    _isDraggingDates = true;
    _dragSelectMode = !_isDateSelected(date);
    _lastDraggedDate = null;
    _handleDragSelectionAt(date);
  }

  void _updateDateDrag(DateTime date) {
    if (!_isDraggingDates) return;
    if (_lastDraggedDate != null && _isSameDate(_lastDraggedDate!, date)) {
      return;
    }
    _handleDragSelectionAt(date);
  }

  void _endDateDrag() {
    _isDraggingDates = false;
    _dragSelectMode = null;
    _lastDraggedDate = null;
  }

  List<DateTimeRange> _buildSelectedRanges() {
    if (_selectedDates.isEmpty) return const [];

    final sortedDates = _selectedDates.toList()..sort((a, b) => a.compareTo(b));

    final ranges = <DateTimeRange>[];
    DateTime rangeStart = sortedDates.first;
    DateTime rangeEnd = sortedDates.first;

    for (final date in sortedDates.skip(1)) {
      final nextExpected = rangeEnd.add(const Duration(days: 1));
      if (_isSameDate(date, nextExpected)) {
        rangeEnd = date;
        continue;
      }

      ranges.add(DateTimeRange(start: rangeStart, end: rangeEnd));
      rangeStart = date;
      rangeEnd = date;
    }

    ranges.add(DateTimeRange(start: rangeStart, end: rangeEnd));
    return ranges;
  }

  String get _selectedChoresSummary {
    final selected = _allChores.where(_selectedChores.contains).toList();
    if (selected.isEmpty) return '집안일 선택';
    return selected.join(', ');
  }

  Future<void> _openChorePicker() async {
    final picked = await showDialog<Set<String>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => _ChoreSelectionDialog(
        allChores: _allChores,
        initialSelected: _selectedChores,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedChores
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _handleAutoAssign() async {
    if (_isLoading) return;

    // 선택된 집안일이 없으면 경고
    if (_selectedChores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('배정할 집안일을 선택해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('배정할 날짜를 선택해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final selectedChoresList = _selectedChores.toList();
      final selectedRanges = _buildSelectedRanges();

      // 집안일 이름을 API enum 값으로 변환
      final choreTypes = _convertChoreNamesToEnum(selectedChoresList);

      // 중복 여부 확인 (첫 번째 중복만 감지해서 한 번에 물어봄)
      Map<String, dynamic>? firstDuplicate;
      for (final range in selectedRanges) {
        final duplicateCheck = await _checkDuplicateChores(
          choreTypes,
          range.start,
          range.end,
        );
        if (duplicateCheck != null && duplicateCheck['hasDuplicate'] == true) {
          firstDuplicate = duplicateCheck;
          break;
        }
      }

      if (firstDuplicate != null) {
        setState(() {
          _isLoading = false;
        });

        final choreName = firstDuplicate['choreName'] as String;
        final date = firstDuplicate['date'] as String;

        final confirmed = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withOpacity(0.5),
          builder: (context) => PartitionGlassDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            borderRadius: BorderRadius.circular(24),
            blurSigma: 18,
            borderColor: Colors.white.withOpacity(0.22),
            gradient: const LinearGradient(
              colors: [Colors.transparent, Colors.transparent],
            ),
            boxShadow: const [],
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '기존 배정 덮어쓰기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$date에 이미\n"$choreName" 집안일이 배정되어 있어요.\n기존 배정을 지우고 새로 배정할까요?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          height: 45.327,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.actionButtonRadius,
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 0.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.actionButtonRadius,
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: const Center(
                                child: Text(
                                  '취소',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: Container(
                          height: 45.327,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.actionButtonRadius,
                            ),
                            border: Border.all(
                              color: Colors.white,
                              width: 0.5,
                            ),
                            gradient: const RadialGradient(
                              center: Alignment(-0.1212, -0.1178),
                              radius: 1.6319,
                              colors: [
                                Color.fromRGBO(255, 255, 255, 0.10),
                                Color.fromRGBO(255, 255, 255, 0.20),
                              ],
                              stops: [0.0, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.25),
                                blurRadius: 30,
                                spreadRadius: 0,
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.actionButtonRadius,
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: const Center(
                                child: Text(
                                  '덮어쓰기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        if (confirmed != true) return;

        // 덮어쓰기 확인 후 로딩 재개
        setState(() {
          _isLoading = true;
        });
      }

      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🏠 집안일 자동 배정 요청');
      debugPrint('  - 선택된 집안일 개수: ${selectedChoresList.length}');
      debugPrint('  - 선택된 집안일 목록 (원본): $selectedChoresList');
      debugPrint('  - 변환된 choreTypes (API 전송용): $choreTypes');
      debugPrint('  - 선택 날짜 개수: ${_selectedDates.length}');
      debugPrint(
        '  - 선택 구간: ${selectedRanges.map((range) => '${_formatDateForApi(range.start)} ~ ${_formatDateForApi(range.end)}').toList()}',
      );
      debugPrint('  - 전체 집안일 목록: $_allChores');
      debugPrint('═══════════════════════════════════════════════════════');

      for (final range in selectedRanges) {
        await _choreService.autoAssignChores(
          startDate: _formatDateForApi(range.start),
          endDate: _formatDateForApi(range.end),
          choreTypes: choreTypes,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop();

      // 콜백 호출하여 캘린더 갱신
      widget.onSuccess?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('집안일 자동 배정이 완료되었어요.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      String message = '집안일 자동 배정에 실패했어요.';
      if (e is ApiException) {
        message = e.message;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildSettingsStyleButton({
    required Widget child,
    required VoidCallback? onTap,
    double height = PartitionUiTokens.actionButtonHeight,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Opacity(
            opacity: onTap != null ? 1 : 0.48,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  PartitionUiTokens.actionButtonRadius,
                ),
                border: Border.all(color: PartitionUiTokens.actionButtonBorder),
                color: PartitionUiTokens.actionButtonFill,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _resolveDateFromCalendarOffset({
    required Offset localPosition,
    required Size size,
    required List<DateTime> days,
  }) {
    if (size.width <= 0 || size.height <= 0) return null;

    final rowCount = (days.length / _kCalendarColumns).ceil();
    final column =
        (localPosition.dx / (size.width / _kCalendarColumns)).floor();
    final row = (localPosition.dy / (size.height / rowCount)).floor();

    if (column < 0 ||
        column >= _kCalendarColumns ||
        row < 0 ||
        row >= rowCount) {
      return null;
    }

    final index = row * _kCalendarColumns + column;
    if (index < 0 || index >= days.length) return null;
    return days[index];
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final modalHeight =
        (screenHeight * 0.72).clamp(_kModalMinHeight, _kModalMaxHeight);
    final days = _getVisibleCalendarDays();
    final weekdays = const ['일', '월', '화', '수', '목', '금', '토'];

    return PartitionGlassDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      constraints: BoxConstraints.tightFor(
        width: 350,
        height: modalHeight,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      fillColor: const Color.fromRGBO(255, 255, 255, 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '집안일 자동 배정',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.15,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '집안일을 고른 뒤 캘린더에서\n날짜를 드래그해 선택하세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontFamily: 'Pretendard Variable',
                height: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            _buildSettingsStyleButton(
              onTap: _openChorePicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedChoresSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedChores.isEmpty
                              ? Colors.white.withOpacity(0.68)
                              : Colors.white,
                          fontSize: PartitionUiTokens.actionFontSize,
                          fontWeight: PartitionUiTokens.actionWeight,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      color: Colors.white.withOpacity(0.7),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Opacity(
                  opacity: _canGoPreviousMonth() ? 1 : 0.3,
                  child: GestureDetector(
                    onTap: _canGoPreviousMonth() ? _goToPreviousMonth : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.white.withOpacity(0.95),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                Text(
                  _monthYearLabel(_visibleMonth),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
                Opacity(
                  opacity: _canGoNextMonth() ? 1 : 0.3,
                  child: GestureDetector(
                    onTap: _canGoNextMonth() ? _goToNextMonth : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white.withOpacity(0.95),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: weekdays.map((day) {
                return Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard Variable',
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      final date = _resolveDateFromCalendarOffset(
                        localPosition: details.localPosition,
                        size: gridSize,
                        days: days,
                      );
                      if (date != null) {
                        _startDateDrag(date);
                      }
                    },
                    onPanUpdate: (details) {
                      final date = _resolveDateFromCalendarOffset(
                        localPosition: details.localPosition,
                        size: gridSize,
                        days: days,
                      );
                      if (date != null) {
                        _updateDateDrag(date);
                      }
                    },
                    onPanEnd: (_) => _endDateDrag(),
                    onPanCancel: _endDateDrag,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _kCalendarColumns,
                        mainAxisSpacing: _kCalendarCellGap,
                        crossAxisSpacing: _kCalendarCellGap,
                        childAspectRatio: constraints.maxWidth /
                            _kCalendarColumns /
                            ((constraints.maxHeight -
                                    (_kCalendarCellGap *
                                        ((days.length / _kCalendarColumns)
                                                .ceil() -
                                            1))) /
                                ((days.length / _kCalendarColumns).ceil())),
                      ),
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final date = days[index];
                        final isCurrentMonth =
                            date.year == _visibleMonth.year &&
                                date.month == _visibleMonth.month;
                        final isSelectable =
                            _isVisibleMonthDateSelectable(date);
                        final isSelected = _isDateSelected(date);
                        final isToday = _isSameDate(date, _today);

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleSingleDate(date),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : isToday
                                        ? Colors.white.withOpacity(0.42)
                                        : isSelectable
                                            ? Colors.white.withOpacity(0.08)
                                            : Colors.transparent,
                                width: isSelected ? 1 : 0.6,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : isSelectable
                                          ? Colors.white
                                          : Colors.white.withOpacity(
                                              isCurrentMonth ? 0.3 : 0.18,
                                            ),
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            _buildSettingsStyleButton(
              onTap: _isLoading ? null : _handleAutoAssign,
              child: Center(
                child: _isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.9),
                          ),
                        ),
                      )
                    : const Text(
                        '자동 배정',
                        style: TextStyle(
                          color: PartitionUiTokens.actionText,
                          fontSize: PartitionUiTokens.actionFontSize,
                          fontWeight: PartitionUiTokens.actionWeight,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoreSelectionDialog extends StatefulWidget {
  const _ChoreSelectionDialog({
    required this.allChores,
    required this.initialSelected,
  });

  final List<String> allChores;
  final Set<String> initialSelected;

  @override
  State<_ChoreSelectionDialog> createState() => _ChoreSelectionDialogState();
}

class _ChoreSelectionDialogState extends State<_ChoreSelectionDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  void _toggle(String chore) {
    setState(() {
      if (_selected.contains(chore)) {
        _selected.remove(chore);
      } else {
        _selected.add(chore);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogW = (size.width - 48).clamp(280.0, 340.0);
    final dialogH = (size.height * 0.58).clamp(320.0, 500.0);

    return PartitionGlassDialog(
      constraints: BoxConstraints.tightFor(
        width: dialogW,
        height: dialogH,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '집안일 선택',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  onPressed: () => Navigator.pop(context),
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
              itemCount: widget.allChores.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.white.withOpacity(0.08),
              ),
              itemBuilder: (context, index) {
                final chore = widget.allChores[index];
                final selected = _selected.contains(chore);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggle(chore),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              color:
                                  selected ? Colors.white : Colors.transparent,
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.black,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              chore,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontFamily: 'Pretendard Variable',
                                fontSize: 15,
                                height: 1.35,
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
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withOpacity(0.22),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context, Set<String>.from(_selected)),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    '선택 완료',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
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
}

/// 글래스모피즘 효과가 적용된 날짜 선택 다이얼로그
class _GlassmorphicDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool isStartDate;

  const _GlassmorphicDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.isStartDate,
  });

  @override
  State<_GlassmorphicDatePicker> createState() =>
      _GlassmorphicDatePickerState();
}

class _GlassmorphicDatePickerState extends State<_GlassmorphicDatePicker> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  void _previousMonth() {
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    if (!prevMonth.isBefore(firstMonth)) {
      setState(() {
        _currentMonth = prevMonth;
      });
    }
  }

  void _nextMonth() {
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (!nextMonth.isAfter(lastMonth)) {
      setState(() {
        _currentMonth = nextMonth;
      });
    }
  }

  bool _canGoPrevious() {
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    return !prevMonth.isBefore(firstMonth);
  }

  bool _canGoNext() {
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    return !nextMonth.isAfter(lastMonth);
  }

  bool _isDateSelectable(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final firstDateOnly = DateTime(
        widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final lastDateOnly = DateTime(
        widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
    return !dateOnly.isBefore(firstDateOnly) && !dateOnly.isAfter(lastDateOnly);
  }

  bool _isDateSelected(DateTime date) {
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }

  void _selectDate(DateTime date) {
    if (_isDateSelectable(date)) {
      setState(() {
        _selectedDate = DateTime(date.year, date.month, date.day);
      });
    }
  }

  String _getMonthYearText() {
    final months = [
      '1월',
      '2월',
      '3월',
      '4월',
      '5월',
      '6월',
      '7월',
      '8월',
      '9월',
      '10월',
      '11월',
      '12월'
    ];
    return '${_currentMonth.year}년 ${months[_currentMonth.month - 1]}';
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7; // 0 = 일요일, 6 = 토요일

    final days = <DateTime>[];

    // 이전 달의 마지막 날들
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }

    // 현재 달의 날들
    for (int i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, i));
    }

    // 다음 달의 첫 날들 (35개 셀을 채우기 위해 - 5주)
    final remainingDays = 35 - days.length;
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month + 1, i));
    }

    return days;
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return PartitionGlassDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints(
        maxWidth: screenWidth - 32,
        maxHeight: screenHeight * 0.45,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Opacity(
                opacity: _canGoPrevious() ? 1 : 0.3,
                child: GestureDetector(
                  onTap: _canGoPrevious() ? _previousMonth : null,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_left,
                      color: Colors.white.withOpacity(0.95),
                      size: 20,
                    ),
                  ),
                ),
              ),
              Text(
                _getMonthYearText(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Pretendard Variable',
                ),
              ),
              Opacity(
                opacity: _canGoNext() ? 1 : 0.3,
                child: GestureDetector(
                  onTap: _canGoNext() ? _nextMonth : null,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: Colors.white.withOpacity(0.95),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 요일 헤더
          Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 날짜 그리드
          Expanded(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.2,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: 35,
              itemBuilder: (context, index) {
                final date = days[index];
                final isCurrentMonth = date.month == _currentMonth.month;
                final isSelectable = _isDateSelectable(date);
                final isSelected = _isDateSelected(date);
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return GestureDetector(
                  onTap: () => _selectDate(date),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    child: isSelected
                        ? Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: isToday
                                  ? Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: isCurrentMonth && isSelectable
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Pretendard Variable',
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(_selectedDate),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(
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
        ],
      ),
    );
  }
}
