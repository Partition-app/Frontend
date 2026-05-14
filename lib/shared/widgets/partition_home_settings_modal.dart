import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/models/household_response_model.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/auth/services/kakao_auth_service.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 홈 탭 「설정」— 그룹 리더 여부·그룹 코드·계정 관련 동작
class PartitionHomeSettingsModal extends StatefulWidget {
  const PartitionHomeSettingsModal({super.key});

  @override
  State<PartitionHomeSettingsModal> createState() =>
      _PartitionHomeSettingsModalState();
}

class _PartitionHomeSettingsModalState extends State<PartitionHomeSettingsModal> {
  final AuthService _authService = AuthService();
  HouseholdResponseModel? _household;
  bool _loading = true;

  static const Color _destructiveMuted = Color(0xFFD88A94);
  @override
  void initState() {
    super.initState();
    _loadHousehold();
  }

  Future<void> _loadHousehold() async {
    setState(() => _loading = true);
    final res = await _authService.fetchMyHousehold();
    if (!mounted) return;
    final role = res?.result?.role?.trim();
    if (role != null && role.isNotEmpty) {
      await StorageService.setUserRole(role);
    }
    if (!mounted) return;
    setState(() {
      _household = res;
      _loading = false;
    });
  }

  bool get _isLeader {
    final r = _household?.result?.role?.trim().toUpperCase();
    if (r == 'LEADER') return true;
    if (r == null || r.isEmpty) {
      return StorageService.getUserRole()?.toUpperCase() == 'LEADER';
    }
    return false;
  }

  String get _groupCode {
    final c = _household?.result?.code?.trim();
    if (c != null && c.isNotEmpty) return c;
    return '—';
  }

