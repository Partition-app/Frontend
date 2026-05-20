import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 파티션 홈/모달 UI에서 공통으로 쓰는 디자인 토큰.
///
/// 규칙:
/// - 주요 액션 버튼: 높이 46, radius 23 (홈 화면 버튼 기준)
/// - 입력/선택 필드: radius 16
/// - 모달/카드 외곽: radius 24 / 20
/// - 기본 액션 버튼 텍스트: 14px, w400
/// - 본문 입력/리스트 텍스트: 13px
/// - 보조 설명/캡션: 12px
abstract final class PartitionUiTokens {
  static const double modalRadius = 24;
  static const double cardRadius = 20;
  static const double fieldRadius = 16;
  static const double compactRadius = 12;

  static const double actionButtonHeight = 46;
  static const double actionButtonRadius = actionButtonHeight / 2;

  static const double titleFontSize = 18;
  static const double bodyFontSize = 13;
  static const double captionFontSize = 12;
  static const double actionFontSize = 14;

  static const FontWeight titleWeight = FontWeight.w900;
  static const FontWeight bodyStrongWeight = FontWeight.w600;
  static const FontWeight actionWeight = FontWeight.w400;

  static const Color textPrimary = Colors.white;
  static const Color actionText = Colors.white;
  static const Color actionTextDisabled = Color.fromRGBO(255, 255, 255, 0.42);

  static const Color surfaceFill = Color.fromRGBO(255, 255, 255, 0.10);
  static const Color surfaceFillSoft = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color surfaceFillMuted = Color.fromRGBO(255, 255, 255, 0.06);

  static const Color surfaceBorder = Color.fromRGBO(255, 255, 255, 0.24);
  static const Color surfaceBorderSoft = Color.fromRGBO(255, 255, 255, 0.18);
  static const Color surfaceBorderMuted = Color.fromRGBO(255, 255, 255, 0.14);

  static const Color actionButtonFill = surfaceFillSoft;
  static const Color actionButtonBorder = Color.fromRGBO(255, 255, 255, 0.25);
  static const Color actionButtonFillDisabled = Color.fromRGBO(255, 255, 255, 0.04);
  static const Color actionButtonBorderDisabled =
      Color.fromRGBO(160, 160, 170, 0.55);

  static Color textSecondary([double opacity = 0.72]) =>
      Colors.white.withValues(alpha: opacity);

  static Color textHint([double opacity = 0.45]) =>
      Colors.white.withValues(alpha: opacity);

  // ── 반응형 레이아웃 토큰 ──────────────────────────────────────────────────
  /// 태블릿 판정 기준 — 짧은 변(shortestSide)이 이 값 이상이면 태블릿으로 본다.
  static const double tabletShortestSideBreakpoint = 600;

  /// 홈 캘린더/버튼 폭과 동일한 컨텐츠 최대 폭.
  /// 공용소비·리포트·게시판 등에서도 동일한 폭을 사용해 태블릿에서 좌우 여백이 자동으로 늘어난다.
  static const double maxContentWidth = 560;

  /// 폰 기본 가로 패딩.
  static const double basePaddingHorizontal = 16;

  /// 주어진 [width]에 대해 컨텐츠가 [maxContentWidth] 안에 들어가도록 좌우 패딩을 계산한다.
  /// 좁은 화면(폰)에서는 [basePaddingHorizontal], 넓은 화면(태블릿/웹)에서는
  /// 양옆이 자동으로 늘어나서 컨텐츠가 중앙으로 모인다.
  static double resolveHorizontalPadding(double width) {
    final extra = (width - maxContentWidth) / 2;
    return math.max(basePaddingHorizontal, extra);
  }
}
