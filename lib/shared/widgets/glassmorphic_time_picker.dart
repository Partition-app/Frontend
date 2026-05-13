import 'package:flutter/material.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';

/// 글래스 스타일 시간 선택 다이얼로그.
class GlassmorphicTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final TimeOfDay? minTime;
  final TimeOfDay? maxTime;

  const GlassmorphicTimePicker({
    super.key,
    required this.initialTime,
    this.minTime,
    this.maxTime,
  });

  @override
  State<GlassmorphicTimePicker> createState() => _GlassmorphicTimePickerState();
}

class _GlassmorphicTimePickerState extends State<GlassmorphicTimePicker> {
  static const _itemExtent = 44.0;
  static const _wheelAreaHeight = 168.0;

  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  int? get _minMinutes =>
      widget.minTime == null ? null : _toMinutes(widget.minTime!);
  int? get _maxMinutes =>
      widget.maxTime == null ? null : _toMinutes(widget.maxTime!);

  @override
  void initState() {
    super.initState();
    final clamped = _clampTime(widget.initialTime);
    _hour = clamped.hour;
    _minute = clamped.minute;
    _hourController = FixedExtentScrollController(
      initialItem: _validHours()
          .indexOf(_hour)
          .clamp(0, _validHours().length - 1),
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _validMinutesForHour(_hour)
          .indexOf(_minute)
          .clamp(0, _validMinutesForHour(_hour).length - 1),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _clampTime(TimeOfDay time) {
    final value = _toMinutes(time);
    var h = time.hour;
    var m = time.minute;
    if (_minMinutes != null && value < _minMinutes!) {
      h = widget.minTime!.hour;
      m = widget.minTime!.minute;
    }
    if (_maxMinutes != null && value > _maxMinutes!) {
      h = widget.maxTime!.hour;
      m = widget.maxTime!.minute;
    }
    final hours = _validHours();
    if (!hours.contains(h)) {
      h = hours.isEmpty ? 0 : hours.first;
    }
    final mins = _validMinutesForHour(h);
    if (!mins.contains(m)) {
      m = mins.isEmpty ? 0 : mins.first;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  List<int> _validHours() {
    final hours = <int>[];
    for (var h = 0; h < 24; h++) {
      if (_validMinutesForHour(h).isNotEmpty) hours.add(h);
    }
    return hours;
  }

  List<int> _validMinutesForHour(int hour) {
    final mins = <int>[];
    for (var m = 0; m < 60; m++) {
      final total = hour * 60 + m;
      if (_minMinutes != null && total < _minMinutes!) continue;
      if (_maxMinutes != null && total > _maxMinutes!) continue;
      mins.add(m);
    }
    return mins;
  }

  void _onHourChanged(int index) {
    final hours = _validHours();
    if (index < 0 || index >= hours.length) return;
    final newHour = hours[index];
    final mins = _validMinutesForHour(newHour);
    var newMinute = _minute;
    if (!mins.contains(newMinute)) {
      newMinute = mins.first;
    }
    setState(() {
      _hour = newHour;
      _minute = newMinute;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mi = mins.indexOf(newMinute);
      if (mi >= 0 && _minuteController.hasClients) {
        _minuteController.jumpToItem(mi);
      }
    });
  }

  void _onMinuteChanged(int index) {
    final mins = _validMinutesForHour(_hour);
    if (index < 0 || index >= mins.length) return;
    setState(() => _minute = mins[index]);
  }

  String _formatHour(int h) => h.toString().padLeft(2, '0');

  String _formatMinute(int m) => m.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hours = _validHours();
    final minutes = _validMinutesForHour(_hour);
    final preview = '${_formatHour(_hour)}:${_formatMinute(_minute)}';

    return PartitionGlassDialog.modal(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '시간 선택',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: 'Pretendard Variable',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preview,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: 'Pretendard Variable',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: _wheelAreaHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Container(
                    height: _itemExtent,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: PartitionUiTokens.surfaceFillMuted,
                      border: Border.all(
                        color: PartitionUiTokens.surfaceBorderSoft,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _buildWheelScroll(
                        controller: _hourController,
                        itemCount: hours.length,
                        builder: (i) => _formatHour(hours[i]),
                        onChanged: _onHourChanged,
                      ),
                    ),
                    SizedBox(
                      width: 18,
                      height: _itemExtent,
                      child: Center(
                        child: Text(
                          ':',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Pretendard Variable',
                            height: 1,
                          ),
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildWheelScroll(
                        controller: _minuteController,
                        itemCount: minutes.length,
                        builder: (i) => _formatMinute(minutes[i]),
                        onChanged: _onMinuteChanged,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    '시',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Center(
                  child: Text(
                    '분',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                onTap: () => Navigator.of(context).pop(
                  TimeOfDay(hour: _hour, minute: _minute),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheelScroll({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) builder,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      diameterRatio: 1.35,
      perspective: 0.003,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          if (index < 0 || index >= itemCount) return null;
          final selected =
              controller.hasClients && controller.selectedItem == index;
          return SizedBox(
            height: _itemExtent,
            child: Center(
              child: Text(
                builder(index),
                style: TextStyle(
                  color: selected
                      ? Colors.white.withOpacity(0.95)
                      : Colors.white.withOpacity(0.32),
                  fontSize: selected ? 22 : 18,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  fontFamily: 'Pretendard Variable',
                  height: 1,
                ),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
              ),
            ),
          );
        },
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