  /// 서버에 저장된 그룹명(없으면 null)
  String? get _trimmedHouseholdName {
    final n = _household?.result?.name?.trim();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  /// 설정 상단에만 쓰는 표시용 그룹명(미설정 시 플레이스홀더)
  String get _groupNameDisplay => _trimmedHouseholdName ?? '미설정';

  Future<void> _copyGroupCode(BuildContext ctx) async {
    final code = _groupCode;
    if (code == '—') {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('복사할 그룹 코드가 없습니다.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('그룹 코드를 복사했습니다.')),
    );
  }

  Future<bool> _confirm(
    BuildContext ctx, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        constraints: const BoxConstraints(maxWidth: 360),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        fillColor: const Color.fromRGBO(255, 255, 255, 0.12),
        borderColor: const Color.fromRGBO(255, 255, 255, 0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(c).pop(false),
                  color: Colors.white.withOpacity(0.88),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 14,
                height: 1.45,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 20),
            _confirmDialogButton(
              label: '취소',
              foregroundColor: PartitionUiTokens.actionText,
              onTap: () => Navigator.of(c).pop(false),
            ),
            const SizedBox(height: 10),
            _confirmDialogButton(
              label: confirmLabel,
              foregroundColor: destructive
                  ? _destructiveMuted
                  : PartitionUiTokens.actionText,
              onTap: () => Navigator.of(c).pop(true),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _onLogout(BuildContext ctx) async {
    final ok =
        await _confirm(ctx,
            title: '로그아웃',
            message: '로그아웃할까요?',
            confirmLabel: '로그아웃');
    if (!ok || !mounted) return;
    try {
      try {
        await KakaoAuthService.logout();
      } catch (_) {}
      // ignore: use_build_context_synchronously
      await ctx.read<AuthProvider>().logout();
    } catch (_) {}
    if (!mounted || !ctx.mounted) return;
    Navigator.of(ctx, rootNavigator: true).pushNamedAndRemoveUntil(
      AppRouter.login,
      (_) => false,
    );
  }

  Future<void> _onLeaveGroup(BuildContext ctx) async {
    final ok =
        await _confirm(ctx,
            title: '그룹 나가기',
            message:
                '이 파티션 그룹에서 나가요. 같은 그룹에 다시 들어오려면 그룹 코드가 필요합니다.',
            confirmLabel: '나가기',
            destructive: true);
    if (!ok || !mounted) return;

    try {
      await _authService.leaveHouseholdAndSyncSession();
    } catch (e) {
      if (!ctx.mounted) return;
      final msg = e is ApiException ? e.message : '그룹 나가기에 실패했어요.';
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    if (!ctx.mounted) return;
    Navigator.of(ctx, rootNavigator: true).pushNamedAndRemoveUntil(
      AppRouter.groupSelection,
      (_) => false,
    );
  }

  Future<void> _onDeleteAccount(BuildContext ctx) async {
    if (_isLeader) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            '그룹 리더는 탈퇴할 수 없어요. 그룹장을 위임한 후 탈퇴해 주세요.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ok =
        await _confirm(ctx,
            title: '회원 탈퇴',
            message:
                '그룹에서 탈퇴하고 로그아웃해요.\n계속 진행할까요?',
            confirmLabel: '탈퇴',
            destructive: true);
    if (!ok || !mounted) return;

    try {
      await ctx.read<AuthProvider>().withdrawAccount();
    } catch (e) {
      if (!ctx.mounted) return;
      final msg = e is ApiException ? e.message : '회원 탈퇴에 실패했어요.';
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    try {
      await KakaoAuthService.logout();
    } catch (_) {}
    if (!ctx.mounted) return;
    Navigator.of(ctx, rootNavigator: true).pushNamedAndRemoveUntil(
      AppRouter.login,
      (_) => false,
    );
  }

  Widget _dangerButton(BuildContext ctx, String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.05),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: _destructiveMuted,
                fontSize: PartitionUiTokens.actionFontSize,
                fontWeight: PartitionUiTokens.actionWeight,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _confirmDialogButton({
    required String label,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.05),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: PartitionUiTokens.actionFontSize,
                fontWeight: PartitionUiTokens.actionWeight,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupSettingsRow(
    BuildContext ctx, {
    required String title,
    String? caption,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: PartitionUiTokens.surfaceFillMuted,
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: PartitionUiTokens.surfaceBorderMuted),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard Variable',
                          height: 1.25,
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          caption,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            fontFamily: 'Pretendard Variable',
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.45),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRenameGroup(BuildContext ctx) async {
    final initial = _trimmedHouseholdName ?? '';
    final newName = await showDialog<String>(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => _RenameHouseholdNameDialog(initialName: initial),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    try {
      await _authService.updateHouseholdName(name: newName);
      await _loadHousehold();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('그룹명을 변경했어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      final msg = e is ApiException ? e.message : '그룹명 변경에 실패했어요.';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _onTransferLeader(BuildContext ctx) async {
    final pickedId = await showDialog<int>(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => _PickNewLeaderDialog(authService: _authService),
    );
    if (pickedId == null || !mounted) return;

    final ok = await _confirm(
      ctx,
      title: '그룹장 변경',
      message: '선택한 그룹원에게 그룹장을 넘길까요?\n이후에는 그룹원으로 참여해요.',
      confirmLabel: '넘기기',
    );
    if (!ok || !mounted) return;

    try {
      await _authService.transferHouseholdLeadership(targetUserId: pickedId);
      await _loadHousehold();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('그룹장을 변경했어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      final msg = e is ApiException ? e.message : '그룹장 변경에 실패했어요.';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _mutedButton(BuildContext ctx, String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: PartitionUiTokens.actionButtonBorder),
              color: PartitionUiTokens.actionButtonFill,
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: PartitionUiTokens.actionText,
                fontSize: PartitionUiTokens.actionFontSize,
                fontWeight: PartitionUiTokens.actionWeight,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 40),
                        const Expanded(
                          child: Text(
                            '설정',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Pretendard Variable',
                            ),
                          ),
                        ),
                        PartitionModalCloseButton(
                          onPressed: () => Navigator.of(context).pop(),
                          color: Colors.white.withOpacity(0.88),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                      )
                    else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _groupNameDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 19.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Pretendard Variable',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _onRenameGroup(context),
                              borderRadius: BorderRadius.circular(
                                PartitionUiTokens.fieldRadius,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  PartitionUiTokens.fieldRadius,
                                ),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        PartitionUiTokens.fieldRadius,
                                      ),
                                      border: Border.all(
                                        color:
                                            Colors.white.withOpacity(0.28),
                                        width: 0.5,
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.14),
                                          Colors.white.withOpacity(0.06),
                                        ],
                                      ),
                                    ),
                                    child: const Text(
                                      '변경',
                                      style: TextStyle(
                                        fontSize:
                                            PartitionUiTokens.actionFontSize,
                                        fontWeight:
                                            PartitionUiTokens.actionWeight,
                                        fontFamily: 'Pretendard Variable',
                                        color: HomeShareStyle.point,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _isLeader
                                ? Icons.manage_accounts_rounded
                                : Icons.person_outline_rounded,
                            size: 20,
                            color: Colors.white.withOpacity(0.75),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isLeader ? '그룹 리더예요.' : '그룹 리더가 아니에요. (그룹원)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 13,
                                height: 1.35,
                                fontFamily: 'Pretendard Variable',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '그룹 코드',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _copyGroupCode(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: PartitionUiTokens.surfaceFillSoft,
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.fieldRadius,
                            ),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.16)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _groupCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Pretendard Variable',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.copy_rounded,
                                size: 20,
                                color: Colors.white.withOpacity(0.65),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '탭하면 코드가 복사돼요.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _groupSettingsRow(
                        context,
                        title: '그룹장 변경하기',
                        caption: '그룹장만 가능',
                        enabled: _isLeader,
                        onTap: _isLeader
                            ? () => _onTransferLeader(context)
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('그룹장만 그룹장을 변경할 수 있어요.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                      ),
                      const SizedBox(height: 22),
                      _mutedButton(context, '로그아웃',
                          () => _onLogout(context)),
                      const SizedBox(height: 10),
                      _dangerButton(context, '그룹 나가기',
                          () => _onLeaveGroup(context)),
                      const SizedBox(height: 10),
                      _dangerButton(context, '회원 탈퇴',
                          () => _onDeleteAccount(context)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 설정 모달과 동일한 서브 다이얼로그 스타일 ─────────────────────────────────

PartitionGlassDialog _wrapSettingsSubdialog(Widget child) {
  return PartitionGlassDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20),
    constraints: const BoxConstraints(maxWidth: 360),
    borderRadius: BorderRadius.circular(24),
    blurSigma: 18,
    fillColor: const Color.fromRGBO(255, 255, 255, 0.12),
    borderColor: const Color.fromRGBO(255, 255, 255, 0.22),
    gradient: const LinearGradient(
      colors: [Colors.transparent, Colors.transparent],
    ),
    boxShadow: const [],
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
    child: child,
  );
}

class _SettingsSubdialogHeader extends StatelessWidget {
  const _SettingsSubdialogHeader({
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 40),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              fontFamily: 'Pretendard Variable',
            ),
          ),
        ),
        PartitionModalCloseButton(
          onPressed: onClose,
          color: Colors.white.withOpacity(0.88),
        ),
      ],
    );
  }
}

class _SettingsSubdialogButton extends StatelessWidget {
  const _SettingsSubdialogButton({
    required this.label,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: PartitionUiTokens.actionButtonHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.05),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: PartitionUiTokens.actionFontSize,
                fontWeight: PartitionUiTokens.actionWeight,
                fontFamily: 'Pretendard Variable',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSubdialogTextField extends StatelessWidget {
  const _SettingsSubdialogTextField({
    required this.controller,
    required this.hintText,
    this.maxLength,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PartitionUiTokens.actionButtonHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: PartitionUiTokens.surfaceFillMuted,
        borderRadius: BorderRadius.circular(PartitionUiTokens.fieldRadius),
        border: Border.all(color: PartitionUiTokens.surfaceBorderMuted),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: PartitionUiTokens.actionFontSize,
          fontFamily: 'Pretendard Variable',
          height: 1.0,
        ),
        strutStyle: const StrutStyle(
          fontSize: PartitionUiTokens.actionFontSize,
          height: 1.0,
          forceStrutHeight: true,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: PartitionUiTokens.actionFontSize,
            fontFamily: 'Pretendard Variable',
            height: 1.0,
          ),
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _RenameHouseholdNameDialog extends StatefulWidget {
  const _RenameHouseholdNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameHouseholdNameDialog> createState() =>
      _RenameHouseholdNameDialogState();
}

class _RenameHouseholdNameDialogState extends State<_RenameHouseholdNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _controller.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('그룹명을 입력해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return _wrapSettingsSubdialog(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSubdialogHeader(
            title: '그룹명 변경',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 14),
          _SettingsSubdialogTextField(
            controller: _controller,
            hintText: '새 그룹명',
            maxLength: 40,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          _SettingsSubdialogButton(
            label: '취소',
            foregroundColor: PartitionUiTokens.actionText,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 10),
          _SettingsSubdialogButton(
            label: '저장',
            foregroundColor: HomeShareStyle.point,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

class _PickNewLeaderDialog extends StatefulWidget {
  const _PickNewLeaderDialog({required this.authService});

  final AuthService authService;

  @override
  State<_PickNewLeaderDialog> createState() => _PickNewLeaderDialogState();
}

class _PickNewLeaderDialogState extends State<_PickNewLeaderDialog> {
  bool _loading = true;
  String? _error;
  List<HouseholdMemberBrief> _candidates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = await widget.authService.getResolvedCurrentUserId();
      final all = await widget.authService.fetchHouseholdMembers();
      final filtered = <HouseholdMemberBrief>[];
      for (final m in all) {
        if (myId != null && m.userId == myId) continue;
        filtered.add(m);
      }
      if (!mounted) return;
      setState(() {
        _candidates = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '멤버 목록을 불러오지 못했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _wrapSettingsSubdialog(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSubdialogHeader(
            title: '그룹장 변경',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.maxFinite,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  )
                : _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 14,
                              height: 1.45,
                              fontFamily: 'Pretendard Variable',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SettingsSubdialogButton(
                            label: '다시 시도',
                            foregroundColor: PartitionUiTokens.actionText,
                            onTap: _load,
                          ),
                        ],
                      )
                    : _candidates.isEmpty
                        ? Text(
                            '그룹장을 넘길 다른 그룹원이 없어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 14,
                              height: 1.45,
                              fontFamily: 'Pretendard Variable',
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _candidates.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final m = _candidates[i];
                                final roleLabel =
                                    m.role == 'LEADER' ? '리더' : '멤버';
                                final initial = m.name.isNotEmpty
                                    ? m.name.characters.first
                                    : '?';
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      PartitionUiTokens.actionButtonRadius,
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(m.userId),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: PartitionUiTokens
                                            .surfaceFillMuted,
                                        borderRadius: BorderRadius.circular(
                                          PartitionUiTokens
                                              .actionButtonRadius,
                                        ),
                                        border: Border.all(
                                          color: PartitionUiTokens
                                              .surfaceBorderMuted,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Colors.white
                                                .withOpacity(0.08),
                                            foregroundImage:
                                                m.profileImage != null
                                                    ? NetworkImage(
                                                        m.profileImage!)
                                                    : null,
                                            child: Text(
                                              initial,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                fontFamily:
                                                    'Pretendard Variable',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  m.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily:
                                                        'Pretendard Variable',
                                                    height: 1.25,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  roleLabel,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.5),
                                                    fontSize: 12,
                                                    fontFamily:
                                                        'Pretendard Variable',
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.white
                                                .withOpacity(0.45),
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          const SizedBox(height: 20),
          _SettingsSubdialogButton(
            label: '닫기',
            foregroundColor: PartitionUiTokens.actionText,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
