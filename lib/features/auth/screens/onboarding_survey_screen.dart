import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';

class OnboardingSurveyScreen extends StatefulWidget {
  const OnboardingSurveyScreen({super.key});

  @override
  State<OnboardingSurveyScreen> createState() => _OnboardingSurveyScreenState();
}

class _OnboardingSurveyScreenState extends State<OnboardingSurveyScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
  }

  Future<void> _handleConfirm() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    try {
      // 로딩 표시
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // API로 이름 설정
      final authService = AuthService();
      final response = await authService.updateUserName(name: name);

      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      }

      if (response.isSuccess) {
        // 로컬 스토리지에도 저장 (API에서 이미 저장했지만 확실하게)
        await StorageService.setUserName(name);

        if (mounted) {
          // 그룹 선택 화면으로 이동
          Navigator.of(context).pushReplacementNamed(AppRouter.groupSelection);
        }
      } else {
        // 에러 처리
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '이름 설정에 실패했습니다.'),
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
            content: Text('이름 설정 중 오류가 발생했습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                    // 로고 이미지 (기준 80px 대비 70%)
                    Image.asset(
                      'assets/icons/partition-logo-mini.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 20),
                    // 글래스모피즘 다이얼로그 박스
                    _buildDialogBox(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogBox() {
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
                const Text(
                  '안녕하세요 지금부터 당신의 공동생활 관리를 도와줄 AI 공동생활관리 비서 파티션입니다. 당신의 이름을 알려주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                // 이름 입력 칸
                _buildNameInput(),
                // 확인 버튼 (항상 표시)
                const SizedBox(height: 16),
                _buildConfirmButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameInput() {
    if (!_isEditing) {
      // 입력하기 버튼
      return GlassmorphismButton(
        text: '입력하기',
        onTap: _startEditing,
        width: 183,
        height: 31,
      );
    }

    // 텍스트 입력 필드 — onChanged로 부모 setState 하지 않음 (한글 조합 유지)
    return GlassmorphismInputField(
      controller: _nameController,
      hintText: '이름',
      autofocus: true,
      width: 183,
      height: 47,
    );
  }

  Widget _buildConfirmButton() {
    return ListenableBuilder(
      listenable: _nameController,
      builder: (context, _) {
        final isEnabled =
            _isEditing && _nameController.text.trim().isNotEmpty;
        return GlassmorphismButton(
          text: '확인',
          onTap: _handleConfirm,
          width: 183,
          height: 31,
          enabled: isEnabled,
        );
      },
    );
  }
}

