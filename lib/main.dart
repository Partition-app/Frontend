import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/push/fcm_registration_service.dart';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/theme/app_theme.dart';
import 'package:partition_app/core/providers/app_providers.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/debug/debug_home_screen.dart';
import 'package:partition_app/features/auth/auth_entry_route_resolver.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';

/// 화면 너비가 이 값을 초과하면 세로형 폰 프레임으로 중앙에 배치
const double _kPhoneFrameBreakpoint = 800.0;
const double _kPhoneFrameWidth = 730.0;

/// 웹/PWA에서 앱 바깥(상·하단 세이프에어리어·레터박스) 배경색
const Color _kWebBackdropColor = Color(0xFF26394B);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // StorageService를 앱 시작 시점에 미리 초기화해 _prefs null 문제 방지
  await StorageService.init();

  // Firebase는 웹에서 백그라운드 메시지 핸들러 미지원
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await FcmRegistrationService.initializePlugin();

  // 카카오 SDK 초기화 (웹은 javascriptAppKey 필요)
  KakaoSdk.init(
    nativeAppKey: '0638124027aec1134312be64899dcde2',
    javaScriptAppKey: '4b6461d2fcd70ec1c6a0f4cd4c0c3cdf',
  );

  runApp(const PartitionApp());
}

/// 모바일 Safari 등에서 scaffold 기본값(밝은 배경)이 비치지 않도록.
ThemeData _webPageBackdrop(ThemeData base) {
  return base.copyWith(
    scaffoldBackgroundColor: _kWebBackdropColor,
    canvasColor: _kWebBackdropColor,
  );
}

class PartitionApp extends StatelessWidget {
  const PartitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppProviders.providers,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: kIsWeb ? _webPageBackdrop(AppTheme.lightTheme) : AppTheme.lightTheme,
        darkTheme: kIsWeb ? _webPageBackdrop(AppTheme.darkTheme) : AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        // 디버그 모드에서는 DebugHomeScreen을 시작 화면으로
        home: kDebugMode
            ? const DebugHomeScreen()
            : const AuthWrapper(),
        // 웹 새로고침 시 URL과 무관하게 항상 AuthWrapper에서 시작해 홈으로 리다이렉트
        onGenerateInitialRoutes: kDebugMode
            ? null
            : (_) => [
                  MaterialPageRoute(
                    builder: (_) => const AuthWrapper(),
                  ),
                ],
        onGenerateRoute: AppRouter.generateRoute,
        // 넓은 화면(웹·태블릿 등)에서 세로형 폰 프레임으로 중앙 배치
        builder: (context, child) => _PhoneFrameWrapper(child: child!),
      ),
    );
  }
}

/// 화면 너비가 [_kPhoneFrameBreakpoint]를 초과할 때
/// 앱 전체를 [_kPhoneFrameWidth] 폭의 세로형 컨테이너 안에 가운데 배치합니다.
/// MediaQuery도 함께 오버라이드해 내부 위젯이 올바른 크기를 보고하게 합니다.
class _PhoneFrameWrapper extends StatelessWidget {
  final Widget child;
  const _PhoneFrameWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;

        // 이미 폰 크기이거나 세로가 더 짧은 경우
        if (screenW <= _kPhoneFrameBreakpoint) {
          if (kIsWeb) {
            // iOS Safari/PWA: 고정 height SizedBox는 visualViewport와 어긋날 수 있어
            // 부모(flutter-view)가 채우는 크기를 그대로 따르게 함
            return ColoredBox(
              color: _kWebBackdropColor,
              child: SizedBox.expand(child: child),
            );
          }
          return child;
        }

        // 넓은 화면: 폰 프레임 내에 렌더
        final double frameW = _kPhoneFrameWidth.clamp(0.0, screenW);
        final double frameH = screenH;

        // MediaQuery를 덮어써서 내부 위젯이 폰 크기(frameW × frameH)를 인식하게 함
        final MediaQueryData parentMq = MediaQuery.of(context);
        final MediaQueryData childMq = parentMq.copyWith(
          size: Size(frameW, frameH),
        );

        return Container(
          width: screenW,
          height: screenH,
          color: _kWebBackdropColor,
          child: Center(
            child: SizedBox(
              width: frameW,
              height: frameH,
              child: MediaQuery(
                data: childMq,
                child: ClipRect(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 인증 상태에 따라 초기 화면을 결정하는 위젯
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // main()에서 이미 초기화됐지만 위젯이 늦게 마운트된 경우를 대비해 재확인
    await StorageService.init();

    // 인증 상태 확인 (JWT 만료 시 자동 클리어 후 false 반환)
    final authService = AuthService();
    final isAuth = await authService.isAuthenticated();
    
    if (mounted) {
      setState(() {
        _isAuthenticated = isAuth;
        _isLoading = false;
      });
      
      // AuthProvider도 업데이트
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.checkAuthStatus();
      
      // 인증 상태에 따라 네비게이션
      if (isAuth) {
        // 사용자 상태 확인 및 적절한 화면으로 이동
        final targetRoute = await AuthEntryRouteResolver.resolve();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(targetRoute);
          unawaited(FcmRegistrationService.registerIfLoggedIn());
        }
      } else {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRouter.login);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    // 로딩 중이 아니면 빈 화면 (네비게이션이 처리됨)
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}