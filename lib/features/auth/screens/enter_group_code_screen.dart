import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/shared/utils/debug_helper.dart';

class EnterGroupCodeScreen extends StatefulWidget {
  const EnterGroupCodeScreen({super.key});

  @override
  State<EnterGroupCodeScreen> createState() => _EnterGroupCodeScreenState();
}

class _EnterGroupCodeScreenState extends State<EnterGroupCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _resultMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _resultMessage = null;
      _isSuccess = false;
    });

    try {
      DebugHelper.log('그룹 참여 시도: $code');
      
      // 실제 그룹 참여 API 호출
      final authService = AuthService();
      final response = await authService.joinHousehold(inviteCode: code);

      if (mounted) {
        if (response.isSuccess) {
          // 성공 시 householdId 저장
          if (response.result?.id != null) {
            await StorageService.setHouseholdId(response.result!.id.toString());
            DebugHelper.log('그룹 참여 성공: householdId=${response.result!.id}');
          }

          // 새로고침 후에도 홈으로 라우팅되도록 역할 갱신 (참여자 → MEMBER)
          await StorageService.setUserRole('MEMBER');

          setState(() {
            _resultMessage = '그룹 참여가 완료되었습니다.';
            _isSuccess = true;
            _isLoading = false;
          });

          // 온보딩 완료 처리
          await StorageService.setOnboardingCompleted(true);

          // 성공 시 설문 화면으로 이동
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(AppRouter.preferenceSurvey);
          }
        } else {
          // API 응답에서 에러 메시지 표시
          setState(() {
            _resultMessage = response.message.isNotEmpty 
                ? response.message 
                : '그룹 참여에 실패했습니다.';
            _isSuccess = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      DebugHelper.log('그룹 참여 오류: $e');
      
      if (mounted) {
        String errorMessage = '그룹 참여 중 오류가 발생했습니다.';
        
        // 에러 메시지에서 더 구체적인 정보 추출
        final errorString = e.toString();
        if (errorString.contains('404') || errorString.contains('존재하지')) {
          errorMessage = '해당 그룹 코드는 존재하지 않습니다.';
        } else if (errorString.contains('400') || errorString.contains('잘못된')) {
          errorMessage = '잘못된 그룹 코드입니다.';
        } else if (errorString.contains('403') || errorString.contains('권한')) {
          errorMessage =
              '그룹 참여가 거부되었어요. 나간 직후라면 잠시 후 다시 시도하거나, '
              '로그아웃 후 다시 로그인해 주세요. 계속되면 문의를 남겨주세요.';
        } else if (errorString.contains('409') || errorString.contains('이미')) {
          errorMessage = '이미 해당 그룹에 참여 중입니다.';
        }
        
        setState(() {
          _resultMessage = errorMessage;
          _isSuccess = false;
          _isLoading = false;
        });
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
                    const AuthFlowLogo(),
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
                  '그룹 코드를 입력해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // 그룹 코드 입력 필드
                GlassmorphismInputField(
                  controller: _codeController,
                  hintText: '그룹 코드',
                  autofocus: true,
                  width: AuthFlowTokens.fieldWidth,
                  height: AuthFlowTokens.fieldHeight,
                ),
                const SizedBox(height: 16),
                // 확인 버튼
                _isLoading
                    ? const SizedBox(
                        width: 183,
                        height: AuthFlowTokens.actionButtonHeight,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    : ListenableBuilder(
                        listenable: _codeController,
                        builder: (context, _) {
                          final hasCode =
                              _codeController.text.trim().isNotEmpty;
                          return GlassmorphismButton(
                            text: '확인',
                            onTap: hasCode ? _handleSubmit : null,
                            width: 183,
                            height: 31,
                            enabled: hasCode,
                          );
                        },
                      ),
                // 결과 메시지
                if (_resultMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _resultMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isSuccess ? HomeShareStyle.point : Colors.red,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

