import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/partition/services/chore_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/chore_assignment_common.dart';
import 'package:partition_app/shared/widgets/chore_member_select_dialog.dart';
import 'package:partition_app/shared/widgets/chore_multi_select_dialog.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 집안일 직접 배정 모달 (AI 배정 모달과 동일 글래스 톤)
class ChoreManualAssignmentModal extends StatefulWidget {
  final VoidCallback? onSuccess;

  const ChoreManualAssignmentModal({
    super.key,
    this.onSuccess,
  });

  @override
  State<ChoreManualAssignmentModal> createState() =>
      _ChoreManualAssignmentModalState();
}

class _ChoreManualAssignmentModalState extends State<ChoreManualAssignmentModal> {
  static const double _kModalMinHeight = 500;
  static const double _kModalMaxHeight = 660;
  static const int _kCalendarColumns = 7;
  static const double _kCalendarCellGap = 4;

  final Set<String> _selectedChores = {};
  final Set<DateTime> _selectedDates = {};
  late DateTime _visibleMonth;
  final ChoreService _choreService = ChoreService();
  final AuthService _authService = AuthService();

  List<HouseholdMemberBrief> _members = [];
  HouseholdMemberBrief? _selectedMember;
  bool _isLoading = false;
  bool _isLoadingMembers = true;
  bool _isDraggingDates = false;
  bool? _dragSelectMode;
  DateTime? _lastDraggedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = choreDateOnly(now);
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDates.add(today);
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await _authService.fetchHouseholdMembers();
      final myIdStr = await StorageService.getUserId();
      final myId = int.tryParse(myIdStr ?? '');
      HouseholdMemberBrief? initial;
      if (myId != null) {
        for (final m in members) {
          if (m.userId == myId) {
            initial = m;
            break;
          }
        }
      }
      initial ??= members.isNotEmpty ? members.first : null;
      if (!mounted) return;
      setState(() {
        _members = members;
        _selectedMember = initial;
        _isLoadingMembers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMembers = false);
    }
  }

  DateTime get _today {
    final now = DateTime.now();
    return choreDateOnly(now);
  }

  DateTime get _lastSelectableDate => _today.add(const Duration(days: 14));

  bool _isDateSelectable(DateTime date) {
    final normalized = choreDateOnly(date);
    return !normalized.isBefore(_today) &&
        !normalized.isAfter(_lastSelectableDate);
  }

  bool _isVisibleMonthDateSelectable(DateTime date) {
    final normalized = choreDateOnly(date);
    final isVisibleMonth = normalized.year == _visibleMonth.year &&
        normalized.month == _visibleMonth.month;
    return isVisibleMonth && _isDateSelectable(normalized);
  }

  bool _isDateSelected(DateTime date) =>
      _selectedDates.contains(choreDateOnly(date));

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
    final normalized = choreDateOnly(date);
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
    final normalized = choreDateOnly(date);
    if (!_isDateSelectable(normalized)) return;

    if (shouldSelect) {
      _selectedDates.add(normalized);
    } else {
      _selectedDates.remove(normalized);
    }
  }

  Iterable<DateTime> _iterateInclusiveDates(
      DateTime start, DateTime end) sync* {
    DateTime cursor = choreDateOnly(start);
    final target = choreDateOnly(end);
    final step = cursor.isAfter(target) ? -1 : 1;

    while (true) {
      yield cursor;
      if (choreIsSameDate(cursor, target)) break;
      cursor = cursor.add(Duration(days: step));
    }
  }

  void _handleDragSelectionAt(DateTime date) {
    final normalized = choreDateOnly(date);
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
    if (_lastDraggedDate != null && choreIsSameDate(_lastDraggedDate!, date)) {
      return;
    }
    _handleDragSelectionAt(date);
  }

  void _endDateDrag() {
    _isDraggingDates = false;
    _dragSelectMode = null;
    _lastDraggedDate = null;
  }

  String get _selectedChoresSummary {
    final selected = kChoreDisplayNames.where(_selectedChores.contains).toList();
    if (selected.isEmpty) return '집안일 선택';
    return selected.join(', ');
  }

  String get _selectedMemberSummary {
    if (_isLoadingMembers) return '담당자 불러오는 중…';
    final member = _selectedMember;
    if (member == null) return '담당자 선택';
    return member.name;
  }

  Future<void> _openChorePicker() async {
    final picked = await showDialog<Set<String>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => ChoreMultiSelectDialog(
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

  Future<void> _openMemberPicker() async {
    if (_isLoadingMembers) return;
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => ChoreMemberSelectDialog(
        members: _members,
        initialUserId: _selectedMember?.userId,
      ),
    );
    if (!mounted || picked == null) return;
    final member = _members.where((m) => m.userId == picked).firstOrNull;
    if (member == null) return;
    setState(() => _selectedMember = member);
  }

  Future<bool> _hasDuplicateAssignment({
    required int assigneeId,
    required String choreType,
    required String date,
  }) async {
    try {
      final response = await _choreService.fetchDailyChores(date: date);
      if (!response.isSuccess || response.result == null) return false;
      return response.result!.any(
        (item) =>
            item.choreType == choreType && item.assigneeId == assigneeId,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleManualAssign() async {
    if (_isLoading) return;

    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('담당자를 선택해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

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

    setState(() => _isLoading = true);

    try {
      final assigneeId = _selectedMember!.userId;
      final choreTypes = choreDisplayNamesToEnum(_selectedChores.toList());
      final sortedDates = _selectedDates.toList()..sort((a, b) => a.compareTo(b));

      for (final date in sortedDates) {
        final dateString = formatChoreDateForApi(date);
        for (final choreType in choreTypes) {
          final duplicate = await _hasDuplicateAssignment(
            assigneeId: assigneeId,
            choreType: choreType,
            date: dateString,
          );
          if (duplicate) {
            final choreName = choreEnumToDisplayName(choreType);
            setState(() => _isLoading = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$dateString에 $choreName이(가) 이미 배정되어 있어요.',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }

          await _choreService.registerManualChore(
            assigneeId: assigneeId,
            choreType: choreType,
            date: dateString,
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('집안일 직접 배정이 완료되었어요.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      var message = '집안일 직접 배정에 실패했어요.';
      if (e is ApiException) message = e.message;
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

  Widget _buildPickerRow({
    required String label,
    required VoidCallback? onTap,
  }) {
    return _buildSettingsStyleButton(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: label.contains('선택') || label.contains('불러')
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final modalHeight =
        (screenHeight * 0.78).clamp(_kModalMinHeight, _kModalMaxHeight);
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
                    '집안일 직접 배정',
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
              '담당자와 집안일을 고른 뒤\n캘린더에서 날짜를 선택하세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontFamily: 'Pretendard Variable',
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildPickerRow(
              label: _selectedMemberSummary,
              onTap: _isLoadingMembers ? null : _openMemberPicker,
            ),
            const SizedBox(height: 10),
            _buildPickerRow(
              label: _selectedChoresSummary,
              onTap: _openChorePicker,
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 10),
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
                      if (date != null) _startDateDrag(date);
                    },
                    onPanUpdate: (details) {
                      final date = _resolveDateFromCalendarOffset(
                        localPosition: details.localPosition,
                        size: gridSize,
                        days: days,
                      );
                      if (date != null) _updateDateDrag(date);
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
                        final isToday = choreIsSameDate(date, _today);

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
            const SizedBox(height: 18),
            _buildSettingsStyleButton(
              onTap: _isLoading ? null : _handleManualAssign,
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
                        '직접 배정',
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
