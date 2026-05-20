import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partition_app/core/config/app_config.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/features/partition/providers/home_share_provider.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/models/household_response_model.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/partition/services/geocoding_service.dart';
import 'package:partition_app/shared/widgets/home_calendar_widget.dart';
import 'package:partition_app/shared/widgets/primary_button.dart';
import 'package:partition_app/shared/widgets/chore_assignment_modal.dart';
import 'package:partition_app/shared/widgets/chore_manual_assignment_modal.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/schedule_registration_modal.dart';
import 'package:partition_app/shared/widgets/partition_home_settings_modal.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// [HouseholdResult]의 `role` / `isLeader`와 로컬에 캐시된 역할로 방장 여부를 판별합니다.
bool _isUserHouseholdLeader({HouseholdResult? result}) {
  final r = result?.role?.trim().toUpperCase();
  if (r == 'LEADER') return true;
  if (result?.isLeader == true) return true;
  if (r == 'MEMBER' || result?.isLeader == false) return false;
  final cached = StorageService.getUserRole()?.toUpperCase();
  if (cached == 'LEADER') return true;
  if (cached == 'MEMBER') return false;
  return false;
}

/// 귀가 공유 API(동의·집 위치·알림 전송) 실패 시 서버 메시지를 스낵바로 한 번 표시합니다.
void _showHomeShareServerNoticeIfAny(BuildContext context) {
  if (!context.mounted) return;
  final provider = context.read<HomeShareProvider>();
  final msg = provider.serverNotice;
  if (msg == null) return;
  provider.clearServerNotice();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class PartitionHomeScreen extends StatefulWidget {
  const PartitionHomeScreen({super.key});

  @override
  State<PartitionHomeScreen> createState() => _PartitionHomeScreenState();
}

class _PartitionHomeScreenState extends State<PartitionHomeScreen> {
  static const double _contentTopOffset = 10.0;
  /// [PartitionSharedExpenseScreen] 등과 동일 — 하단 글래스 탭바·노치와 겹침 방지
  static const double _contentPaddingBottom = 16.0;
  static const double _scrollBottomInsetForTabBar = 147.0;
  static const double _scrollExtraTailSpace = 56.0;

  final AuthService _authService = AuthService();
  bool _isHouseholdLeader =
      StorageService.getUserRole()?.toUpperCase() == 'LEADER';

  DateTime _selectedDate = DateTime.now();
  final GlobalKey<HomeCalendarWidgetState> _calendarKey =
      GlobalKey<HomeCalendarWidgetState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<HomeShareProvider>().initialize());
      unawaited(_refreshHouseholdLeader());
    });
  }

  /// `GET /households/me`로 방장 여부를 갱신합니다 (설정 모달과 동일하게 역할을 로컬에 저장).
  Future<void> _refreshHouseholdLeader() async {
    final res = await _authService.fetchMyHousehold();
    if (!mounted) return;
    final role = res?.result?.role?.trim();
    if (role != null && role.isNotEmpty) {
      await StorageService.setUserRole(role);
    }
    if (!mounted) return;
    setState(() {
      _isHouseholdLeader = _isUserHouseholdLeader(result: res?.result);
    });
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
  }

  void _refreshCalendar() {
    _calendarKey.currentState?.refreshCalendar();
  }

  void _onPointerDownOutsideCalendar(PointerDownEvent event) {
    final ctx = _calendarKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    if (rect.contains(event.position)) return;
    _calendarKey.currentState?.collapseWeekDetailIfShowing();
  }

  Future<void> _onPullToRefresh() async {
    _calendarKey.currentState?.refreshCalendar();
    if (mounted) {
      await Future.wait([
        context.read<HomeShareProvider>().refreshRoommateNearHomeFromServer(),
        _refreshHouseholdLeader(),
      ]);
    }
  }

  void _showScheduleRegistrationModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => ScheduleRegistrationModal(
        selectedDate: _selectedDate,
        onSuccess: _refreshCalendar,
      ),
    );
  }

  void _showChoreAssignmentModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => ChoreAssignmentModal(
        onSuccess: _refreshCalendar,
      ),
    );
  }

  void _showChoreManualAssignmentModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => ChoreManualAssignmentModal(
        onSuccess: _refreshCalendar,
      ),
    );
  }

  void _showSettingsModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierDismissible: true,
      builder: (context) => const PartitionHomeSettingsModal(),
    );
  }

  // ── 집 위치 변경 ──────────────────────────────────────────────────────────

  Future<void> _onEditHomeLocation(BuildContext context) async {
    await _refreshHouseholdLeader();
    if (!context.mounted) return;
    if (!_isHouseholdLeader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('집 위치는 그룹 방장만 변경할 수 있어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => const _HomeLocationChangeDialog(),
    );
  }

  // ── 귀가 공유 토글 처리 ────────────────────────────────────────────────────

  Future<void> _onToggleSharing(BuildContext context) async {
    final provider = context.read<HomeShareProvider>();

    if (provider.isEnabled) {
      await provider.disableSharing();
      if (context.mounted) {
        _showHomeShareServerNoticeIfAny(context);
      }
      return;
    }

    // 집 위치가 없으면 서버(가구 공용) 좌표 먼저 시도 후 설정 다이얼로그
    if (provider.homeLocation == null) {
      await provider.ensureHomeLocationFromServer();
    }
    if (provider.homeLocation == null) {
      await _refreshHouseholdLeader();
      if (!context.mounted) return;
      final bool set = await _showHomeSetupDialog(
        context,
        canChangeHouseholdHomeLocation: _isHouseholdLeader,
      );
      if (!set) return;
      if (context.mounted) {
        _showHomeShareServerNoticeIfAny(context);
      }
    }

    final bool success = await provider.enableSharing();
    if (!success && context.mounted) {
      // ignore: use_build_context_synchronously
      _showEnableFailFeedback(context);
    } else if (context.mounted) {
      _showHomeShareServerNoticeIfAny(context);
    }
  }

  Future<bool> _showHomeSetupDialog(
    BuildContext context, {
    required bool canChangeHouseholdHomeLocation,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => _HomeLocationSetupDialog(
        canChangeHouseholdHomeLocation: canChangeHouseholdHomeLocation,
      ),
    );
    return result ?? false;
  }

  Future<void> _showEnableFailFeedback(BuildContext context) async {
    final perm = await Permission.location.status;
    if (!context.mounted) return;
    if (perm.isPermanentlyDenied) {
      _showPermissionDeniedDialog(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('위치 서비스 또는 권한이 필요합니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Transform.translate(
        offset: const Offset(0, -10),
        child: _PartitionGlassModalCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    const Expanded(
                      child: Text(
                        '위치 권한 필요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Pretendard Variable',
                          height: 1.15,
                        ),
                      ),
                    ),
                    PartitionModalCloseButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '귀가 공유를 사용하려면 위치 권한이 필요합니다.\n'
                  '설정 > ${AppConfig.appName} > 위치에서 허용해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 14,
                    height: 1.5,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          '취소',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await Geolocator.openAppSettings();
                        },
                        child: Text(
                          '설정 열기',
                          style: TextStyle(
                            color: HomeShareStyle.point.withOpacity(0.95),
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard Variable',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── UI 빌드 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final screenWidth = mediaSize.width;
    // 태블릿(가로 기준): 짧은 변이 600 이상일 때 — 캘린더/버튼 폭과 버튼 높이를 키운다.
    final isTablet = mediaSize.shortestSide >= 600;
    final availableButtonWidth = screenWidth - 32;
    // 캘린더 폭과 동일하게 맞춰 시각적 정렬 보장.
    final buttonWidth = math.min(
      availableButtonWidth,
      HomeCalendarWidget.maxContentWidth,
    );
    final buttonHeight = isTablet ? 64.0 : PartitionUiTokens.actionButtonHeight;
    final buttonGap = isTablet ? 14.0 : 10.0;
    final scrollBottomPadding = _contentPaddingBottom +
        MediaQuery.viewPaddingOf(context).bottom +
        _scrollBottomInsetForTabBar +
        _scrollExtraTailSpace;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _onPullToRefresh,
        color: Colors.white,
        backgroundColor: Colors.white.withOpacity(0.15),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          _contentTopOffset,
          16,
          scrollBottomPadding,
        ),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDownOutsideCalendar,
          child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top),
            Image.asset(
              'assets/icons/partition-logo-mini.png',
              width: 56 * 0.7,
              height: 56 * 0.7,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 26),
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final calWidth = HomeCalendarWidget.resolveContentWidth(
                    constraints.maxWidth,
                  );
                  final calHeight = HomeCalendarWidget.resolveMonthViewHeight(
                    outerWidth: calWidth,
                  );
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: calWidth,
                      height: calHeight,
                      child: HomeCalendarWidget(
                        key: _calendarKey,
                        onDateSelected: _onDateSelected,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: buttonGap),
            PrimaryButton(
              label: '일정 등록하기',
              width: buttonWidth,
              height: buttonHeight,
              onPressed: () => _showScheduleRegistrationModal(context),
            ),
            SizedBox(height: buttonGap),
            PrimaryButton(
              label: 'AI 집안일 배정',
              width: buttonWidth,
              height: buttonHeight,
              onPressed: () => _showChoreAssignmentModal(context),
            ),
            SizedBox(height: buttonGap),
            PrimaryButton(
              label: '집안일 직접 배정',
              width: buttonWidth,
              height: buttonHeight,
              onPressed: () => _showChoreManualAssignmentModal(context),
            ),
            SizedBox(height: buttonGap),
            PrimaryButton(
              label: '설정',
              width: buttonWidth,
              height: buttonHeight,
              onPressed: () => _showSettingsModal(context),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: _HomeShareCard(
                onToggle: () => _onToggleSharing(context),
                onEditLocation: () => _onEditHomeLocation(context),
                canEditHomeLocation: _isHouseholdLeader,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 홈 설정 모달과 동일한 글래스 카드 셸
// ─────────────────────────────────────────────────────────────────────────────

class _PartitionGlassModalCard extends StatelessWidget {
  const _PartitionGlassModalCard({
    required this.child,
    this.maxWidth = 350,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final capWidth = math.min(maxWidth, math.max(280.0, screenW - 40));

    return PartitionGlassDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(
        maxWidth: capWidth,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.12),
      borderColor: const Color.fromRGBO(255, 255, 255, 0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 귀가 공유 토글 카드
// ─────────────────────────────────────────────────────────────────────────────

class _HomeShareUiState {
  const _HomeShareUiState({
    required this.enabled,
    required this.nearHome,
    required this.loading,
    required this.hasHome,
    required this.canEditHomeLocation,
  });

  final bool enabled;
  final bool nearHome;
  final bool loading;
  final bool hasHome;
  final bool canEditHomeLocation;

  @override
  bool operator ==(Object other) =>
      other is _HomeShareUiState &&
      enabled == other.enabled &&
      nearHome == other.nearHome &&
      loading == other.loading &&
      hasHome == other.hasHome &&
      canEditHomeLocation == other.canEditHomeLocation;

  @override
  int get hashCode =>
      Object.hash(enabled, nearHome, loading, hasHome, canEditHomeLocation);
}

class _HomeShareCard extends StatelessWidget {
  const _HomeShareCard({
    required this.onToggle,
    required this.onEditLocation,
    required this.canEditHomeLocation,
  });

  final VoidCallback onToggle;
  final VoidCallback onEditLocation;
  final bool canEditHomeLocation;

  @override
  Widget build(BuildContext context) {
    return Selector<HomeShareProvider, _HomeShareUiState>(
      selector: (_, provider) => _HomeShareUiState(
        enabled: provider.isEnabled,
        nearHome: provider.isNearHome,
        loading: provider.isLoading,
        hasHome: provider.homeLocation != null,
        canEditHomeLocation: canEditHomeLocation,
      ),
      builder: (context, state, _) => _HomeShareCardBody(
        enabled: state.enabled,
        nearHome: state.nearHome,
        loading: state.loading,
        hasHome: state.hasHome,
        canEditHomeLocation: state.canEditHomeLocation,
        onToggle: onToggle,
        onEditLocation: onEditLocation,
      ),
    );
  }
}

class _HomeShareCardBody extends StatelessWidget {
  const _HomeShareCardBody({
    required this.enabled,
    required this.nearHome,
    required this.loading,
    required this.hasHome,
    required this.canEditHomeLocation,
    required this.onToggle,
    required this.onEditLocation,
  });

  final bool enabled;
  final bool nearHome;
  final bool loading;
  final bool hasHome;
  final bool canEditHomeLocation;
  final VoidCallback onToggle;
  final VoidCallback onEditLocation;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = !enabled
        ? Colors.white.withOpacity(0.5)
        : (nearHome
            ? HomeShareStyle.point
            : HomeShareStyle.point.withOpacity(0.72));

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(enabled ? 0.14 : 0.09),
                HomeShareStyle.main.withOpacity(enabled ? 0.22 : 0.14),
              ],
            ),
            border: Border.all(
              width: 1,
              color: enabled
                  ? HomeShareStyle.pointStroke(nearHome ? 0.42 : 0.28)
                  : Colors.white.withOpacity(0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: HomeShareStyle.main.withOpacity(enabled ? 0.18 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // 아이콘
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: enabled
                          ? HomeShareStyle.pointFillSoft(0.16)
                          : HomeShareStyle.main.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: enabled
                            ? HomeShareStyle.point.withOpacity(0.22)
                            : Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Icon(
                      enabled && nearHome
                          ? Icons.home_rounded
                          : Icons.directions_walk_rounded,
                      color: enabled
                          ? accentColor
                          : Colors.white.withOpacity(0.55),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 텍스트
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '귀가 공유',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _statusLabel(enabled, nearHome, hasHome),
                          style: TextStyle(
                            color: enabled
                                ? accentColor.withOpacity(0.9)
                                : Colors.white.withOpacity(0.45),
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 집 위치 변경 버튼 (방장만 서버 좌표 변경 가능)
                  GestureDetector(
                    onTap: () {
                      if (!canEditHomeLocation) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('집 위치는 그룹 방장만 변경할 수 있어요.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      onEditLocation();
                    },
                    child: Opacity(
                      opacity: canEditHomeLocation ? 1.0 : 0.45,
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(
                            PartitionUiTokens.fieldRadius,
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.16),
                          ),
                        ),
                        child: Icon(
                          Icons.edit_location_alt_rounded,
                          size: 16,
                          color: canEditHomeLocation
                              ? (enabled
                                  ? HomeShareStyle.point.withOpacity(0.82)
                                  : Colors.white.withOpacity(0.5))
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ),
                  // 토글 또는 로딩
                  if (loading)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onToggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 50,
                        height: 28,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: enabled
                              ? HomeShareStyle.point.withOpacity(0.88)
                              : Colors.white.withOpacity(0.14),
                          border: Border.all(
                            color: enabled
                                ? HomeShareStyle.point.withOpacity(0.95)
                                : Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          alignment: enabled
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: enabled
                                  ? HomeShareStyle.main
                                  : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 4,
                                  offset: Offset.zero,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // 집 근처일 때 상태 배지
              if (enabled && nearHome) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: HomeShareStyle.pointFillSoft(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: HomeShareStyle.pointStroke(0.32),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: HomeShareStyle.point,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '룸메이트에게 귀가 알림을 보내고 있어요.',
                        style: TextStyle(
                          color: HomeShareStyle.point.withOpacity(0.96),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(bool enabled, bool nearHome, bool hasHome) {
    if (!enabled) return '룸메이트에게 귀가를 알려요';
    if (!hasHome) return '집 위치가 설정되지 않았어요';
    if (nearHome) return '집 근처에 있어요';
    return '집 밖에서 공유 중이에요';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 집 위치 설정 다이얼로그
// ─────────────────────────────────────────────────────────────────────────────

enum _HomeSetupStage {
  checkingServer,
  showRegisteredHome,
  chooseNewHome,
  loadFailed,
}

class _HomeLocationSetupDialog extends StatefulWidget {
  const _HomeLocationSetupDialog({
    required this.canChangeHouseholdHomeLocation,
  });

  /// 서버 가구 좌표를 새로 저장하거나 바꿀 수 있는지 (그룹 방장만 true).
  final bool canChangeHouseholdHomeLocation;

  @override
  State<_HomeLocationSetupDialog> createState() =>
      _HomeLocationSetupDialogState();
}

class _HomeLocationSetupDialogState extends State<_HomeLocationSetupDialog> {
  _HomeSetupStage _stage = _HomeSetupStage.checkingServer;
  bool _busy = false;
  String? _gpsError;

  ({double lat, double lng, double radius})? _registeredCoords;
  String? _registeredAddress;
  bool _addressLoading = false;
  String? _reverseGeocodeError;

  String? _fetchErrorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_checkServer());
  }

  Future<void> _checkServer() async {
    if (!mounted) return;
    setState(() {
      _stage = _HomeSetupStage.checkingServer;
      _fetchErrorMessage = null;
    });
    final provider = context.read<HomeShareProvider>();
    try {
      final snap = await provider.fetchHomeLocationSnapshot();
      if (!mounted) return;
      final c = snap.coordinates;
      if (c != null) {
        setState(() {
          _stage = _HomeSetupStage.showRegisteredHome;
          _registeredCoords = c;
          _registeredAddress = null;
          _addressLoading = true;
          _reverseGeocodeError = null;
        });
        final (:address, :error) =
            await GeocodingService.reverseGeocodeWithDetails(c.lat, c.lng);
        if (!mounted) return;
        setState(() {
          _addressLoading = false;
          _registeredAddress = address;
          _reverseGeocodeError = error;
        });
      } else {
        setState(() => _stage = _HomeSetupStage.chooseNewHome);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _HomeSetupStage.loadFailed;
        _fetchErrorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _HomeSetupStage.loadFailed;
        _fetchErrorMessage = '집 위치를 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _onUseRegisteredHome() async {
    final c = _registeredCoords;
    if (c == null) return;
    setState(() {
      _busy = true;
      _gpsError = null;
    });
    final provider = context.read<HomeShareProvider>();
    await provider.adoptServerHomeLocation(
      lat: c.lat,
      lng: c.lng,
      radius: c.radius,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _onSetCurrentLocation() async {
    setState(() {
      _busy = true;
      _gpsError = null;
    });

    final provider = context.read<HomeShareProvider>();
    final bool success = await provider.setHomeFromCurrentLocation();

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _gpsError = '현재 위치를 가져오지 못했습니다.\n위치 권한을 확인해주세요.';
      });
    }
  }

  void _goToChooseNewHome() {
    setState(() {
      _stage = _HomeSetupStage.chooseNewHome;
      _gpsError = null;
    });
  }

  void _backToRegisteredHome() {
    if (_registeredCoords == null) return;
    setState(() {
      _stage = _HomeSetupStage.showRegisteredHome;
      _gpsError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PartitionGlassModalCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    _stage == _HomeSetupStage.showRegisteredHome
                        ? '등록된 집 위치'
                        : '집 위치 설정',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.15,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  color: Colors.white.withOpacity(_busy ? 0.35 : 0.9),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_stage == _HomeSetupStage.checkingServer) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '가구에 등록된 집 위치를 확인하는 중이에요…',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 14,
                        height: 1.55,
                        fontFamily: 'Pretendard Variable',
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_stage == _HomeSetupStage.loadFailed) ...[
              Text(
                _fetchErrorMessage ??
                    '등록된 집 위치를 확인하지 못했어요.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 14,
                  height: 1.55,
                  fontFamily: 'Pretendard Variable',
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : _checkServer,
                      child: Text(
                        '다시 시도',
                        style: TextStyle(
                          color: HomeShareStyle.point.withOpacity(0.95),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                    ),
                  ),
                  if (widget.canChangeHouseholdHomeLocation)
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : _goToChooseNewHome,
                        child: Text(
                          '지금 위치로 새로 설정',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (_stage == _HomeSetupStage.showRegisteredHome) ...[
              Text(
                widget.canChangeHouseholdHomeLocation
                    ? '파티션 가구에 이미 저장된 집이 있어요.\n'
                        '아래를 확인한 뒤 그대로 쓰거나 바꿀 수 있어요.'
                    : '파티션 가구에 이미 저장된 집이 있어요.\n'
                        '방장이 등록한 위치예요. 확인 후 귀가 공유를 켜 주세요.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.76),
                  fontSize: 14,
                  height: 1.6,
                  fontFamily: 'Pretendard Variable',
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: HomeShareStyle.point.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(
                    PartitionUiTokens.fieldRadius,
                  ),
                  border: Border.all(
                    color: HomeShareStyle.pointStroke(0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '현재 등록 위치',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_addressLoading)
                      Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '주소 불러오는 중…',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      )
                    else if (_registeredAddress != null &&
                        _registeredAddress!.isNotEmpty)
                      Text(
                        _registeredAddress!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          height: 1.45,
                          decoration: TextDecoration.none,
                        ),
                      )
                    else
                      Text(
                        '위도 ${_registeredCoords?.lat.toStringAsFixed(5)}, '
                        '경도 ${_registeredCoords?.lng.toStringAsFixed(5)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 13,
                          height: 1.45,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    if (_reverseGeocodeError != null &&
                        !_addressLoading &&
                        (_registeredAddress == null ||
                            _registeredAddress!.isEmpty)) ...[
                      const SizedBox(height: 6),
                      Text(
                        '지도에서 주소를 가져오지 못했어요. 좌표만 표시합니다.',
                        style: TextStyle(
                          color: HomeShareStyle.point.withOpacity(0.75),
                          fontSize: 11,
                          height: 1.35,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      '감지 반경 ${_registeredCoords?.radius.round() ?? 300}m',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.48),
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _policyBox(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: PartitionUiTokens.actionButtonHeight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_busy || _addressLoading) ? null : _onUseRegisteredHome,
                    borderRadius: BorderRadius.circular(
                      PartitionUiTokens.actionButtonRadius,
                    ),
                    child: Opacity(
                      opacity: (_busy || _addressLoading) ? 0.55 : 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            PartitionUiTokens.actionButtonRadius,
                          ),
                          border: Border.all(
                            color: PartitionUiTokens.actionButtonBorder,
                          ),
                          color: PartitionUiTokens.actionButtonFill,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_busy)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(
                                Icons.home_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _busy ? '적용 중…' : '이 위치로 귀가 공유 켜기',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: PartitionUiTokens.actionFontSize,
                                fontWeight: PartitionUiTokens.actionWeight,
                                fontFamily: 'Pretendard Variable',
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (widget.canChangeHouseholdHomeLocation)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy ? null : _goToChooseNewHome,
                    child: Text(
                      '다른 위치로 설정',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 14,
                        fontFamily: 'Pretendard Variable',
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
            if (_stage == _HomeSetupStage.chooseNewHome) ...[
              if (_registeredCoords != null) ...[
                TextButton(
                  onPressed: _busy ? null : _backToRegisteredHome,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '← 등록된 집 위치로 돌아가기',
                    style: TextStyle(
                      color: HomeShareStyle.point.withOpacity(0.85),
                      fontSize: 13,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!widget.canChangeHouseholdHomeLocation) ...[
                Text(
                  '가구 집 위치는 그룹 방장만 등록할 수 있어요.\n'
                  '방장에게 요청한 뒤 다시 시도해 주세요.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 14,
                    height: 1.6,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: Text(
                      '나중에 설정하기',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 14,
                        fontFamily: 'Pretendard Variable',
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  '집 반경 300m 안에 들어오면 룸메이트에게\n'
                  '조용한 알림이 전송됩니다.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 14,
                    height: 1.6,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),
                _policyBox(),
                const SizedBox(height: 20),
                if (_gpsError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B2942).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _gpsError!,
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 13,
                        fontFamily: 'Pretendard Variable',
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  width: double.infinity,
                  height: PartitionUiTokens.actionButtonHeight,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _busy ? null : _onSetCurrentLocation,
                      borderRadius: BorderRadius.circular(
                        PartitionUiTokens.actionButtonRadius,
                      ),
                      child: Opacity(
                        opacity: _busy ? 0.55 : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              PartitionUiTokens.actionButtonRadius,
                            ),
                            border: Border.all(
                              color: PartitionUiTokens.actionButtonBorder,
                            ),
                            color: PartitionUiTokens.actionButtonFill,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_busy)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.my_location_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              const SizedBox(width: 8),
                              Text(
                                _busy ? '위치 가져오는 중...' : '현재 위치를 집으로 설정',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: PartitionUiTokens.actionFontSize,
                                  fontWeight: PartitionUiTokens.actionWeight,
                                  fontFamily: 'Pretendard Variable',
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: Text(
                      '나중에 설정하기',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 14,
                        fontFamily: 'Pretendard Variable',
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _policyBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PartitionUiTokens.surfaceBorderMuted,
          width: 0.5,
        ),
        color: PartitionUiTokens.surfaceFillMuted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _policyRow(Icons.check_circle_outline_rounded,
              '"집 근처 도착 여부"만 공유'),
          const SizedBox(height: 6),
          _policyRow(Icons.do_not_disturb_alt_rounded,
              '실시간 위치·이동 경로 비공개'),
          const SizedBox(height: 6),
          _policyRow(Icons.group_rounded,
              '같은 파티션 그룹 룸메이트에게만 전송'),
        ],
      ),
    );
  }

  Widget _policyRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon,
            size: 14, color: HomeShareStyle.point.withOpacity(0.78)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 12,
              fontFamily: 'Pretendard Variable',
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 집 위치 변경 다이얼로그
// ─────────────────────────────────────────────────────────────────────────────

enum _HomeLocViewStage {
  loading,
  hasRegistered,
  noRegistered,
  loadFailed,
}

class _HomeLocationChangeDialog extends StatefulWidget {
  const _HomeLocationChangeDialog();

  @override
  State<_HomeLocationChangeDialog> createState() =>
      _HomeLocationChangeDialogState();
}

class _HomeLocationChangeDialogState extends State<_HomeLocationChangeDialog> {
  final TextEditingController _searchController = TextEditingController();

  _HomeLocViewStage _viewStage = _HomeLocViewStage.loading;
  ({double lat, double lng, double radius})? _registeredCoords;
  String? _registeredAddress;
  bool _addressResolving = false;
  String? _reverseGeocodeError;
  String? _viewLoadError;

  bool _locationLoading = false;
  bool _searchLoading = false;
  List<PlaceSuggestion> _suggestions = [];
  bool _searchedOnce = false;
  String? _error;
  Timer? _debounce;
  bool _apiKeyMissing = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _checkApiKey();
    unawaited(_loadRegisteredFromServer());
  }

  void _checkApiKey() {
    _apiKeyMissing = !GeocodingService.hasApiKey;
  }

  /// 위치 아이콘 탭 시 항상 서버에 등록된 집 좌표를 조회해 표시합니다.
  Future<void> _loadRegisteredFromServer() async {
    if (!mounted) return;
    setState(() {
      _viewStage = _HomeLocViewStage.loading;
      _viewLoadError = null;
      _registeredCoords = null;
      _registeredAddress = null;
      _reverseGeocodeError = null;
      _addressResolving = false;
    });

    final provider = context.read<HomeShareProvider>();
    try {
      final snap = await provider.fetchHomeLocationSnapshot();
      if (!mounted) return;
      final c = snap.coordinates;
      if (c == null) {
        setState(() => _viewStage = _HomeLocViewStage.noRegistered);
        return;
      }

      setState(() {
        _viewStage = _HomeLocViewStage.hasRegistered;
        _registeredCoords = c;
        _addressResolving = true;
      });

      await provider.adoptServerHomeLocation(
        lat: c.lat,
        lng: c.lng,
        radius: c.radius,
      );
      if (!mounted) return;

      final cachedAddress = provider.homeAddress;
      if (cachedAddress != null && cachedAddress.isNotEmpty) {
        setState(() {
          _addressResolving = false;
          _registeredAddress = cachedAddress;
        });
        return;
      }

      final (:address, :error) =
          await GeocodingService.reverseGeocodeWithDetails(c.lat, c.lng);
      if (!mounted) return;
      if (address != null) await provider.updateHomeAddress(address);
      setState(() {
        _addressResolving = false;
        _registeredAddress = address;
        _reverseGeocodeError = error;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _viewStage = _HomeLocViewStage.loadFailed;
        _viewLoadError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _viewStage = _HomeLocViewStage.loadFailed;
        _viewLoadError = '등록된 집 위치를 불러오지 못했습니다.';
      });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _searchLoading = true;
      _searchedOnce = true;
      _error = null;
    });
    final (:results, :error) = await GeocodingService.searchPlaces(query);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _error = error;
      _searchLoading = false;
    });
  }

  Future<void> _onUseCurrentLocation() async {
    setState(() {
      _locationLoading = true;
      _error = null;
    });
    final provider = context.read<HomeShareProvider>();
    final success = await provider.setHomeFromCurrentLocation();
    if (!mounted) return;
    if (success) {
      setState(() => _locationLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('현재 위치로 집이 설정되었어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _showHomeShareServerNoticeIfAny(context);
      await _loadRegisteredFromServer();
    } else {
      setState(() {
        _locationLoading = false;
        _error = '현재 위치를 가져오지 못했습니다.\n위치 권한을 확인해주세요.';
      });
    }
  }

  Future<void> _onSelectPlace(PlaceSuggestion place) async {
    // 카카오 검색 결과에는 좌표가 이미 포함되어 있으므로 별도 상세 조회 불필요
    setState(() {
      _suggestions = [];
      _error = null;
    });
    final provider = context.read<HomeShareProvider>();
    await provider.setHomeFromCoordinates(
        place.lat, place.lng, place.formattedAddress);
    if (!mounted) return;
    _showHomeShareServerNoticeIfAny(context);
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Widget _buildRegisteredLocationCard() {
    final hasAddress =
        _registeredAddress != null && _registeredAddress!.isNotEmpty;
    final coords = _registeredCoords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재 등록된 집 위치',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        if (_viewStage == _HomeLocViewStage.loading)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: HomeShareStyle.main.withOpacity(0.28),
              borderRadius:
                  BorderRadius.circular(PartitionUiTokens.fieldRadius),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '등록된 집 위치 확인 중…',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          )
        else if (_viewStage == _HomeLocViewStage.loadFailed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF8B2942).withOpacity(0.25),
              borderRadius:
                  BorderRadius.circular(PartitionUiTokens.fieldRadius),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _viewLoadError ?? '등록된 집 위치를 불러오지 못했습니다.',
                  style: TextStyle(
                    color: Colors.red.shade300,
                    fontSize: 13,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadRegisteredFromServer,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '다시 불러오기',
                    style: TextStyle(
                      color: HomeShareStyle.point.withOpacity(0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (_viewStage == _HomeLocViewStage.noRegistered)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: HomeShareStyle.main.withOpacity(0.28),
              borderRadius:
                  BorderRadius.circular(PartitionUiTokens.fieldRadius),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              '등록된 집 위치가 없어요.\n아래에서 집 위치를 설정할 수 있어요.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 13,
                height: 1.45,
                decoration: TextDecoration.none,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: hasAddress
                  ? HomeShareStyle.point.withOpacity(0.08)
                  : HomeShareStyle.main.withOpacity(0.28),
              borderRadius:
                  BorderRadius.circular(PartitionUiTokens.fieldRadius),
              border: Border.all(
                color: hasAddress
                    ? HomeShareStyle.pointStroke(0.28)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_addressResolving)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      )
                    else
                      Icon(
                        hasAddress
                            ? Icons.location_on_rounded
                            : Icons.location_searching_rounded,
                        color: hasAddress
                            ? HomeShareStyle.point.withOpacity(0.92)
                            : Colors.white.withOpacity(0.35),
                        size: 18,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _addressResolving
                          ? Text(
                              '주소 불러오는 중…',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                decoration: TextDecoration.none,
                              ),
                            )
                          : hasAddress
                              ? Text(
                                  _registeredAddress!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.88),
                                    fontSize: 13,
                                    height: 1.45,
                                    decoration: TextDecoration.none,
                                  ),
                                )
                              : Text(
                                  '위도 ${coords?.lat.toStringAsFixed(5)}, '
                                  '경도 ${coords?.lng.toStringAsFixed(5)}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.72),
                                    fontSize: 13,
                                    height: 1.45,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                    ),
                  ],
                ),
                if (_reverseGeocodeError != null &&
                    !_addressResolving &&
                    !hasAddress) ...[
                  const SizedBox(height: 6),
                  Text(
                    _reverseGeocodeError!,
                    style: TextStyle(
                      color: Colors.red.shade300.withOpacity(0.95),
                      fontSize: 11,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
                if (coords != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '감지 반경 ${coords.radius.round()}m',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.48),
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    /// 본문만 최대 높이 제한(검색 결과 많을 때). 카드 전체 높이는 내용물에 맞춤.
    final maxScrollBodyHeight = math.max(160.0, screenH * 0.55);

    return _PartitionGlassModalCard(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '집 위치 변경',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.15,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxScrollBodyHeight),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                          _buildRegisteredLocationCard(),

                          // 현재 위치로 설정 버튼
                          SizedBox(
                            width: double.infinity,
                            height: PartitionUiTokens.actionButtonHeight,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _locationLoading
                                    ? null
                                    : _onUseCurrentLocation,
                                borderRadius: BorderRadius.circular(
                                  PartitionUiTokens.actionButtonRadius,
                                ),
                                child: Opacity(
                                  opacity: _locationLoading ? 0.55 : 1.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        PartitionUiTokens.actionButtonRadius,
                                      ),
                                      border: Border.all(
                                        color:
                                            PartitionUiTokens.actionButtonBorder,
                                      ),
                                      color: PartitionUiTokens.actionButtonFill,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_locationLoading)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        else
                                          const Icon(
                                            Icons.my_location_rounded,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _locationLoading
                                              ? '위치 가져오는 중...'
                                              : '현재 위치로 설정',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize:
                                                PartitionUiTokens.actionFontSize,
                                            fontWeight:
                                                PartitionUiTokens.actionWeight,
                                            decoration: TextDecoration.none,
                                            fontFamily: 'Pretendard Variable',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 구분선
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withOpacity(0.15))),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  '또는 주소 검색',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 12,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withOpacity(0.15))),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 검색 입력창
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(
                                PartitionUiTokens.fieldRadius,
                              ),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.15)),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14),
                              decoration: InputDecoration(
                                hintText: _apiKeyMissing
                                    ? '카카오 REST API 키 설정 후 사용 가능'
                                    : '장소 또는 주소를 검색하세요',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: Colors.white.withOpacity(0.38),
                                  size: 20,
                                ),
                                suffixIcon: _searchLoading
                                    ? Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color:
                                                Colors.white.withOpacity(0.4),
                                          ),
                                        ),
                                      )
                                    : _searchController.text.isNotEmpty
                                        ? GestureDetector(
                                            onTap: () {
                                              _searchController.clear();
                                              setState(() {
                                                _suggestions = [];
                                                _searchedOnce = false;
                                              });
                                            },
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: Colors.white
                                                  .withOpacity(0.35),
                                            ),
                                          )
                                        : null,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                enabled: !_apiKeyMissing,
                              ),
                            ),
                          ),

                          // 에러 메시지
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B2942).withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade300,
                                  fontSize: 12,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],

                          // 검색 결과
                          if (_suggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                PartitionUiTokens.fieldRadius,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(
                                    PartitionUiTokens.fieldRadius,
                                  ),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.12)),
                                ),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: _suggestions.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                  itemBuilder: (context, index) {
                                    final place = _suggestions[index];
                                    return InkWell(
                                      onTap: () => _onSelectPlace(place),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on_rounded,
                                              size: 16,
                                              color: HomeShareStyle.point
                                                  .withOpacity(0.75),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    place.mainText,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.92),
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      decoration:
                                                          TextDecoration.none,
                                                    ),
                                                  ),
                                                  if (place.secondaryText
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      place.secondaryText,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.45),
                                                        fontSize: 11,
                                                        decoration:
                                                            TextDecoration.none,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ] else if (_searchedOnce &&
                              !_searchLoading &&
                              _error == null &&
                              _searchController.text.isNotEmpty) ...[
                            // 검색 결과 없음
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                '검색 결과가 없어요',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 13,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
  }
}
