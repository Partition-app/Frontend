import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/services/calendar_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';
import 'package:partition_app/shared/widgets/schedule_registration_modal.dart';

/// 일정 수정 모달 — [ScheduleRegistrationModal]과 동일 글래스 톤
class ScheduleEditModal extends StatefulWidget {
  final int scheduleId;
  final String initialContent;
  final DateTime initialDate;
  final void Function(DateTime originalDate, DateTime updatedDate)? onSuccess;

  const ScheduleEditModal({
    super.key,
    required this.scheduleId,
    required this.initialContent,
    required this.initialDate,
    this.onSuccess,
  });

  @override
  State<ScheduleEditModal> createState() => _ScheduleEditModalState();
}

class _ScheduleEditModalState extends State<ScheduleEditModal> {
  late final TextEditingController _scheduleController;
  final FocusNode _focusNode = FocusNode();
  final CalendarService _calendarService = CalendarService();
  bool _isLoading = false;
  late DateTime _selectedDate;
  late final DateTime _originalDate;

  @override
  void initState() {
    super.initState();
    _scheduleController = TextEditingController(text: widget.initialContent);
    _originalDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _selectedDate = _originalDate;
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

  Future<void> _handleSave() async {
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

    setState(() => _isLoading = true);

    try {
      await _calendarService.updateSchedule(
        scheduleId: widget.scheduleId,
        content: scheduleText,
        date: _formatDateToApi(_selectedDate),
      );

      if (!mounted) return;

      Navigator.of(context).pop();
      widget.onSuccess?.call(_originalDate, _selectedDate);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_formatDate(_selectedDate)} 일정이 수정되었습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      var message = '일정 수정에 실패했습니다.';
      if (e is ApiException) message = e.message;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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
      insetPadding: const EdgeInsets.symmetric(
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
                      '일정 수정하기',
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
              const Text(
                '수정된 일정은 룸메이트와 공유됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Pretendard Variable',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 80,
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
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSaveButton(),
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

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: _isLoading ? null : _handleSave,
          child: Opacity(
            opacity: _isLoading ? 0.48 : 1,
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
              child: const Text(
                '저장하기',
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
      ),
    );
  }
}
