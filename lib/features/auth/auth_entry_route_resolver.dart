import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';

/// 로그인·앱 시작 시 진입 화면을 결정합니다.
///
/// 로컬 `household_id`·`userRole`은 기기마다 다를 수 있으므로
/// **항상 서버 `GET /households/me` 결과를 우선**합니다.
class AuthEntryRouteResolver {
  const AuthEntryRouteResolver._();

  static Future<String> resolve() async {
    final authService = AuthService();
    final household = await authService.fetchMyHousehold();
    final householdId = household?.result?.id;
    final inGroup = household != null &&
        household.isSuccess &&
        householdId != null;

    if (inGroup) {
      await StorageService.setHouseholdId(householdId.toString());
      final result = household.result!;
      final serverRole = result.role?.trim().toUpperCase() ??
          (result.isLeader == true
              ? 'LEADER'
              : (result.isLeader == false ? 'MEMBER' : null));
      if (serverRole == 'LEADER' || serverRole == 'MEMBER') {
        await StorageService.setUserRole(serverRole!);
      } else {
        final localRole = StorageService.getUserRole();
        if (localRole != 'LEADER' && localRole != 'MEMBER') {
          await StorageService.setUserRole('MEMBER');
        }
      }
      await StorageService.setOnboardingCompleted(true);

      final userInfo = await authService.getUserInfo();
      final name = userInfo?.name;
      if (name != null && name.isNotEmpty) {
        await StorageService.setUserName(name);
      }
      return AppRouter.partitionMain;
    }

    // 다른 기기에서 그룹 나가기 등 — 서버에 가구 없으면 로컬 캐시 정리
    await StorageService.clearHouseholdAffiliation();

    // 카카오 프로필 닉네임이 아닌, 앱에서 직접 입력한 닉네임이 있을 때만 그룹 선택으로
    if (!await StorageService.hasNicknameSetupCompleted()) {
      return AppRouter.onboardingSurvey;
    }
    return AppRouter.groupSelection;
  }
}
