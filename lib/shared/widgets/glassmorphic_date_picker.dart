import 'package:flutter/material.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';

/// 글래스 스타일 날짜 선택 다이얼로그.
class GlassmorphicDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool isStartDate;

  const GlassmorphicDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.isStartDate,
  });

  @override
  State<GlassmorphicDatePicker> createState() => _GlassmorphicDatePickerState();
}

class _GlassmorphicDatePickerState extends State<GlassmorphicDatePicker> {
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
    final firstDateOnly = DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final lastDateOnly = DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
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
      '1월', '2월', '3월', '4월', '5월', '6월',
      '7월', '8월', '9월', '10월', '11월', '12월'
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
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final screenWidth = mq.size.width;
    // 작은 디바이스(iPhone SE 등)에서 달 5주 그리드+버튼이 45% 제한에 걸려 오버플로우됨.
    // 안전 영역 안에서 세로를 넉넉히 쓰고, 큰 글자/랜드스케이프는 스크롤로 대응.
    final safeVertical = screenHeight - mq.padding.vertical;
    final maxDialogHeight = safeVertical * 0.82;

    return PartitionGlassDialog.modal(
      constraints: BoxConstraints(
        maxWidth: screenWidth - 32,
        maxHeight: maxDialogHeight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Opacity(
                        opacity: _canGoPrevious() ? 1 : 0.3,
                        child: GestureDetector(
                          onTap: _canGoPrevious() ? _previousMonth : null,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: PartitionUiTokens.surfaceBorderMuted,
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_left,
                              color: Colors.white.withOpacity(0.85),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _getMonthYearText(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Opacity(
                        opacity: _canGoNext() ? 1 : 0.3,
                        child: GestureDetector(
                          onTap: _canGoNext() ? _nextMonth : null,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: PartitionUiTokens.surfaceBorderMuted,
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              color: Colors.white.withOpacity(0.85),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: weekdays.map((day) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                GridView.builder(
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
                                  color: PartitionUiTokens.surfaceFillMuted,
                                  border: Border.all(
                                    color: PartitionUiTokens.surfaceBorderSoft,
                                    width: 0.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    textAlign: TextAlign.center,
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
                                          color:
                                              PartitionUiTokens.surfaceBorderSoft,
                                          width: 0.5,
                                        )
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isCurrentMonth && isSelectable
                                          ? Colors.white.withOpacity(0.92)
                                          : Colors.white.withOpacity(0.35),
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      label: '취소',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      label: '확인',
                      onTap: () => Navigator.of(context).pop(_selectedDate),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 100,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              color: PartitionUiTokens.actionButtonFill,
              border: Border.all(
                color: PartitionUiTokens.actionButtonBorder,
                width: 0.5,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
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
    );
  }
}
