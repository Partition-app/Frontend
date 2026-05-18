import 'package:flutter/material.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/chore_assignment_common.dart';
import 'package:partition_app/shared/widgets/chore_member_select_dialog.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 집안일 수정 — 담당자·날짜 변경 (AI 집안일 배정 모달과 동일 글래스 톤)
Future<Map<String, dynamic>?> showChoreEditDialog({
  required BuildContext context,
  required String choreTitle,
  required List<HouseholdMemberBrief> members,
  required int initialAssigneeId,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  int selectedAssigneeId = initialAssigneeId;
  DateTime selectedDate = choreDateOnly(initialDate);

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final assigneeName = members
              .where((m) => m.userId == selectedAssigneeId)
              .map((m) => m.name)
              .firstOrNull;
          final hasAssigneeLabel =
              assigneeName != null && assigneeName.isNotEmpty;

          return PartitionGlassDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            constraints: const BoxConstraints.tightFor(width: 350),
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 40),
                      const Expanded(
                        child: Text(
                          '집안일 수정',
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
                  Text(
                    choreTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Pretendard Variable',
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ChoreGlassSettingsButton(
                    onTap: members.isEmpty
                        ? null
                        : () async {
                            final picked = await showDialog<int>(
                              context: context,
                              barrierColor: Colors.black.withOpacity(0.55),
                              builder: (ctx) => ChoreMemberSelectDialog(
                                members: members,
                                initialUserId: selectedAssigneeId,
                              ),
                            );
                            if (picked != null) {
                              setDialogState(
                                  () => selectedAssigneeId = picked);
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              hasAssigneeLabel
                                  ? assigneeName!
                                  : '담당자 선택',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: hasAssigneeLabel
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.68),
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
                  const SizedBox(height: 10),
                  _ChoreGlassSettingsButton(
                    onTap: () async {
                      final picked = await showDialog<DateTime>(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.55),
                        builder: (ctx) => ChoreEditDatePickerDialog(
                          initialDate: selectedDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(
                            () => selectedDate = choreDateOnly(picked));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatChoreDateLabel(selectedDate),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
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
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _ChoreGlassSettingsButton(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Center(
                            child: Text(
                              '취소',
                              style: TextStyle(
                                color: PartitionUiTokens.actionText,
                                fontSize: PartitionUiTokens.actionFontSize,
                                fontWeight: PartitionUiTokens.actionWeight,
                                fontFamily: 'Pretendard Variable',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ChoreGlassSettingsButton(
                          onTap: () => Navigator.of(context).pop({
                            'assigneeId': selectedAssigneeId,
                            'date': selectedDate,
                          }),
                          child: const Center(
                            child: Text(
                              '저장',
                              style: TextStyle(
                                color: PartitionUiTokens.actionText,
                                fontSize: PartitionUiTokens.actionFontSize,
                                fontWeight: PartitionUiTokens.actionWeight,
                                fontFamily: 'Pretendard Variable',
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
        },
      );
    },
  );
}

String formatChoreDateLabel(DateTime date) =>
    '${date.year}년 ${date.month}월 ${date.day}일';

/// AI 배정 모달과 동일한 필 액션 버튼
class _ChoreGlassSettingsButton extends StatelessWidget {
  const _ChoreGlassSettingsButton({
    required this.child,
    required this.onTap,
    this.height = PartitionUiTokens.actionButtonHeight,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
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
}

/// 날짜 선택 — [PartitionGlassDialog] 블러 + 배정 모달 캘린더 그리드
class ChoreEditDatePickerDialog extends StatefulWidget {
  const ChoreEditDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<ChoreEditDatePickerDialog> createState() =>
      _ChoreEditDatePickerDialogState();
}

class _ChoreEditDatePickerDialogState extends State<ChoreEditDatePickerDialog> {
  static const int _kCalendarColumns = 7;
  static const double _kCalendarCellGap = 4;
  static const double _kGridHeight = 252;

  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  DateTime get _first => choreDateOnly(widget.firstDate);
  DateTime get _last => choreDateOnly(widget.lastDate);

  @override
  void initState() {
    super.initState();
    _selectedDate = choreDateOnly(widget.initialDate);
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  String _monthYearLabel(DateTime date) => '${date.year}년 ${date.month}월';

  bool _isDateSelectable(DateTime date) {
    final d = choreDateOnly(date);
    return !d.isBefore(_first) && !d.isAfter(_last);
  }

  bool _isVisibleMonthDateSelectable(DateTime date) {
    final normalized = choreDateOnly(date);
    final inMonth = normalized.year == _visibleMonth.year &&
        normalized.month == _visibleMonth.month;
    return inMonth && _isDateSelectable(normalized);
  }

  bool _canGoPreviousMonth() {
    final previousMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    final firstMonth = DateTime(_first.year, _first.month);
    return !previousMonth.isBefore(firstMonth);
  }

  bool _canGoNextMonth() {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    final lastMonth = DateTime(_last.year, _last.month);
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

  @override
  Widget build(BuildContext context) {
    final days = _getVisibleCalendarDays();
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    final today = choreDateOnly(DateTime.now());

    return PartitionGlassDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      constraints: const BoxConstraints.tightFor(width: 350),
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '날짜 선택',
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
            Text(
              formatChoreDateLabel(_selectedDate),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 13,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 20),
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
            SizedBox(
              height: _kGridHeight,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _kCalendarColumns,
                  mainAxisSpacing: _kCalendarCellGap,
                  crossAxisSpacing: _kCalendarCellGap,
                  childAspectRatio: (350 - 48) /
                      _kCalendarColumns /
                      ((_kGridHeight -
                              _kCalendarCellGap *
                                  ((days.length / _kCalendarColumns).ceil() -
                                      1)) /
                          (days.length / _kCalendarColumns).ceil()),
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final date = days[index];
                  final isCurrentMonth = date.year == _visibleMonth.year &&
                      date.month == _visibleMonth.month;
                  final isSelectable = _isVisibleMonthDateSelectable(date);
                  final isSelected = choreIsSameDate(date, _selectedDate);
                  final isToday = choreIsSameDate(date, today);

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isSelectable
                        ? () => setState(
                              () => _selectedDate = choreDateOnly(date),
                            )
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isSelected ? Colors.white : Colors.transparent,
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
            ),
            const SizedBox(height: 22),
            _ChoreGlassSettingsButton(
              onTap: () => Navigator.of(context).pop(_selectedDate),
              child: const Center(
                child: Text(
                  '선택 완료',
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
