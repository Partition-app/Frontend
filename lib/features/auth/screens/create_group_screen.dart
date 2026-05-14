import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) return;

    // 그룹명 확인 화면으로 이동
    if (mounted) {
      Navigator.of(context).pushNamed(
        AppRouter.confirmGroupName,
        arguments: groupName,
      );
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
                  '새로운 그룹을 만들기 위해\n그룹 명을 입력해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                // 그룹명 입력 칸
                _buildGroupNameInput(),
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

  Widget _buildGroupNameInput() {
    return GlassmorphismInputField(
      controller: _groupNameController,
      hintText: '그룹명',
      autofocus: true,
      width: AuthFlowTokens.fieldWidth,
      height: AuthFlowTokens.fieldHeight,
    );
  }

  Widget _buildConfirmButton() {
    return ListenableBuilder(
      listenable: _groupNameController,
      builder: (context, _) {
        final isEnabled = _groupNameController.text.trim().isNotEmpty;
        return GlassmorphismButton(
          text: '확인',
          onTap: _handleConfirm,
          width: AuthFlowTokens.fieldWidth,
          height: AuthFlowTokens.actionButtonHeight,
          enabled: isEnabled,
        );
      },
    );
  }
}

