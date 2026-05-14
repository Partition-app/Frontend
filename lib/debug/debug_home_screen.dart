import 'package:flutter/material.dart';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:provider/provider.dart';

/// 개발용 디버그 메뉴 화면
/// 디버그 모드에서만 표시되며, 각 화면으로 바로 이동할 수 있습니다.
class DebugHomeScreen extends StatelessWidget {
  const DebugHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 릴리즈 빌드에서는 이 화면이 표시되지 않도록 보장
    assert(() {
      return true;
    }());

    return Scaffold(
      appBar: AppBar(
        title: const Text('🐛 DEBUG MENU'),
        backgroundColor: Colors.orange,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '개발용 화면 바로가기',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // 인증 관련
          _buildSectionTitle('인증'),
          _buildMenuItem(
            context,
            title: '로그인 화면',
            icon: Icons.login,
            route: AppRouter.login,
          ),
          const SizedBox(height: 16),
          
          // 파티션 관련
          _buildSectionTitle('파티션'),
          _buildMenuItem(
            context,
            title: '파티션 메인 (홈/공용소비/관리/게시판)',
            icon: Icons.dashboard,
            route: AppRouter.partitionMain,
            requiresAuth: true,
          ),
          const SizedBox(height: 16),
          
          // 설정
          _buildSectionTitle('설정'),
          _buildMenuItem(
            context,
            title: '설정 화면',
            icon: Icons.settings,
            route: AppRouter.settings,
            requiresAuth: true,
          ),
          const SizedBox(height: 24),
          
          // 디버그 기능
          _buildSectionTitle('디버그 기능'),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.blue),
            title: const Text('더미 유저로 로그인'),
            subtitle: const Text('로그인 없이 인증된 상태로 전환'),
            onTap: () async {
              final authProvider = context.read<AuthProvider>();
              
              // 더미 유저 설정
              authProvider.setMockUserForDebug();
              
              // StorageService 초기화 (아직 안 되어 있다면)
              await StorageService.init();
              
              // 더미 유저를 위한 필수 데이터 설정
              await StorageService.setUserName('Debug User');
              await StorageService.setHouseholdId('debug-household-001');
              await StorageService.setOnboardingCompleted(true);
              
              // 더미 토큰 설정 (인증 체크를 통과하기 위해)
              await StorageService.setToken('debug-token');
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ 더미 유저로 로그인되었습니다. 홈으로 이동합니다.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 1),
                  ),
                );
                
                // 홈 화면으로 이동
                Navigator.of(context).pushReplacementNamed(AppRouter.partitionMain);
              }
            },
          ),
          Builder(
            builder: (context) {
              return ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('로그아웃'),
                subtitle: const Text('인증 상태 초기화'),
                onTap: () async {
                  final authProvider = context.read<AuthProvider>();
                  await authProvider.logout();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('로그아웃되었습니다'),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
    String? arguments,
    bool requiresAuth = false,
  }) {
    return Builder(
      builder: (context) {
        final authProvider = context.watch<AuthProvider>();
        final isAuthenticated = authProvider.isAuthenticated;
        
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: requiresAuth && !isAuthenticated
              ? const Text(
                  '⚠️ 로그인 필요',
                  style: TextStyle(color: Colors.orange),
                )
              : null,
          trailing: requiresAuth && !isAuthenticated
              ? const Icon(Icons.lock, color: Colors.orange)
              : const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async {
            if (requiresAuth) {
              final isAuth = await AuthService().isAuthenticated();
              if (!isAuth) {
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed(AppRouter.login);
                }
                return;
              }
            }
            
            if (arguments != null) {
              Navigator.pushNamed(context, route, arguments: arguments);
            } else {
              Navigator.pushNamed(context, route);
            }
          },
        );
      },
    );
  }
}

