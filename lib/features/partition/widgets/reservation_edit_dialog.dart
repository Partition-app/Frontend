import 'package:flutter/material.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/features/partition/models/reservation_item_model.dart';
import 'package:partition_app/features/partition/services/reservation_items_service.dart';
import 'package:partition_app/features/partition/services/reservations_service.dart';
import 'package:partition_app/shared/widgets/frosted_panel.dart';
import 'package:partition_app/shared/widgets/glassmorphic_date_picker.dart';
import 'package:partition_app/shared/widgets/glassmorphic_time_picker.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';
import 'package:partition_app/shared/widgets/primary_button.dart';

const Duration _kMaxReservationDuration = Duration(hours: 5);
const int _kMaxReservationAdvanceDays = 14;

/// 예약 수정 저장 결과
class ReservationEditResult {
  final int itemId;
  final String itemName;
  final DateTime startTime;
  final DateTime endTime;

  const ReservationEditResult({
    required this.itemId,
    required this.itemName,
    required this.startTime,
    required this.endTime,
  });
}

/// 예약 수정 (`PATCH /api/reservations/{reservationId}`)
Future<ReservationEditResult?> showReservationEditDialog({
  required BuildContext context,
  required int reservationId,
  required int initialItemId,
  required DateTime initialStart,
  required DateTime initialEnd,
  bool useDummyData = false,
  List<ReservationItem>? initialItems,
  Future<void> Function()? onOpenReservationItemManage,
}) {
  return showDialog<ReservationEditResult>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (ctx) => _ReservationEditDialog(
      reservationId: reservationId,
      initialItemId: initialItemId,
      initialStart: initialStart,
      initialEnd: initialEnd,
      useDummyData: useDummyData,
      initialItems: initialItems,
      onOpenReservationItemManage: onOpenReservationItemManage,
    ),
  );
}

class _ReservationEditDialog extends StatefulWidget {
  final int reservationId;
  final int initialItemId;
  final DateTime initialStart;
  final DateTime initialEnd;
  final bool useDummyData;
  final List<ReservationItem>? initialItems;
  final Future<void> Function()? onOpenReservationItemManage;

  const _ReservationEditDialog({
    required this.reservationId,
    required this.initialItemId,
    required this.initialStart,
    required this.initialEnd,
    required this.useDummyData,
    this.initialItems,
    this.onOpenReservationItemManage,
  });

  @override
  State<_ReservationEditDialog> createState() => _ReservationEditDialogState();
}

class _ReservationEditDialogState extends State<_ReservationEditDialog> {
  late DateTime _start;
  late DateTime _end;
  final ReservationItemsService _itemsService = ReservationItemsService();
  final ReservationsService _reservationsService = ReservationsService();

