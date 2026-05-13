import 'dart:ui';

import 'package:flutter/material.dart';

class PartitionGlassDialog extends StatelessWidget {
  const PartitionGlassDialog({
    super.key,
    required this.child,
    this.insetPadding =
        const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    this.alignment = Alignment.center,
    this.constraints,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blurSigma = 10,
    this.fillColor = const Color.fromRGBO(255, 255, 255, 0.12),
    this.borderColor = const Color.fromRGBO(255, 255, 255, 0.5),
    this.borderWidth = 0.5,
    this.gradient = const RadialGradient(
      center: Alignment(-0.1212, -0.1178),
      radius: 1.7145,
      colors: [
        Color.fromRGBO(255, 255, 255, 0.10),
        Color.fromRGBO(255, 255, 255, 0.15),
      ],
      stops: [0.0, 1.0],
    ),
    this.boxShadow = const [
      BoxShadow(
        color: Color.fromRGBO(255, 255, 255, 0.25),
        offset: Offset(4, 4),
        blurRadius: 30,
      ),
    ],
    this.padding,
  });

  /// 예약하기·설정 등 파티션 모달과 동일한 은은한 글래스 톤.
  factory PartitionGlassDialog.modal({
    Key? key,
    required Widget child,
    BoxConstraints? constraints,
    EdgeInsetsGeometry? padding,
    EdgeInsets insetPadding =
        const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  }) {
    return PartitionGlassDialog(
      key: key,
      insetPadding: insetPadding,
      constraints: constraints,
      padding: padding,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      blurSigma: 18,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.06),
      borderColor: const Color.fromRGBO(255, 255, 255, 0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      child: child,
    );
  }

  final Widget child;
  final EdgeInsets insetPadding;
  final AlignmentGeometry alignment;
  final BoxConstraints? constraints;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final Gradient gradient;
  final List<BoxShadow> boxShadow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: borderWidth),
        gradient: gradient,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            color: fillColor,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (constraints != null) {
      card = ConstrainedBox(constraints: constraints!, child: card);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: alignment,
      insetPadding: insetPadding,
      child: card,
    );
  }
}
