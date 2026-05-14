import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';

class GroupCreatedScreen extends StatefulWidget {
  final String groupName;
  final String groupCode;

  const GroupCreatedScreen({
    super.key,
    required this.groupName,
    required this.groupCode,
  });

  @override
  State<GroupCreatedScreen> createState() => _GroupCreatedScreenState();
}

class _GroupCreatedScreenState extends State<GroupCreatedScreen> {
  bool _isCodePressed = false;

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.groupCode));
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('클립보드에 복사되었습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleNext(BuildContext context) async {
    // 설문 화면으로 이동
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed(AppRouter.preferenceSurvey);
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
                const Text(
                  '축하합니다!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '그룹이 생성되었습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // 그룹 코드 표시 (클릭 가능)
                GestureDetector(
                  onTapDown: (_) {
                    setState(() {
                      _isCodePressed = true;
                    });
                  },
                  onTapUp: (_) {
                    setState(() {
                      _isCodePressed = false;
                    });
                    _copyToClipboard(context);
                  },
                  onTapCancel: () {
                    setState(() {
                      _isCodePressed = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    width: 183,
                    height: 31,
                    transform: Matrix4.identity()..scale(_isCodePressed ? 0.95 : 1.0),
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
                          blurRadius: 30,
                          spreadRadius: 0,
                          offset: const Offset(4, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Center(
                          child: Text(
                            '그룹 코드: ${widget.groupCode}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 다음으로 버튼
                GlassmorphismButton(
                  text: '다음으로',
                  onTap: () => _handleNext(context),
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