  List<ReservationItem> _items = [];
  bool _itemsLoading = false;
  int? _selectedItemId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _selectedItemId = widget.initialItemId > 0 ? widget.initialItemId : null;
    if (widget.useDummyData) {
      _items = widget.initialItems ?? [];
    } else {
      _loadItems();
    }
  }

  Future<void> _loadItems() async {
    setState(() => _itemsLoading = true);
    try {
      final list = await _itemsService.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = list;
        _itemsLoading = false;
        if (_selectedItemId == null && list.isNotEmpty) {
          _selectedItemId = list.first.itemId;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = widget.initialItems ?? [];
        _itemsLoading = false;
      });
    }
  }

  Future<void> _openItemManage() async {
    final open = widget.onOpenReservationItemManage;
    if (open == null) return;
    await open();
    if (mounted) await _loadItems();
  }

  String _formatField(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}. '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  DateTime get _earliestBookableTime {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  DateTime get _latestBookableTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = today.add(const Duration(days: _kMaxReservationAdvanceDays));
    return DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59);
  }

  bool _isWithinBookableRange(DateTime dt) {
    return !dt.isBefore(_earliestBookableTime) && !dt.isAfter(_latestBookableTime);
  }

  Future<DateTime?> _pickDateTime(
    DateTime initial, {
    DateTime? minDateTime,
    DateTime? maxDateTime,
  }) async {
    var init = initial;
    final floor = minDateTime ?? _earliestBookableTime;
    final ceiling = maxDateTime ?? _latestBookableTime;
    if (init.isBefore(floor)) init = floor;
    if (init.isAfter(ceiling)) init = ceiling;

    final date = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => GlassmorphicDatePicker(
        initialDate: init,
        firstDate: DateTime(floor.year, floor.month, floor.day),
        lastDate: DateTime(ceiling.year, ceiling.month, ceiling.day),
        isStartDate: true,
      ),
    );
    if (!mounted || date == null) return null;

    final selectedDay = DateTime(date.year, date.month, date.day);
    final floorDay = DateTime(floor.year, floor.month, floor.day);
    final ceilingDay = DateTime(ceiling.year, ceiling.month, ceiling.day);
    TimeOfDay? minTime;
    TimeOfDay? maxTime;
    if (selectedDay == floorDay) {
      minTime = TimeOfDay(hour: floor.hour, minute: floor.minute);
    }
    if (selectedDay == ceilingDay) {
      maxTime = TimeOfDay(hour: ceiling.hour, minute: ceiling.minute);
    }

    final tod = await showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => GlassmorphicTimePicker(
        initialTime: TimeOfDay(hour: init.hour, minute: init.minute),
        minTime: minTime,
        maxTime: maxTime,
      ),
    );
    if (!mounted || tod == null) return null;

    var picked = DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
    if (picked.isBefore(floor)) picked = floor;
    if (picked.isAfter(ceiling)) picked = ceiling;
    return picked;
  }

  DateTime get _minEndTime => _start.add(const Duration(minutes: 1));

  DateTime get _maxEndTime => _start.add(_kMaxReservationDuration);

  DateTime get _cappedMaxEndTime {
    final raw = _maxEndTime;
    return raw.isAfter(_latestBookableTime) ? _latestBookableTime : raw;
  }

  DateTime _clampEndTime(DateTime end) {
    if (end.isBefore(_minEndTime)) return _minEndTime;
    if (end.isAfter(_cappedMaxEndTime)) return _cappedMaxEndTime;
    return end;
  }

  void _syncEndAfterStartChange() {
    if (!_end.isAfter(_start)) {
      _end = _start.add(const Duration(hours: 1));
    }
    _end = _clampEndTime(_end);
  }

  Future<void> _pickStart() async {
    final d = await _pickDateTime(
      _start,
      minDateTime: _earliestBookableTime,
      maxDateTime: _latestBookableTime,
    );
    if (d != null) {
      setState(() {
        _start = d;
        _syncEndAfterStartChange();
      });
    }
  }

  Future<void> _pickEnd() async {
    final base = _clampEndTime(
      _end.isAfter(_start) ? _end : _start.add(const Duration(hours: 1)),
    );
    final d = await _pickDateTime(
      base,
      minDateTime: _minEndTime,
      maxDateTime: _cappedMaxEndTime,
    );
    if (d != null) {
      setState(() => _end = _clampEndTime(d));
    }
  }

  ReservationItem? get _selectedItem {
    if (_selectedItemId == null) return null;
    for (final e in _items) {
      if (e.itemId == _selectedItemId) return e;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약할 물품을 목록에서 선택해 주세요.')),
      );
      return;
    }
    if (!_isWithinBookableRange(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('예약은 오늘부터 2주 이내 날짜·시간만 선택할 수 있습니다.'),
        ),
      );
      return;
    }
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 시간이 시작 시간보다 이후여야 합니다.')),
      );
      return;
    }
    if (_end.isAfter(_cappedMaxEndTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('종료 시간은 시작 시간으로부터 5시간 이내여야 합니다.'),
        ),
      );
      return;
    }

    final match = _selectedItem;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목록에서 예약 대상을 선택해 주세요.')),
      );
      return;
    }

    final result = ReservationEditResult(
      itemId: match.itemId,
      itemName: match.name,
      startTime: _start,
      endTime: _end,
    );

    if (widget.useDummyData) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    }

    setState(() => _submitting = true);
    try {
      try {
        final conflict = await _reservationsService.hasConflictingReservation(
          itemId: match.itemId,
          itemName: match.name,
          startTime: _start,
          endTime: _end,
          excludeReservationId: widget.reservationId,
        );
        if (conflict) {
          if (!mounted) return;
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(ReservationsService.conflictErrorMessage),
            ),
          );
          return;
        }
      } catch (_) {}

      await _reservationsService.updateReservation(
        reservationId: widget.reservationId,
        itemId: match.itemId,
        startTime: _start,
        endTime: _end,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약이 수정되었습니다.')),
      );
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e is ApiException ? e.message : '예약 수정에 실패했습니다.';
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PartitionGlassDialog.modal(
        constraints: BoxConstraints(maxWidth: dialogW, minWidth: dialogW),
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
                    '예약 수정',
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
                    child: PartitionModalCloseButton(
                      onPressed: () => Navigator.of(context).pop(),
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '대상과 시간을 변경하세요.\n(오늘부터 2주 이내)',
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
                            '등록된 예약 물품이 없습니다.',
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
                          height: 160,
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
                                              : Colors.white.withOpacity(0.45),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            e.name,
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
                if (widget.onOpenReservationItemManage != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _openItemManage,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('물품 관리'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              Row(
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
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: PrimaryButton(
                  label: _submitting ? '저장 중…' : '저장',
                  width: btnW,
                  enabled: !_submitting,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
