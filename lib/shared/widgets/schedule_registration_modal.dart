import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/partition/services/calendar_service.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 일정 등록 모달
class ScheduleRegistrationModal extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback? onSuccess; // 등록 성공 시 호출될 콜백

  const ScheduleRegistrationModal({
    super.key,
    required this.selectedDate,
    this.onSuccess,
  });

  @override
  State<ScheduleRegistrationModal> createState() =>
      _ScheduleRegistrationModalState();
}

class _ScheduleRegistrationModalState extends State<ScheduleRegistrationModal> {
  final TextEditingController _scheduleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final CalendarService _calendarService = CalendarService();
  bool _isLoading = false;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    // 모달이 열린 후 포커스를 설정하여 키보드가 자동으로 나타나도록 함
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scheduleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    return '${date.year}년 ${date.month}월 ${date.day}일 (${weekdays[date.weekday % 7]})';
  }

  String _formatDateToApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickScheduleDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => ScheduleRegistrationDatePickerDialog(
        initialDate: _selectedDate,
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime(2100, 12, 31),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _handleRegister() async {
    final scheduleText = _scheduleController.text.trim();
    if (scheduleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('일정 내용을 입력해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dateString = _formatDateToApi(_selectedDate);
      await _calendarService.registerSchedule(
        content: scheduleText,
        date: dateString,
      );

      if (!mounted) return;

      // 등록 성공 시 모달 닫기
      Navigator.of(context).pop();

      // 콜백 호출하여 캘린더 갱신
      widget.onSuccess?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_formatDate(_selectedDate)} 일정이 등록되었습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      String errorMessage = '일정 등록에 실패했습니다.';
      if (e is ApiException) {
        errorMessage = e.message;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PartitionGlassDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      constraints: BoxConstraints(
        minWidth: screenWidth - 40,
        maxWidth: screenWidth - 40,
        maxHeight: screenHeight * 0.58,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  const SizedBox(width: 40),
                  const Expanded(
                    child: Text(
                      '일정 등록하기',
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
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickScheduleDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(PartitionUiTokens.fieldRadius),
                    border: Border.all(
                      color: PartitionUiTokens.surfaceBorderSoft,
                      width: 0.5,
                    ),
                    color: PartitionUiTokens.surfaceFillSoft,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '등록 날짜 변경',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Pretendard Variable',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(_selectedDate),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Pretendard Variable',
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white.withOpacity(0.82),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 부제목
              const Text(
                '등록된 일정은 룸메이트와 공유됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Pretendard Variable',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20), // 여백 축소
              // 입력 영역
              SizedBox(
                height: 80, // 고정 높이로 크기 절반으로 축소
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(PartitionUiTokens.fieldRadius),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 0.5,
                    ),
                    gradient: const RadialGradient(
                      center: Alignment(-0.1212, -0.1178),
                      radius: 1.6319,
                      colors: [
                        Color.fromRGBO(255, 255, 255, 0.10),
                        Color.fromRGBO(255, 255, 255, 0.15),
                      ],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(PartitionUiTokens.fieldRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: TextField(
                        controller: _scheduleController,
                        focusNode: _focusNode,
                        autofocus: true,
                        maxLines: 2,
                        maxLength: 30,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Pretendard Variable',
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '일정을 입력해주세요...',
                          hintStyle: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontFamily: 'Pretendard Variable',
                          ),
                          counterText: '', // 글자 수 카운터 숨기기
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20), // 여백 축소
              // 등록하기 버튼
              _buildRegisterButton(),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return _buildSettingsStyleButton(
      label: '등록하기',
      onTap: _isLoading ? null : _handleRegister,
    );
  }

  Widget _buildSettingsStyleButton({
    required String label,
    required VoidCallback? onTap,
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

/// 일정 등록·수정 공통 날짜 선택 (글래스 블러)
class ScheduleRegistrationDatePickerDialog extends StatefulWidget {
  const ScheduleRegistrationDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<ScheduleRegistrationDatePickerDialog> createState() =>
      _ScheduleRegistrationDatePickerDialogState();
}

class _ScheduleRegistrationDatePickerDialogState
    extends State<ScheduleRegistrationDatePickerDialog> {
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

    return PartitionGlassDialog(
      constraints: BoxConstraints.tightFor(width: dialogW),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '등록 날짜 선택',
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
              _ScheduleWeekdayLabel('일'),
              _ScheduleWeekdayLabel('월'),
              _ScheduleWeekdayLabel('화'),
              _ScheduleWeekdayLabel('수'),
              _ScheduleWeekdayLabel('목'),
              _ScheduleWeekdayLabel('금'),
              _ScheduleWeekdayLabel('토'),
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
            _formatSelectedDate(_selectedDate),
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

  String _formatSelectedDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
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

class _ScheduleWeekdayLabel extends StatelessWidget {
  const _ScheduleWeekdayLabel(this.label);

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
