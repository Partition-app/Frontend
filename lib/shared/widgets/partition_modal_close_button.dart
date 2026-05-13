import 'package:flutter/material.dart';

/// 파티션 모달 헤더용 닫기(X) 버튼. 터치 영역을 넓혀 누르기 쉽게 합니다.
class PartitionModalCloseButton extends StatelessWidget {
  const PartitionModalCloseButton({
    super.key,
    required this.onPressed,
    this.color,
    this.iconSize = 24,
    this.tooltip = '닫기',
  });

  final VoidCallback? onPressed;
  final Color? color;
  final double iconSize;
  final String tooltip;

  static const double hitSize = 48;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        Icons.close_rounded,
        color: color ?? Colors.white.withOpacity(0.9),
        size: iconSize,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: hitSize,
        minHeight: hitSize,
      ),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(hitSize, hitSize),
      ),
    );
  }
}
