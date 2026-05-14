import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';

class ConfirmGroupNameScreen extends StatelessWidget {
  final String groupName;

  const ConfirmGroupNameScreen({
    super.key,
    required this.groupName,
  });

  Future<void> _handleConfirm(BuildContext context) async {
    try {
      // 로딩 표시
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // 실제 그룹 생성 API 호출
      final authService = AuthService();
      final response = await authService.createHousehold(name: groupName);

      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      }

      // 응답에서 그룹 코드 추출 (result.code 또는 result의 다른 필드)
      final groupCode = response.result?.code ?? 
                       response.result?.id?.toString() ?? 
                       '';
      final householdId = response.result?.id?.toString();

      if (context.mounted) {
        if (response.isSuccess) {
          // 그룹 ID 저장
          if (householdId != null) {
            await StorageService.setHouseholdId(householdId);
          }

          // 새로고침 후에도 홈으로 라우팅되도록 역할 갱신 (생성자 → LEADER)
          await StorageService.setUserRole('LEADER');
          await StorageService.setOnboardingCompleted(true);
          
          Navigator.of(context).pushReplacementNamed(
            AppRouter.groupCreated,
            arguments: {
              'groupName': groupName,
              'groupCode': groupCode,
            },
          );
        } else {
          // 에러 처리
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '그룹 생성에 실패했습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('그룹 생성 중 오류가 발생했습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleBack(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 백그라운드 이미지
        Positioned.fill(
          child: Image.asset(
            'assets/images/background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: Colors.black);
            },
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 로고 이미지
                    const AuthFlowLogo(),
                    const SizedBox(height: 20),
                    // 글래스모피즘 다이얼로그 박스
                    _buildDialogBox(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogBox(BuildContext context) {
    return Container(
      width: 294,
      constraints: const BoxConstraints(
        minHeight: 180,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white,
          width: 0.5,
        ),
        gradient: const RadialGradient(
          center: Alignment(-0.1212, -0.1178),
          radius: 1.6319,
          colors: [
            Color.fromRGBO(255, 255, 255, 0.10),
            Color.fromRGBO(255, 255, 255, 0.15),
          ],
          stops: [0.0, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.25),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 그룹명 표시
                Text(
                  "'$groupName'",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '이 그룹명으로 하겠습니까?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // 해당 그룹명으로 결정 버튼
                GlassmorphismButton(
                  text: '해당 그룹명으로 결정',
                  onTap: () => _handleConfirm(context),
                  width: 183,
                  height: 31,
                ),
                const SizedBox(height: 12),
                // 이전으로 버튼
                GlassmorphismButton(
                  text: '이전으로',
                  onTap: () => _handleBack(context),
                  width: 183,
                  height: 31,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

