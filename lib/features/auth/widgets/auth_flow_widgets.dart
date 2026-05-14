import 'package:flutter/material.dart';

/// 회원가입·온보딩 플로우 공통 크기 토큰
abstract final class AuthFlowTokens {
  static const double logoSize = 40;
  static const double fieldWidth = 183;
  static const double fieldHeight = 47;
  static const double actionButtonHeight = 31;
}

/// 온보딩·로그인 화면 상단 로고 (크기 통일)
class AuthFlowLogo extends StatelessWidget {
  const AuthFlowLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/partition-logo-mini.png',
      width: AuthFlowTokens.logoSize,
      height: AuthFlowTokens.logoSize,
      fit: BoxFit.contain,
    );
  }
}
