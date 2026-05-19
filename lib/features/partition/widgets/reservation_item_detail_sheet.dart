import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 예약 게시판 — 항목명 탭 시 상세(이용완료·삭제)
class ReservationItemDetailSheet extends StatefulWidget {
  final String itemName;
  final String startLabel;
  final String endLabel;
  final String reserverName;
  final bool completed;
  /// 본인 예약이면 완료·삭제 UI 표시
  final bool canManageCompletion;

  /// 이용완료 처리 (`PATCH .../complete`)
  final Future<void> Function()? onMarkCompleted;

  /// 삭제 (`DELETE /reservations`)
  final Future<void> Function()? onDeleteRequested;

  /// 시트를 닫은 뒤 예약 수정 다이얼로그를 연다
  final VoidCallback? onEditRequested;

  const ReservationItemDetailSheet({
    super.key,
    required this.itemName,
    required this.startLabel,
    required this.endLabel,
    required this.reserverName,
    required this.completed,
    this.canManageCompletion = true,
    this.onMarkCompleted,
    this.onDeleteRequested,
    this.onEditRequested,
  });

  @override
  State<ReservationItemDetailSheet> createState() =>
      _ReservationItemDetailSheetState();
}

class _ReservationItemDetailSheetState extends State<ReservationItemDetailSheet> {
  late bool _completed;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _completed = widget.completed;
  }

  @override
  void didUpdateWidget(ReservationItemDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completed != widget.completed) {
      _completed = widget.completed;
    }
  }

  String get _timeRangeLine => '${widget.startLabel} ~ ${widget.endLabel}';

  Future<void> _handleMarkCompleted() async {
    final action = widget.onMarkCompleted;
    if (action == null || _completed || _completing) return;
    setState(() => _completing = true);
    try {
      await action();
      if (mounted) setState(() => _completed = true);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger
            ? const Color.fromRGBO(255, 180, 180, 1.0)
            : Colors.white,
        side: BorderSide(
          color: danger
              ? Colors.redAccent.withOpacity(0.55)
              : Colors.white.withOpacity(onPressed == null ? 0.18 : 0.45),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onPressed == null
              ? Colors.white.withOpacity(0.42)
              : (danger
                    ? const Color.fromRGBO(255, 180, 180, 1.0)
                    : Colors.white),
          fontWeight: FontWeight.w600,
          fontFamily: 'Pretendard Variable',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.45), width: 0.5),
            gradient: const RadialGradient(
              center: Alignment(-0.12, -0.12),
              radius: 1.7,
              colors: [
                Color.fromRGBO(255, 255, 255, 0.14),
                Color.fromRGBO(255, 255, 255, 0.08),
              ],
              stops: [0.0, 1.0],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(255, 255, 255, 0.12),
                offset: Offset(0, -4),
                blurRadius: 24,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.itemName,
                            style: TextStyle(
                              color: _completed
                                  ? Colors.white.withOpacity(0.45)
                                  : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Pretendard Variable',
                              height: 1.25,
                              decoration: _completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.white54,
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
                      _timeRangeLine,
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                          _completed ? 0.5 : 0.82,
                        ),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: _completed ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '예약자 · ${widget.reserverName}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                          _completed ? 0.45 : 0.95,
                        ),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: _completed ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white54,
                      ),
                    ),
                    if (widget.onEditRequested != null ||
                        widget.onDeleteRequested != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (widget.onEditRequested != null)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onEditRequested!();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  '수정',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Pretendard Variable',
                                  ),
                                ),
                              ),
                            ),
                          if (widget.onEditRequested != null &&
                              widget.onDeleteRequested != null)
                            const SizedBox(width: 10),
                          if (widget.onDeleteRequested != null)
                            Expanded(
                              child: _buildActionButton(
                                label: '삭제',
                                danger: true,
                                onPressed: () async {
                                  final del = widget.onDeleteRequested!;
                                  Navigator.of(context).pop();
                                  await del();
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '이용 관리',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _completed ? '이용 완료' : '이용 전',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  !widget.canManageCompletion
                                      ? '다른 사람 예약은 조회만 가능해요. 수정·완료·삭제는 예약자만 할 수 있어요.'
                                      : _completed
                                          ? '완료된 예약은 취소선과 흐린 색으로 표시돼요.'
                                          : '종료 시각이 지나면 본인 예약은 자동 완료되며, 아래에서 수동 완료할 수 있어요.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.62),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.canManageCompletion)
                            Switch.adaptive(
                              value: _completed,
                              onChanged: _completed || _completing
                                  ? null
                                  : (_) => _handleMarkCompleted(),
                              activeColor: Colors.white,
                              activeTrackColor:
                                  Colors.white.withOpacity(0.35),
                            ),
                        ],
                      ),
                    ),
                    if (widget.canManageCompletion &&
                        !_completed &&
                        widget.onMarkCompleted != null) ...[
                      const SizedBox(height: 10),
                      _buildActionButton(
                        label: _completing ? '처리 중…' : '이용 완료 처리',
                        onPressed: _completing ? null : _handleMarkCompleted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
