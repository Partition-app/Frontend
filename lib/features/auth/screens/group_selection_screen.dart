import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';

class GroupSelectionScreen extends StatefulWidget {
  const GroupSelectionScreen({super.key});

  @override
  State<GroupSelectionScreen> createState() => _GroupSelectionScreenState();
}

class _GroupSelectionScreenState extends State<GroupSelectionScreen> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final name = await StorageService.getUserName();
    if (mounted) {
      setState(() {
        _userName = name;
      });
    }
  }

  /// 이미 그룹에 속해 있으면 홈으로 이동하고 true 반환, 아니면 false 반환
  Future<bool> _redirectIfAlreadyInGroup() async {
    final householdId = await StorageService.getHouseholdId();
    if (householdId != null && householdId.isNotEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRouter.partitionMain);
      }
      return true;
    }
    return false;
  }

  Future<void> _handleEnterGroupCode() async {
    if (await _redirectIfAlreadyInGroup()) return;
    if (mounted) {
      Navigator.of(context).pushNamed(AppRouter.enterGroupCode);
    }
  }

  Future<void> _handleCreateNewGroup() async {
    if (await _redirectIfAlreadyInGroup()) return;
    if (mounted) {
      Navigator.of(context).pushNamed(AppRouter.createGroup);
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
                Text(
                  _userName != null
                      ? '$_userName님, 반갑습니다. 혹시 이미 속해있는 파티션 그룹이 있나요? 아니면, 그룹을 새로 만드시겠어요?'
                      : '반갑습니다. 혹시 이미 속해있는 파티션 그룹이 있나요? 아니면, 그룹을 새로 만드시겠어요?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // 그룹 코드 입력하기 버튼
                GlassmorphismButton(
                  text: '그룹 코드 입력하기',
                  onTap: _handleEnterGroupCode,
                  width: 183,
                  height: 31,
                ),
                const SizedBox(height: 12),
                // 새로운 그룹 만들기 버튼
                GlassmorphismButton(
                  text: '새로운 그룹 만들기',
                  onTap: _handleCreateNewGroup,
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

