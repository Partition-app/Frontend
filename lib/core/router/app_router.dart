import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/features/auth/screens/login_screen.dart';
import 'package:partition_app/features/auth/screens/onboarding_survey_screen.dart';
import 'package:partition_app/features/auth/screens/group_selection_screen.dart';
import 'package:partition_app/features/auth/screens/enter_group_code_screen.dart';
import 'package:partition_app/features/auth/screens/create_group_screen.dart';
import 'package:partition_app/features/auth/screens/confirm_group_name_screen.dart';
import 'package:partition_app/features/auth/screens/group_created_screen.dart';
import 'package:partition_app/features/auth/screens/preference_survey_screen.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/partition/screens/partition_main_screen.dart';
import 'package:partition_app/features/settings/screens/settings_screen.dart';
import 'package:partition_app/shared/widgets/not_found_screen.dart';

class AppRouter {
  static const String initialRoute = '/login';
  
  // Route names
  static const String login = '/login';
  static const String onboardingSurvey = '/onboarding-survey';
  static const String groupSelection = '/group-selection';
  static const String enterGroupCode = '/enter-group-code';
  static const String createGroup = '/create-group';
  static const String confirmGroupName = '/confirm-group-name';
  static const String groupCreated = '/group-created';
  static const String preferenceSurvey = '/preference-survey';
  static const String partitionMain = '/partitions';
  static const String settings = '/settings';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
      case onboardingSurvey:
        return MaterialPageRoute(
          builder: (_) => const OnboardingSurveyScreen(),
        );
      case groupSelection:
        return MaterialPageRoute(
          builder: (_) => const GroupSelectionScreen(),
        );
      case enterGroupCode:
        return MaterialPageRoute(
          builder: (_) => const EnterGroupCodeScreen(),
        );
      case createGroup:
        return MaterialPageRoute(
          builder: (_) => const CreateGroupScreen(),
        );
      case confirmGroupName:
        final groupName = settings.arguments as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => ConfirmGroupNameScreen(groupName: groupName),
        );
      case groupCreated:
        final args = settings.arguments as Map<String, dynamic>?;
        final groupName = args?['groupName'] as String? ?? '';
        final groupCode = args?['groupCode'] as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => GroupCreatedScreen(
            groupName: groupName,
            groupCode: groupCode,
          ),
        );
      case preferenceSurvey:
        return MaterialPageRoute(
          builder: (_) => const PreferenceSurveyScreen(),
        );
      case partitionMain:
        return MaterialPageRoute(
          builder: (context) => _AuthGuard(
            child: const PartitionMainScreen(),
          ),
        );
      case AppRouter.settings:
        return MaterialPageRoute(
          builder: (context) => _AuthGuard(
            child: const SettingsScreen(),
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const NotFoundScreen(),
        );
    }
  }
}

/// 인증이 필요한 화면을 보호하는 위젯
class _AuthGuard extends StatefulWidget {
  final Widget child;

  const _AuthGuard({required this.child});

  @override
  State<_AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<_AuthGuard> {
  bool _isChecking = true;
  bool _sessionValid = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRouter.login);
  }

  Future<void> _verifySessionOrRedirect() async {
    final authService = AuthService();
    final isAuth = await authService.isAuthenticated();
    if (!isAuth && mounted) {
      _redirectToLogin();
    }
  }

  Future<void> _checkAuth() async {
    final authService = AuthService();
    final isAuth = await authService.isAuthenticated();

    if (!isAuth) {
      if (mounted) _redirectToLogin();
      return;
    }

    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.checkAuthStatus();

      setState(() {
        _sessionValid = true;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_sessionValid) {
      return const SizedBox.shrink();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => unawaited(_verifySessionOrRedirect()),
      child: widget.child,
    );
  }
}