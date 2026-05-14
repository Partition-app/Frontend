import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';

/// 글래스모피즘 효과를 적용한 버튼 컴포넌트
/// width: 183px, height: 31px 기본값
class GlassmorphismButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool enabled;
  final double opacity;

  const GlassmorphismButton({
    super.key,
    required this.text,
    this.onTap,
    this.width = 183,
    this.height = 31,
    this.enabled = true,
    this.opacity = 1.0,
  });

  @override
  State<GlassmorphismButton> createState() => _GlassmorphismButtonState();
}

class _GlassmorphismButtonState extends State<GlassmorphismButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.height / 2);
    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
              setState(() {
                _isPressed = true;
              });
            }
          : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() {
                _isPressed = false;
              });
              widget.onTap?.call();
            }
          : null,
      onTapCancel: widget.enabled
          ? () {
              setState(() {
                _isPressed = false;
              });
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()..scale(_isPressed ? 0.95 : 1.0),
        child: Opacity(
          opacity: widget.enabled ? widget.opacity : 0.5,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: widget.enabled
                    ? PartitionUiTokens.actionButtonBorder
                    : PartitionUiTokens.actionButtonBorderDisabled,
                width: 0.5,
              ),
              color: widget.enabled
                  ? PartitionUiTokens.actionButtonFill
                  : PartitionUiTokens.actionButtonFillDisabled,
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
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Center(
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      color: widget.enabled
                          ? PartitionUiTokens.actionText
                          : PartitionUiTokens.actionTextDisabled,
                      fontSize: PartitionUiTokens.actionFontSize,
                      fontWeight: PartitionUiTokens.actionWeight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 글래스모피즘 효과를 적용한 입력 필드 컴포넌트
class GlassmorphismInputField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final double width;
  final double height;

  const GlassmorphismInputField({
    super.key,
    required this.controller,
    this.hintText,
    this.onChanged,
    this.autofocus = false,
    this.width = 183,
    this.height = 47,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PartitionUiTokens.fieldRadius);
    final verticalPad =
        ((height - PartitionUiTokens.bodyFontSize) / 2).clamp(0.0, height / 2);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: PartitionUiTokens.surfaceBorderSoft,
          width: 0.5,
        ),
        color: PartitionUiTokens.surfaceFillSoft,
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
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: autofocus,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                color: PartitionUiTokens.textPrimary,
                fontSize: PartitionUiTokens.bodyFontSize,
                height: 1.0,
              ),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: false,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: verticalPad,
                ),
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(
                  color: PartitionUiTokens.textHint(0.7),
                  fontSize: PartitionUiTokens.bodyFontSize,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

