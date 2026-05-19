import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partition_app/shared/widgets/frosted_panel.dart';
import 'package:partition_app/features/partition/services/calendar_service.dart';
import 'package:partition_app/features/partition/services/chore_service.dart';
import 'package:partition_app/features/partition/models/daily_calendar_response_model.dart';
import 'package:partition_app/core/network/api_exception.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/auth/providers/auth_provider.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/schedule_edit_modal.dart';
import 'package:partition_app/shared/utils/partition_dummy_data_policy.dart';
import 'package:partition_app/features/partition/theme/home_share_style.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/shared/widgets/chore_assignment_common.dart';
import 'package:partition_app/shared/widgets/chore_edit_dialog.dart';

const _kChoreTaskNames = ['설거지', '빨래', '청소', '분리수거'];
const _kOtherMemberNames = ['홍길동', '김민수', '이영희', '박서준'];

/// 홈 화면용 캘린더 위젯
/// 글래스모피즘 효과가 적용된 커스텀 캘린더
class HomeCalendarWidget extends StatefulWidget {
  final ValueChanged<DateTime>? onDateSelected;
  final GlobalKey<HomeCalendarWidgetState>? refreshKey; // 외부에서 갱신하기 위한 키

  /// [FrostedPanel] 기본 패딩과 동일
  static const double frostHorizontalPadding = 56;
  static const double frostVerticalPadding = 48;
  static const double maxContentWidth = 440;
  static const int gridWeekRows = 6;
  static const int gridColumns = 7;
  static const double gridSpacing = 8;
  /// 월 선택 + 요일 헤더 + 간격
  static const double monthHeaderHeight = 94;
  static const double minCellSize = 34;
  static const double maxCellSize = 52;

  const HomeCalendarWidget({
    super.key,
    this.onDateSelected,
    this.refreshKey,
  });

  /// 태블릿 등 넓은 화면에서 캘린더 가로 폭 상한.
  static double resolveContentWidth(double layoutWidth) {
    if (!layoutWidth.isFinite || layoutWidth <= 0) return maxContentWidth;
    return math.min(layoutWidth, maxContentWidth);
  }

  /// 월간 뷰(6주)가 잘리지 않도록 바깥 [SizedBox] 높이를 계산합니다.
  static double resolveMonthViewHeight({
    required double outerWidth,
    double? outerHeight,
  }) {
    final layout = _computeMonthGridLayout(outerWidth, maxHeight: outerHeight);
    return layout.gridHeight + monthHeaderHeight + frostVerticalPadding;
  }

  static _MonthGridLayout _computeMonthGridLayout(
    double maxWidth, {
    double? maxHeight,
  }) {
    final innerWidth = math.max(
      0.0,
      maxWidth - frostHorizontalPadding,
    );
    final cellFromWidth =
        (innerWidth - (gridColumns - 1) * gridSpacing) / gridColumns;

    var cell = cellFromWidth;
    if (maxHeight != null && maxHeight.isFinite && maxHeight > 0) {
      final innerHeight = maxHeight - frostVerticalPadding;
      final gridBudget = innerHeight - monthHeaderHeight;
      if (gridBudget > 0) {
        final cellFromHeight =
            (gridBudget - (gridWeekRows - 1) * gridSpacing) / gridWeekRows;
        cell = math.min(cell, cellFromHeight);
      }
    }

    cell = cell.clamp(minCellSize, maxCellSize);
    final gridHeight =
        gridWeekRows * cell + (gridWeekRows - 1) * gridSpacing;
    return _MonthGridLayout(cellSize: cell, gridHeight: gridHeight);
  }

  @override
  State<HomeCalendarWidget> createState() => HomeCalendarWidgetState();
}

class _MonthGridLayout {
  const _MonthGridLayout({required this.cellSize, required this.gridHeight});

  final double cellSize;
  final double gridHeight;
}

/// HomeCalendarWidget의 State를 public으로 노출 (외부에서 refreshCalendar 호출 가능)
class HomeCalendarWidgetState extends State<HomeCalendarWidget> {
  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime.now();
  DateTime? _detailDate;
  bool _showDetail = false;

  // API에서 가져온 캘린더 데이터 (캐싱)
  Map<String, List<_CalendarEvent>>? _cachedEvents;
  String? _cachedMonthKey;
  bool _isLoading = false;
  final CalendarService _calendarService = CalendarService();
  
  // 일간 상세 데이터 캐싱
  Map<String, List<DailyCalendarItem>>? _cachedDailyEvents;
  String? _cachedDailyDateKey;
  bool _isLoadingDaily = false;
  final ChoreService _choreService = ChoreService();
  final AuthService _authService = AuthService();
  final Set<int> _choreToggleInProgress = {};
  /// 집안일 더미/월간 집계용 담당자 표시명(로그인·로컬 이름)
  String _meNameForChores = '나';
  int? _myUserId;
  /// 월간 더미 집안일(음수 id) 로컬 완료 — 서버와 별개
  final Map<int, bool> _previewChoreCompleted = {};

  /// null: 아직 `didChangeDependencies` 전. true: 디버그·미로그인일 때만 4월 미리보기 더미 합침.
  bool? _partitionDummyActive;

  /// 월간 점 표시용. 4월 미리보기 더미는 디버그·미로그인일 때만 합침.
  Map<String, List<_CalendarEvent>> get _events {
    final base = _cachedEvents ?? {};
    Map<String, List<_CalendarEvent>> combined;
    final injectAprilPreview =
        _partitionDummyActive == true && _currentMonth.month == 4;
    if (injectAprilPreview) {
      combined = Map<String, List<_CalendarEvent>>.from(base);
      combined.addAll(_buildAprilPreviewEvents(_currentMonth.year));
    } else {
      combined = base;
    }
    return _applyPreviewChoreCompletion(combined);
  }

  List<DailyCalendarItem>? _getDailyEvents(String dateKey) {
    return _cachedDailyEvents?[dateKey];
  }

  /// 일간 API `category` 비교용 (공백·대소문자 차이 흡수)
  String _normalizeDailyCategory(String? raw) =>
      (raw ?? '').trim().toUpperCase();

  bool _assigneeNameMatchesMe(String? assignee, String meName) {
    if (assignee == null || assignee.trim().isEmpty) return false;
    final a = assignee.trim().toLowerCase();
    final m = meName.trim().toLowerCase();
    if (a == m) return true;
    // "홍길동 · 설거지" 형태·앞뒤 공백 차이
    if (a.startsWith('$m ·') || a.startsWith('$m·')) return true;
    return false;
  }

  Future<void> _refreshMeIdentity() async {
    var meName = await _resolveMeName();
    int? parsedId;

    try {
      final authUser =
          Provider.of<AuthProvider>(context, listen: false).user;
      if (authUser != null) {
        parsedId = int.tryParse(authUser.id);
        final authName = authUser.name?.trim();
        if (authName != null && authName.isNotEmpty) {
          meName = authName;
        }
      }
    } catch (_) {}

    parsedId ??= int.tryParse(await StorageService.getUserId() ?? '');

    if (!mounted) return;
    setState(() {
      _meNameForChores = meName;
      if (parsedId != null && parsedId > 0) {
        _myUserId = parsedId;
      }
    });
  }

  /// GET `/calendars/daily` — Swagger `isOwner` 우선, 없을 때만 담당자 ID·이름으로 추정
  bool _choreOwnedByMe(DailyCalendarItem item) {
    if (item.isOwner == true) return true;
    if (item.isOwner == false) return false;
    if (_myUserId != null &&
        item.assigneeId != null &&
        item.assigneeId! > 0 &&
        item.assigneeId == _myUserId) {
      return true;
    }
    if (item.assigneeName != null &&
        item.assigneeName!.trim().isNotEmpty &&
        _assigneeNameMatchesMe(item.assigneeName, _meNameForChores)) {
      return true;
    }
    return false;
  }

  /// 완료 체크박스 — 일간 API `isOwner: true`인 CHORE만 (양수 choreId)
  bool _canShowChoreCompletionCheckbox(_CalendarEvent event) {
    if (event.id == null || event.id! <= 0) return false;
    if (event.dailyApiIsOwner == true) return true;
    if (event.dailyApiIsOwner == false) return false;
    return event.isOwner == true;
  }

  /// 서버 자동 일정·공과금·월세 등이 `SCHEDULE` + 특정 담당자명으로 오는 경우
  bool _isSystemGeneratedAssignee(String? assignee) {
    final a = assignee?.trim().toLowerCase();
    if (a == null || a.isEmpty) return false;
    return a == '시스템' ||
        a == 'system' ||
        a == 'system_generated' ||
        a == 'auto' ||
        a == '서버';
  }

  /// DailyCalendarItem을 _CalendarEvent로 변환
  List<_CalendarEvent> _convertDailyItemsToEvents(List<DailyCalendarItem> items) {
    return items.map((item) {
      CalendarEventType eventType;
      String description;
      final cat = _normalizeDailyCategory(item.category);
      final systemSchedule =
          cat == 'SCHEDULE' && _isSystemGeneratedAssignee(item.assigneeName);

      if (cat == 'CHORE') {
        eventType = CalendarEventType.chore;
        // 작성자 이름을 앞에 표시
        if (item.assigneeName != null && item.assigneeName!.isNotEmpty) {
          description = '${item.assigneeName} · ${item.title}';
        } else {
          description = item.title;
        }
      } else if (cat == 'SCHEDULE' && !systemSchedule) {
        eventType = CalendarEventType.memo;
        // 작성자 이름을 앞에 표시
        if (item.assigneeName != null && item.assigneeName!.isNotEmpty) {
          description = '${item.assigneeName} · ${item.title}';
        } else {
          description = item.title;
        }
        if (item.isCompleted) {
          description += ' ✓';
        }
      } else {
        // UTILITY/BILL 카테고리 또는 서버 자동 일정(시스템 담당) → 공과금 UI
        eventType = CalendarEventType.bill;
        // 작성자 이름을 앞에 표시
        if (item.assigneeName != null && item.assigneeName!.isNotEmpty) {
          description = '${item.assigneeName} · ${item.title}';
        } else {
          description = item.title;
        }
      }

      final bool? dailyApiIsOwner = cat == 'CHORE' ? item.isOwner : null;
      final bool? isOwnerForEvent =
          cat == 'CHORE' ? _choreOwnedByMe(item) : item.isOwner;

      return _CalendarEvent(
        eventType,
        description,
        id: item.id,
        category: item.category,
        assigneeName: item.assigneeName,
        assigneeId: item.assigneeId,
        choreType: item.choreType,
        choreTitle: cat == 'CHORE' ? item.title : null,
        dailyApiIsOwner: dailyApiIsOwner,
        isOwner: isOwnerForEvent,
        isCompleted: item.isCompleted,
      );
    }).toList();
  }

  /// 주간·일정 세부 화면이 열려 있으면 월간 그리드로 접기 (홈에서 캘린더 바깥 탭 등)
  void collapseWeekDetailIfShowing() {
    if (!_showDetail) return;
    if (!mounted) return;
    setState(() {
      _showDetail = false;
    });
  }

  /// 캘린더 데이터 강제 갱신 (외부에서 호출 가능)
  void refreshCalendar() {
    // 캐시 무효화
    _cachedMonthKey = null;
    _cachedEvents = null;
    _cachedDailyEvents = null; // 모든 일간 캐시 무효화
    
    // 데이터 재로드 (강제 갱신)
    _loadCalendarData(_currentMonth.year, _currentMonth.month, forceRefresh: true);
    if (_detailDate != null) {
      _loadDailyCalendarData(_detailDate!, forceRefresh: true);
    }
  }

  /// UI 확인용: 해당 연도 4월 월간 그리드에 집안일·공과금·일정 점이 다양하게 보이도록
  Map<String, List<_CalendarEvent>> _buildAprilPreviewEvents(int year) {
    const billTexts = [
      '전기요금 납부',
      '가스요금 납부',
      '인터넷 요금 납부',
      '수도요금 납부',
    ];
    const scheduleTexts = [
      '일정이 있습니다',
      '중요한 일정',
      '약속',
    ];

    List<_CalendarEvent> buildDay(
      String dateKey,
      int choreCount,
      int utilityBillsCount,
      int scheduleCount,
    ) {
      final dayEvents = <_CalendarEvent>[];
      for (int i = 0; i < choreCount; i++) {
        final index = (dateKey.hashCode + i) % _kChoreTaskNames.length;
        final taskName = _kChoreTaskNames[index];
        final assignee = (i % 4 == 0)
            ? _meNameForChores
            : _kOtherMemberNames[(i + dateKey.hashCode) % _kOtherMemberNames.length];
        final isMine = assignee == _meNameForChores;
        final id = _syntheticChoreId(dateKey, i);
        dayEvents.add(_CalendarEvent(
          CalendarEventType.chore,
          '$assignee · $taskName',
          id: id,
          category: 'CHORE',
          assigneeName: assignee,
          dailyApiIsOwner: isMine,
          isOwner: isMine,
          isCompleted: false,
        ));
      }
      for (int i = 0; i < utilityBillsCount; i++) {
        final index = (dateKey.hashCode + i) % billTexts.length;
        dayEvents.add(_CalendarEvent(
          CalendarEventType.bill,
          billTexts[index],
          isOwner: null,
        ));
      }
      for (int i = 0; i < scheduleCount; i++) {
        final index = (dateKey.hashCode + i) % scheduleTexts.length;
        dayEvents.add(_CalendarEvent(
          CalendarEventType.memo,
          scheduleTexts[index],
          isOwner: null,
        ));
      }
      return dayEvents;
    }

    final out = <String, List<_CalendarEvent>>{};
    void put(String day, int c, int u, int s) {
      final dateKey = '$year-04-${day.padLeft(2, '0')}';
      final list = buildDay(dateKey, c, u, s);
      if (list.isNotEmpty) {
        out[dateKey] = list;
      }
    }

    // (집안일, 공과금, 일정) 개수 — 한 달에 걸쳐 패턴 다양하게
    put('01', 1, 1, 1);
    put('03', 2, 0, 1);
    put('05', 1, 2, 0);
    put('07', 0, 1, 2);
    put('09', 3, 1, 0);
    put('11', 1, 0, 2);
    put('13', 2, 1, 1);
    put('15', 1, 1, 0);
    put('17', 0, 2, 1);
    put('19', 2, 0, 2);
    put('21', 1, 1, 1);
    put('23', 4, 0, 0);
    put('25', 0, 1, 3);
    put('27', 1, 2, 0);
    put('29', 2, 1, 1);
    put('30', 1, 0, 1);
    return out;
  }

  Future<String> _resolveMeName() async {
    if (!mounted) return _meNameForChores;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false).user?.name;
      if (auth != null && auth.isNotEmpty) return auth;
    } catch (_) {}
    final n = await StorageService.getUserName();
    if (n != null && n.isNotEmpty) return n;
    return '나';
  }

  /// 월간 집계용 더미 집안일 id(음수). 서버 id와 겹치지 않도록 날짜·인덱스로만 생성.
  int _syntheticChoreId(String dateKey, int indexInDay) {
    return -(dateKey.hashCode * 1009 + indexInDay * 17 + 1).abs();
  }

  Map<String, List<_CalendarEvent>> _applyPreviewChoreCompletion(
    Map<String, List<_CalendarEvent>> input,
  ) {
    if (_previewChoreCompleted.isEmpty) return input;
    final out = <String, List<_CalendarEvent>>{};
    for (final entry in input.entries) {
      out[entry.key] = entry.value.map((ev) {
        final id = ev.id;
        if (id == null || id >= 0) return ev;
        if (!_previewChoreCompleted.containsKey(id)) return ev;
        final c = _previewChoreCompleted[id]!;
        return _CalendarEvent(
          ev.type,
          ev.description,
          id: ev.id,
          category: ev.category,
          assigneeName: ev.assigneeName,
          assigneeId: ev.assigneeId,
          choreType: ev.choreType,
          choreTitle: ev.choreTitle,
          dailyApiIsOwner: ev.dailyApiIsOwner,
          isOwner: ev.isOwner,
          isCompleted: c,
        );
      }).toList();
    }
    return out;
  }

  Future<void> _loadCalendarData(int year, int month, {bool forceRefresh = false}) async {
    final monthKey = '$year-${month.toString().padLeft(2, '0')}';
    final useDummy = _partitionDummyActive == true ||
        usePartitionDummyData(
          Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
        );
    
    // 강제 갱신이 아니고 이미 같은 월의 데이터가 캐시되어 있으면 다시 로드하지 않음
    if (!forceRefresh && _cachedMonthKey == monthKey && _cachedEvents != null) {
      return;
    }

    if (!mounted) return;
    if (useDummy) {
      setState(() {
        _isLoading = false;
        _cachedEvents = {};
        _cachedMonthKey = monthKey;
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _calendarService.getMonthlyCalendar(
        year: year,
        month: month,
      );

      if (response.isSuccess && response.result != null) {
        final meName = await _resolveMeName();
        if (!mounted) return;
        final Map<String, List<_CalendarEvent>> events = {};

        // 공과금 텍스트 목록
        final billTexts = [
          '전기요금 납부',
          '가스요금 납부',
          '인터넷 요금 납부',
          '수도요금 납부',
        ];
        
        // 일정 텍스트 목록
        final scheduleTexts = [
          '일정이 있습니다',
          '중요한 일정',
          '약속',
        ];

        for (final item in response.result!) {
          final date = item.date;
          final choreCount = item.choreCount;
          final scheduleCount = item.scheduleCount;
          final utilityBillsCount = item.utilityBillsCount;
          
          final List<_CalendarEvent> dayEvents = [];
          
          // 집안일 추가 (월간은 건수만 오므로 담당·더미 id 부여 — 내 담당만 체크 가능)
          for (int i = 0; i < choreCount; i++) {
            final index = (date.hashCode + i) % _kChoreTaskNames.length;
            final taskName = _kChoreTaskNames[index];
            final assignee = (i % 4 == 0)
                ? meName
                : _kOtherMemberNames[(i + date.hashCode) % _kOtherMemberNames.length];
            final isMine = assignee == meName;
            final id = _syntheticChoreId(date, i);
            dayEvents.add(_CalendarEvent(
              CalendarEventType.chore,
              '$assignee · $taskName',
              id: id,
              category: 'CHORE',
              assigneeName: assignee,
              dailyApiIsOwner: isMine,
              isOwner: isMine,
              isCompleted: false,
            ));
          }
          
          // 공과금 추가
          for (int i = 0; i < utilityBillsCount; i++) {
            final index = (date.hashCode + i) % billTexts.length;
            dayEvents.add(_CalendarEvent(
              CalendarEventType.bill,
              billTexts[index],
              isOwner: null,
            ));
          }
          
          // 일정 추가
          for (int i = 0; i < scheduleCount; i++) {
            final index = (date.hashCode + i) % scheduleTexts.length;
            dayEvents.add(_CalendarEvent(
              CalendarEventType.memo,
              scheduleTexts[index],
              isOwner: null,
            ));
          }
          
          if (dayEvents.isNotEmpty) {
            events[date] = dayEvents;
          }
        }

        if (mounted) {
          setState(() {
            _meNameForChores = meName;
            _cachedEvents = events;
            _cachedMonthKey = monthKey;
          });
        }
      } else {
        // 응답 실패·result 없음: 해당 월 캐시만 비우고 monthKey 맞춤 (4월은 getter에서 더미 합침)
        if (mounted) {
          setState(() {
            _cachedEvents = {};
            _cachedMonthKey = monthKey;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('캘린더 데이터 로드 실패: $e');
        setState(() {
          _cachedEvents = {};
          _cachedMonthKey = monthKey;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 일간 캘린더 상세 조회
  Future<void> _loadDailyCalendarData(DateTime date, {bool forceRefresh = false}) async {
    final dateKey = _dateKey(date);
    final useDummy = _partitionDummyActive == true ||
        usePartitionDummyData(
          Provider.of<AuthProvider>(context, listen: false).isAuthenticated,
        );
    
    // 강제 갱신이 아니고 이미 같은 날짜의 데이터가 캐시되어 있으면 다시 로드하지 않음
    if (!forceRefresh && _cachedDailyDateKey == dateKey && _cachedDailyEvents != null && _cachedDailyEvents![dateKey] != null) {
      if (mounted) {
        setState(() => _isLoadingDaily = false);
      }
      return;
    }

    if (!mounted) return;
    if (useDummy) {
      setState(() {
        _isLoadingDaily = false;
        _cachedDailyEvents ??= {};
        _cachedDailyEvents!.remove(dateKey);
        _cachedDailyDateKey = dateKey;
      });
      return;
    }
    setState(() {
      _isLoadingDaily = true;
    });

    try {
      await _refreshMeIdentity();
      if (!mounted) return;

      final response = await _calendarService.getDailyCalendar(
        date: dateKey,
      );

      if (response.isSuccess && response.result != null) {
        if (mounted) {
          setState(() {
            _cachedDailyEvents ??= {};
            _cachedDailyEvents![dateKey] = response.result!;
            _cachedDailyDateKey = dateKey;
          });
          await _enrichChoresWithDailyApi(dateKey);
        }
      } else {
        // 실패 시 빈 배열을 넣지 않음 — 디버그·미로그인일 때만 월간 합성으로 폴백
        if (mounted) {
          setState(() {
            _cachedDailyEvents ??= {};
            _cachedDailyEvents!.remove(dateKey);
            _cachedDailyDateKey = dateKey;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cachedDailyEvents ??= {};
          _cachedDailyEvents!.remove(dateKey);
          _cachedDailyDateKey = dateKey;
        });
      }
      if (mounted) {
        debugPrint('일간 캘린더 데이터 로드 실패: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDaily = false;
        });
      }
    }
  }
  
  final List<String> _monthNames = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
           date.month == now.month &&
           date.day == now.day;
  }

  List<DateTime> _getWeekDays(DateTime centerDate) {
    // 선택한 날짜가 속한 주의 시작일 (일요일) 찾기
    final weekday = centerDate.weekday % 7; // 0 = 일요일
    final startOfWeek = centerDate.subtract(Duration(days: weekday));
    
    // 일주일 (7일) 생성
    return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
  }

  Widget _buildWeekView({
    required int startMonth,
    required int currentMonthIndex,
    required DateTime centerDate,
    /// 바깥 LayoutBuilder(홈의 SizedBox 등)에서 오는 유한 높이. 내부 LayoutBuilder만 쓰면
    /// FrostedPanel/AnimatedSwitcher 경로에서 maxHeight가 무한이 되어 Expanded+ListView가 깨짐.
    required double parentMaxHeight,
  }) {
    final weekDays = _getWeekDays(centerDate);
    final h = parentMaxHeight.isFinite && parentMaxHeight > 0
        ? parentMaxHeight
        : 380.0;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Column(
        key: const ValueKey('week-view'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMonthSelector(startMonth, currentMonthIndex),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((day) => SizedBox(
                      width: 40,
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: 7,
              itemBuilder: (context, index) {
                final date = weekDays[index];
                final isToday = _isToday(date);
                final isSelected = _detailDate != null &&
                    _detailDate!.year == date.year &&
                    _detailDate!.month == date.month &&
                    _detailDate!.day == date.day;
                final events = _events[_dateKey(date)] ?? [];
                final showBill = events.any((e) => e.type == CalendarEventType.bill);
                final showChore = events.any((e) => e.type == CalendarEventType.chore);
                final showMemo = events.any((e) => e.type == CalendarEventType.memo);

                return GestureDetector(
                  onTap: () => _handleDateTap(date),
                  child: CustomPaint(
                    painter: _DateHighlightPainter(
                      showOrbit: false,
                      showSelection: isSelected,
                      color: Colors.white,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (showBill || showChore || showMemo)
                          Positioned(
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showBill)
                                  Container(
                                    width: 4.211,
                                    height: 4.211,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFF4E2),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (showBill && (showChore || showMemo))
                                  const SizedBox(width: 2),
                                if (showChore)
                                  Container(
                                    width: 4.211,
                                    height: 4.211,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDBD1C2),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (showChore && showMemo)
                                  const SizedBox(width: 2),
                                if (showMemo)
                                  Container(
                                    width: 4.211,
                                    height: 4.211,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF7C7C7C),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
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
          if (_detailDate != null) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoadingDaily)
                    const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  Expanded(
                    child: _buildEventList(_detailDate!),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthSelector(int startMonth, int currentMonthIndex) {
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(4, (index) {
              final monthIndex = startMonth + index;
              if (monthIndex >= 12) return const SizedBox.shrink();
              final isSelected = monthIndex == currentMonthIndex;
              return GestureDetector(
                onTap: () => _selectMonth(monthIndex),
                child: Column(
                  children: [
                    Text(
                      _monthNames[monthIndex],
                      style: TextStyle(
                        color: isSelected
                            ? HomeShareStyle.point
                            : Colors.white,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (isSelected)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        height: 2,
                        width: 30,
                        color: HomeShareStyle.point,
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left,
                  color: Colors.white, size: 20),
              onPressed: _previousMonth,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_right,
                  color: Colors.white, size: 20),
              onPressed: _nextMonth,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }

  bool _isSelected(DateTime date) {
    return date.year == _selectedDate.year &&
           date.month == _selectedDate.month &&
           date.day == _selectedDate.day;
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    
    // 첫 번째 날의 요일 (0 = 일요일, 6 = 토요일)
    final firstWeekday = firstDay.weekday % 7;
    
    List<DateTime> days = [];
    
    // 이전 달의 마지막 날들 추가
    final prevMonthLastDay = DateTime(_currentMonth.year, _currentMonth.month, 0);
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month - 1, prevMonthLastDay.day - i));
    }
    
    // 현재 달의 날들 추가
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, i));
    }
    
    // 다음 달의 첫 날들 추가 (캘린더를 6주로 채우기 위해)
    final remainingDays = 42 - days.length; // 6주 * 7일 = 42일
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month + 1, i));
    }
    
    return days;
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _formatDateLabel(DateTime date) {
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return '${weekdays[date.weekday % 7]} · ${date.month}/${date.day}';
  }

  /// 현재 사용자 이름 가져오기 (여러 소스 확인)
  Future<String?> _getCurrentUserName(BuildContext context, String? providerUserName) async {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('🔍 사용자 이름 조회 시작');
    debugPrint('  - Provider 사용자 이름: $providerUserName');
    
    // 1. Provider에서 사용자 정보 확인 (이미 전달받음)
    if (providerUserName != null && providerUserName.isNotEmpty) {
      await StorageService.setUserName(providerUserName);
      return providerUserName;
    }
    
    // 2. 로컬 스토리지에서 먼저 확인 (서버 에러가 발생할 수 있으므로)
    final localUserName = await StorageService.getUserName();
    if (localUserName != null && localUserName.isNotEmpty) {
      return localUserName;
    }
    
    // 3. 세션 사용자(로컬만, GET /users/me 미사용)
    final authService = AuthService();
    final userInfo = await authService.getUserInfo();
    if (userInfo?.name != null && userInfo!.name!.isNotEmpty) {
      await StorageService.setUserName(userInfo.name!);
      return userInfo.name;
    }
    
    return null;
  }

  /// 이벤트 목록 위젯 생성
  Widget _buildEventList(DateTime date) {
    final dateKey = _dateKey(date);
    final dailyItems = _getDailyEvents(dateKey);
    final monthlyFallback = _events[dateKey] ?? [];
    final allowSyntheticFallback = _partitionDummyActive == true;

    final List<_CalendarEvent> events;
    if (allowSyntheticFallback) {
      // 디버그·미로그인: 일간 없을 때 월간 건수 기반 합성 일정으로 폴백
      if (dailyItems == null) {
        events = monthlyFallback;
      } else if (dailyItems.isEmpty && monthlyFallback.isNotEmpty) {
        events = monthlyFallback;
      } else {
        events = _convertDailyItemsToEvents(dailyItems);
      }
    } else {
      // 로그인(또는 릴리스): 일간 API 결과만 표시 — 합성 일정과 섞지 않음
      if (dailyItems == null) {
        if (_isLoadingDaily) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '일정을 불러오는 중…',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }
        return const Center(
          child: Text(
            '이 날의 일정을 불러오지 못했어요.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        );
      }
      events = _convertDailyItemsToEvents(dailyItems);
    }

    if (events.isEmpty) {
      return const Center(
        child: Text(
          '일정이 없습니다',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: false,
      padding: const EdgeInsets.only(top: 0),
      children: events.map(
        (event) {
          // SCHEDULE 카테고리이고 isOwner가 true인 경우에만 수정/삭제 가능
          final cat = _normalizeDailyCategory(event.category);
          final isSchedule = cat == 'SCHEDULE';
          final canEdit = isSchedule && (event.isOwner == true);
          // 집안일: 완료 체크는 본인 담당만, 수정·삭제는 그룹 집안일 전체
          final isChoreItem =
              event.type == CalendarEventType.chore && cat == 'CHORE' && event.id != null;
          final canToggleChore =
              isChoreItem && _canShowChoreCompletionCheckbox(event);
          final canManageChore =
              isChoreItem && event.id != null && event.id! > 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EventChip(
              event: event,
              onDelete: event.id != null && canEdit
                  ? () => _handleDeleteSchedule(event.id!, date)
                  : canManageChore
                      ? () => _handleDeleteChore(event.id!, date)
                      : null,
              onEdit: event.id != null && canEdit
                  ? () => _handleEditSchedule(event.id!, event.description, date)
                  : canManageChore
                      ? () => _handleEditChore(event, date)
                      : null,
              onChoreCompleted: canToggleChore
                  ? (completed) =>
                      _handleToggleChoreCompletion(event.id!, completed, date)
                  : null,
              choreCheckboxBusy: canToggleChore &&
                  _choreToggleInProgress.contains(event.id!),
            ),
          );
        },
      ).toList(),
    );
  }

  Future<void> _showFutureChoreBlockedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => PartitionGlassDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        borderRadius: BorderRadius.circular(24),
        blurSigma: 18,
        borderColor: Colors.white.withOpacity(0.22),
        gradient: const LinearGradient(
          colors: [Colors.transparent, Colors.transparent],
        ),
        boxShadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '완료 표시 불가',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '아직 오지 않은 날의 집안일은\n완료 표시를 할 수 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.normal,
                fontFamily: 'Pretendard Variable',
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                height: 45,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    PartitionUiTokens.actionButtonRadius,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 0.5,
                  ),
                  color: Colors.white.withOpacity(0.15),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '확인',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: PartitionUiTokens.actionFontSize,
                    fontWeight: PartitionUiTokens.actionWeight,
                    fontFamily: 'Pretendard Variable',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleToggleChoreCompletion(
    int choreId,
    bool completed,
    DateTime date,
  ) async {
    // 월간 집계/4월 미리보기용 음수 id — 서버 호출 없이 로컬만 반영
    if (choreId < 0) {
      if (!mounted) return;
      setState(() {
        _previewChoreCompleted[choreId] = completed;
      });
      return;
    }
    // 미래 날짜에 완료 표시 시도 시 차단
    if (completed) {
      final today = DateTime.now();
      final todayMidnight = DateTime(today.year, today.month, today.day);
      final dateMidnight = DateTime(date.year, date.month, date.day);
      if (dateMidnight.isAfter(todayMidnight)) {
        await _showFutureChoreBlockedDialog();
        return;
      }
    }
    if (_choreToggleInProgress.contains(choreId)) return;
    setState(() => _choreToggleInProgress.add(choreId));
    try {
      final response = await _choreService.updateChoreCompletion(
        choreId: choreId,
        isCompleted: completed,
      );
      if (!mounted) return;
      if (!response.isSuccess) {
        throw Exception(
          response.message.isNotEmpty
              ? response.message
              : '집안일 완료 처리에 실패했어요.',
        );
      }
      await _loadDailyCalendarData(date, forceRefresh: true);
      if (!mounted) return;
      await _loadCalendarData(
        _currentMonth.year,
        _currentMonth.month,
        forceRefresh: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : (e is Exception ? e.toString() : '집안일 완료 처리에 실패했어요.'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _choreToggleInProgress.remove(choreId));
      }
    }
  }

  /// `/chores/daily`로 담당자·유형 메타 보강 (일간 캘린더에 없을 때)
  Future<void> _enrichChoresWithDailyApi(String dateKey) async {
    try {
      final response = await _choreService.fetchDailyChores(date: dateKey);
      if (!response.isSuccess || response.result == null) return;

      final items = _cachedDailyEvents?[dateKey];
      if (items == null || items.isEmpty) return;

      final byChoreId = {
        for (final c in response.result!) c.choreId: c,
      };

      var changed = false;
      final merged = items.map((item) {
        if (_normalizeDailyCategory(item.category) != 'CHORE') return item;
        final detail = byChoreId[item.id];
        if (detail == null) return item;
        changed = true;
        final assigneeId = detail.assigneeId ?? item.assigneeId;
        final assigneeName = detail.assigneeName ?? item.assigneeName;
        final merged = DailyCalendarItem(
          category: item.category,
          id: item.id,
          title: detail.choreName.isNotEmpty ? detail.choreName : item.title,
          assigneeName: assigneeName,
          assigneeId: assigneeId,
          choreType: detail.choreType,
          isCompleted: detail.isCompleted,
          isOwner: item.isOwner == true
              ? true
              : (item.isOwner == false
                  ? false
                  : _choreOwnedByMe(
                      DailyCalendarItem(
                        category: item.category,
                        id: item.id,
                        title: item.title,
                        assigneeName: assigneeName,
                        assigneeId: assigneeId,
                        choreType: detail.choreType,
                        isCompleted: detail.isCompleted,
                        isOwner: null,
                      ),
                    )),
        );
        return merged;
      }).toList();

      if (!changed || !mounted) return;
      setState(() {
        _cachedDailyEvents![dateKey] = merged;
      });
    } catch (_) {
      // 전용 API 미구현 시 일간 캘린더 데이터만 사용
    }
  }

  String _choreTitleFromEvent(_CalendarEvent event) {
    if (event.choreTitle != null && event.choreTitle!.trim().isNotEmpty) {
      return event.choreTitle!.trim();
    }
    final desc = event.description;
    if (desc.contains(' · ')) {
      return desc.split(' · ').skip(1).join(' · ').trim();
    }
    return desc;
  }

  Future<int?> _resolveChoreAssigneeId(_CalendarEvent event) async {
    if (event.assigneeId != null && event.assigneeId! > 0) {
      return event.assigneeId;
    }
    final members = await _authService.fetchHouseholdMembers();
    final name = event.assigneeName?.trim();
    if (name != null && name.isNotEmpty) {
      for (final m in members) {
        if (m.name == name) return m.userId;
      }
    }
    final descName = event.description.split(' · ').first.trim();
    for (final m in members) {
      if (m.name == descName) return m.userId;
    }
    return null;
  }

  Future<void> _handleDeleteChore(int choreId, DateTime date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 0.5),
            gradient: const RadialGradient(
              center: Alignment(-0.1212, -0.1178),
              radius: 1.6319,
              colors: [
                Color.fromRGBO(255, 255, 255, 0.10),
                Color.fromRGBO(255, 255, 255, 0.15),
              ],
              stops: [0.0, 1.0],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '집안일 삭제',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '정말 이 집안일을 삭제하시겠습니까?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGlassmorphismButton(
                        text: '취소',
                        onTap: () => Navigator.of(context).pop(false),
                        width: 100,
                      ),
                      const SizedBox(width: 12),
                      _buildGlassmorphismButton(
                        text: '삭제',
                        onTap: () => Navigator.of(context).pop(true),
                        width: 100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _choreService.deleteChore(choreId: choreId);
      if (!mounted) return;
      if (!response.isSuccess) {
        throw Exception(response.message);
      }

      final dateKey = _dateKey(date);
      _cachedDailyEvents?.remove(dateKey);
      await _loadDailyCalendarData(date, forceRefresh: true);
      refreshCalendar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message.isNotEmpty
                ? response.message
                : '집안일이 삭제되었어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : '집안일 삭제에 실패했어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleEditChore(_CalendarEvent event, DateTime date) async {
    if (event.id == null || event.id! <= 0) return;
    if (event.isCompleted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 완료된 집안일은 수정할 수 없어요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final assigneeId = await _resolveChoreAssigneeId(event);
    if (assigneeId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('담당자 정보를 확인할 수 없어요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final members = await _authService.fetchHouseholdMembers();
    if (!mounted) return;

    final today = choreDateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 14));

    final result = await showChoreEditDialog(
      context: context,
      choreTitle: _choreTitleFromEvent(event),
      members: members,
      initialAssigneeId: assigneeId,
      initialDate: date,
      firstDate: today,
      lastDate: lastDate,
    );

    if (result == null) return;

    final newAssigneeId = result['assigneeId'] as int;
    final newDate = choreDateOnly(result['date'] as DateTime);
    final oldDateKey = _dateKey(date);
    final newDateKey = formatChoreDateForApi(newDate);
    final oldAssigneeId = assigneeId;

    final body = <String, dynamic>{};
    if (newAssigneeId != oldAssigneeId) {
      body['assigneeId'] = newAssigneeId;
    }
    if (newDateKey != oldDateKey) {
      body['date'] = newDateKey;
    }
    if (body.isEmpty) return;

    try {
      final response = await _choreService.updateChoreAssignment(
        choreId: event.id!,
        assigneeId: body['assigneeId'] as int?,
        date: body['date'] as String?,
      );

      if (!mounted) return;
      if (!response.isSuccess) {
        throw Exception(response.message);
      }

      _cachedDailyEvents?.remove(oldDateKey);
      if (oldDateKey != newDateKey) {
        _cachedDailyEvents?.remove(newDateKey);
      }
      await _loadDailyCalendarData(date, forceRefresh: true);
      if (oldDateKey != newDateKey) {
        await _loadDailyCalendarData(newDate, forceRefresh: true);
      }
      refreshCalendar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message.isNotEmpty
                ? response.message
                : '집안일이 수정되었어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : '집안일 수정에 실패했어요.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleDeleteSchedule(int scheduleId, DateTime date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '일정 삭제',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '정말 이 일정을 삭제하시겠습니까?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGlassmorphismButton(
                        text: '취소',
                        onTap: () => Navigator.of(context).pop(false),
                        width: 100,
                      ),
                      const SizedBox(width: 12),
                      _buildGlassmorphismButton(
                        text: '삭제',
                        onTap: () => Navigator.of(context).pop(true),
                        width: 100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // DELETE /api/schedules/{scheduleId} 호출
      final response = await _calendarService.deleteSchedule(scheduleId: scheduleId);
      
      if (!mounted) return;

      // API 응답 확인 (isSuccess 체크)
      if (!response.isSuccess) {
        throw Exception(response.message);
      }

      // 캐시 무효화 및 재로드
      final dateKey = _dateKey(date);
      _cachedDailyEvents?.remove(dateKey);
      await _loadDailyCalendarData(date, forceRefresh: true);

      // 월간 캘린더도 갱신
      refreshCalendar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message.isNotEmpty ? response.message : '일정이 삭제되었습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('일정 삭제에 실패했습니다: ${e is ApiException ? e.message : e.toString()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleEditSchedule(
    int scheduleId,
    String currentContent,
    DateTime date,
  ) async {
    var titleOnly = currentContent;
    if (currentContent.contains(' · ')) {
      final parts = currentContent.split(' · ');
      if (parts.length > 1) {
        titleOnly = parts.sublist(1).join(' · ');
      }
    }
    titleOnly = titleOnly.replaceAll(' ✓', '').trim();

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => ScheduleEditModal(
        scheduleId: scheduleId,
        initialContent: titleOnly,
        initialDate: date,
        onSuccess: (originalDate, updatedDate) async {
          final originalKey = _dateKey(originalDate);
          final updatedKey = _dateKey(updatedDate);
          _cachedDailyEvents?.remove(originalKey);
          if (originalKey != updatedKey) {
            _cachedDailyEvents?.remove(updatedKey);
          }
          await _loadDailyCalendarData(originalDate, forceRefresh: true);
          if (originalKey != updatedKey) {
            await _loadDailyCalendarData(updatedDate, forceRefresh: true);
          }
          refreshCalendar();
        },
      ),
    );
  }

  Widget _buildGlassmorphismButton({
    required String text,
    required VoidCallback onTap,
    double width = 100,
    double height = PartitionUiTokens.actionButtonHeight,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(PartitionUiTokens.actionButtonRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                PartitionUiTokens.actionButtonRadius,
              ),
              border: Border.all(
                color: PartitionUiTokens.actionButtonBorder,
                width: 0.5,
              ),
              color: PartitionUiTokens.actionButtonFill,
            ),
            child: Center(
              child: Text(
                text,
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
      ),
    );
  }

  void _previousMonth() {
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      });
      _loadCalendarData(_currentMonth.year, _currentMonth.month);
    }
  }

  void _nextMonth() {
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      });
      _loadCalendarData(_currentMonth.year, _currentMonth.month);
    }
  }

  void _selectMonth(int monthIndex) {
    if (!mounted) return;
    if (mounted) {
      setState(() {
      final newMonth = monthIndex + 1;
      _currentMonth = DateTime(_currentMonth.year, newMonth);
      
      // 주간 달력을 보고 있는 경우, 같은 날짜로 해당 월의 주간 달력으로 이동
      if (_showDetail && _detailDate != null) {
        final currentDay = _detailDate!.day;
        final lastDayOfNewMonth = DateTime(_currentMonth.year, newMonth + 1, 0).day;
        // 새 월의 마지막 날보다 큰 날짜를 선택한 경우, 마지막 날로 조정
        final targetDay = currentDay > lastDayOfNewMonth ? lastDayOfNewMonth : currentDay;
        _detailDate = DateTime(_currentMonth.year, newMonth, targetDay);
        _selectedDate = _detailDate!;
        // 주간 달력 모드 유지
        _showDetail = true;
      }
      });
      _loadCalendarData(_currentMonth.year, _currentMonth.month);
    }
  }

  void _handleDateTap(DateTime date) {
    if (!mounted) return;
    if (mounted) {
      setState(() {
      final bool sameDetail =
          _detailDate != null && _detailDate!.year == date.year && _detailDate!.month == date.month && _detailDate!.day == date.day;

      // 같은 날짜를 다시 탭하면 월 뷰로 접기 (바깥 탭과 동일한 결과)
      if (_showDetail && sameDetail) {
        _showDetail = false;
      } else {
        // 한 번 탭으로 바로 주간·세부 화면
        _selectedDate = date;
        _detailDate = date;
        _showDetail = true;
      }

      if (date.month != _currentMonth.month) {
        _currentMonth = DateTime(date.year, date.month);
      }
      });
      
      // 일간 상세 조회 호출
      _loadDailyCalendarData(date);
      
      // 선택된 날짜를 외부에 알림
      widget.onDateSelected?.call(date);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshMeIdentity();
      if (!mounted) return;
      _loadCalendarData(_currentMonth.year, _currentMonth.month);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final useDummy = usePartitionDummyData(
      Provider.of<AuthProvider>(context).isAuthenticated,
    );
    if (_partitionDummyActive == useDummy) return;
    _partitionDummyActive = useDummy;
    if (!useDummy) {
      _previewChoreCompleted.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _loadCalendarData(_currentMonth.year, _currentMonth.month, forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final currentMonthIndex = _currentMonth.month - 1;

    int startMonth = (currentMonthIndex ~/ 4) * 4;
    if (startMonth + 4 > 12) {
      startMonth = 12 - 4;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final Widget child = _showDetail && _detailDate != null
            ? _buildWeekView(
                startMonth: startMonth,
                currentMonthIndex: currentMonthIndex,
                centerDate: _detailDate!,
                parentMaxHeight: constraints.maxHeight,
              )
            : _buildCalendarContent(
                days: days,
                startMonth: startMonth,
                currentMonthIndex: currentMonthIndex,
                maxHeight: hasBoundedHeight ? constraints.maxHeight : null,
              );

        return RepaintBoundary(
          child: FrostedPanel(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendarContent({
    required List<DateTime> days,
    required int startMonth,
    required int currentMonthIndex,
    double? maxHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HomeCalendarWidget._computeMonthGridLayout(
          constraints.maxWidth,
          maxHeight: maxHeight,
        );
        final gridHeight = layout.gridHeight;

        final gridView = GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: HomeCalendarWidget.gridColumns,
            mainAxisSpacing: HomeCalendarWidget.gridSpacing,
            crossAxisSpacing: HomeCalendarWidget.gridSpacing,
            childAspectRatio: 1.0,
          ),
          itemCount: HomeCalendarWidget.gridWeekRows *
              HomeCalendarWidget.gridColumns,
          itemBuilder: (context, index) {
            final date = days[index];
            final isCurrentMonth = date.month == _currentMonth.month;
            final isToday = _isToday(date);
            final isSelected = _isSelected(date);
            final events = _events[_dateKey(date)] ?? [];
            // 각 타입이 하나라도 있으면 해당 색의 점 1개만 표시
            final showBill = events.any((e) => e.type == CalendarEventType.bill);
            final showChore = events.any((e) => e.type == CalendarEventType.chore);
            final showMemo = events.any((e) => e.type == CalendarEventType.memo);
            
            return GestureDetector(
              onTap: () => _handleDateTap(date),
              child: CustomPaint(
                painter: _DateHighlightPainter(
                  showOrbit: false,
                  showSelection: isSelected,
                  color: Colors.white,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isCurrentMonth
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                          fontSize: 14,
                          fontWeight: isToday || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    // 이벤트 표시 (각 타입당 점 1개)
                    if (showBill || showChore || showMemo)
                      Positioned(
                        bottom: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showBill)
                              Container(
                                width: 4.211,
                                height: 4.211,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFF4E2),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (showBill && (showChore || showMemo))
                              const SizedBox(width: 2),
                            if (showChore)
                              Container(
                                width: 4.211,
                                height: 4.211,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDBD1C2),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (showChore && showMemo)
                              const SizedBox(width: 2),
                            if (showMemo)
                              Container(
                                width: 4.211,
                                height: 4.211,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF7C7C7C),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );

        return Column(
          key: const ValueKey('month-view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMonthSelector(startMonth, currentMonthIndex),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                  .map((day) => SizedBox(
                        width: 40,
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // 날짜 그리드
            SizedBox(
              height: gridHeight,
              child: gridView,
            ),
          ],
        );
      },
    );
  }
}

class _DateHighlightPainter extends CustomPainter {
  final bool showOrbit;
  final bool showSelection;
  final Color color;

  _DateHighlightPainter({
    required this.showOrbit,
    required this.showSelection,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    if (showSelection) {
      final Paint basePaint = Paint()
        ..color = color.withOpacity(0.15);
      canvas.drawCircle(center, radius * 0.8, basePaint);
    }

    if (!showOrbit) return;

    final Paint dotPaint = Paint();
    final double orbitRadius = radius * 0.9;
    final double gap = 6.0;
    final List<double> dotDiameters = [8, 6, 4.5];
    double currentAngle = 0;

    for (int i = 0; i < dotDiameters.length; i++) {
      final double dotRadius = dotDiameters[i] / 2;
      dotPaint.color = color.withOpacity(0.9 - i * 0.25);

      final offset = Offset(
        center.dx + (orbitRadius + dotRadius) * math.cos(currentAngle),
        center.dy + (orbitRadius + dotRadius) * math.sin(currentAngle),
      );
      canvas.drawCircle(offset, dotRadius, dotPaint);
      currentAngle += (dotDiameters[i] + gap) / orbitRadius;
    }
  }

  @override
  bool shouldRepaint(covariant _DateHighlightPainter oldDelegate) {
    return oldDelegate.showOrbit != showOrbit ||
        oldDelegate.showSelection != showSelection ||
        oldDelegate.color != color;
  }
}

class _EventChip extends StatelessWidget {
  final _CalendarEvent event;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onChoreCompleted;
  final bool choreCheckboxBusy;

  const _EventChip({
    required this.event,
    this.onDelete,
    this.onEdit,
    this.onChoreCompleted,
    this.choreCheckboxBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = _eventColor(event.type);
    final showChoreCheckbox = onChoreCompleted != null;
    final showChoreCompletedStrike =
        event.type == CalendarEventType.chore && (event.isCompleted ?? false);
    return ClipRRect(
      borderRadius: BorderRadius.circular(31.369),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(31.369)),
            border: Border.all(
              color: Colors.white.withOpacity(0.22),
              width: 0.5,
            ),
            gradient: RadialGradient(
              center: const Alignment(-0.1212, -0.1178),
              radius: 1.7145,
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.09),
              ],
              stops: const [0.0, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.10),
                offset: const Offset(1.5, 2),
                blurRadius: 10,
              ),
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 10.038, vertical: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.45),
                    width: 0.75,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withOpacity(0.65),
                      blurRadius: 5,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.description,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Pretendard Variable',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    decoration: showChoreCompletedStrike
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: Colors.white70,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                      FontFeature.liningFigures(),
                    ],
                  ),
                ),
              ),
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(width: 8),
                if (onEdit != null)
                  GestureDetector(
                    onTap: onEdit,
                    child: Icon(
                      Icons.edit,
                      size: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                if (onEdit != null && onDelete != null)
                  const SizedBox(width: 4),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.delete,
                      size: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
              ],
              if (showChoreCheckbox) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: event.isCompleted ?? false,
                    onChanged: choreCheckboxBusy
                        ? null
                        : (v) {
                            if (v != null) onChoreCompleted!(v);
                          },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.5),
                      width: 1.1,
                    ),
                    fillColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.selected)) {
                        return Colors.white.withOpacity(0.20);
                      }
                      return Colors.white.withOpacity(0.06);
                    }),
                    checkColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _eventColor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bill:
        return const Color(0xFFFFF4E2); // 공과금 알림
      case CalendarEventType.chore:
        return const Color(0xFFDBD1C2); // 집안일 담당
      case CalendarEventType.memo:
        return const Color(0xFF7C7C7C); // 메모
    }
  }
}

class _CalendarEvent {
  final CalendarEventType type;
  final String description;
  final int? id;
  final String? category;
  final String? assigneeName;
  final int? assigneeId;
  final String? choreType;
  final String? choreTitle;
  /// GET `/calendars/daily` 원본 `isOwner` (체크박스 판단용)
  final bool? dailyApiIsOwner;
  final bool? isOwner;
  final bool? isCompleted;

  const _CalendarEvent(
    this.type,
    this.description, {
    this.id,
    this.category,
    this.assigneeName,
    this.assigneeId,
    this.choreType,
    this.choreTitle,
    this.dailyApiIsOwner,
    this.isOwner,
    this.isCompleted,
  });
}

enum CalendarEventType { bill, chore, memo }

/// 글래스모피즘 효과가 적용된 날짜 선택 다이얼로그
class _GlassmorphicDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _GlassmorphicDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_GlassmorphicDatePicker> createState() => _GlassmorphicDatePickerState();
}

class _GlassmorphicDatePickerState extends State<_GlassmorphicDatePicker> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  void _previousMonth() {
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      });
    }
  }

  void _nextMonth() {
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      });
    }
  }

  bool _canGoPrevious() {
    // 제한 없음 - 항상 이전 월로 이동 가능
    return true;
  }

  bool _canGoNext() {
    // 제한 없음 - 항상 다음 월로 이동 가능
    return true;
  }

  bool _isDateSelectable(DateTime date) {
    // 제한 없음 - 모든 날짜 선택 가능
    return true;
  }

  bool _isDateSelected(DateTime date) {
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }

  void _selectDate(DateTime date) {
    if (_isDateSelectable(date)) {
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _selectedDate = DateTime(date.year, date.month, date.day);
        });
      }
    }
  }

  String _getMonthYearText() {
    final months = [
      '1월', '2월', '3월', '4월', '5월', '6월',
      '7월', '8월', '9월', '10월', '11월', '12월'
    ];
    return '${_currentMonth.year}년 ${months[_currentMonth.month - 1]}';
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7; // 0 = 일요일, 6 = 토요일

    final days = <DateTime>[];
    
    // 이전 달의 마지막 날들
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }

    // 현재 달의 날들
    for (int i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, i));
    }

    // 다음 달의 첫 날들 (35개 셀을 채우기 위해 - 5주)
    final remainingDays = 35 - days.length;
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month + 1, i));
    }

    return days;
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final weekdays = ['일', '월', '화', '수', '목', '금', '토'];

    return PartitionGlassDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      constraints: const BoxConstraints(
        maxWidth: 280,
        maxHeight: 360,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
                  // 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Opacity(
                        opacity: _canGoPrevious() ? 1 : 0.3,
                        child: GestureDetector(
                          onTap: _canGoPrevious() ? _previousMonth : null,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_left,
                              color: Colors.white.withOpacity(0.95),
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _getMonthYearText(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard Variable',
                        ),
                      ),
                      Opacity(
                        opacity: _canGoNext() ? 1 : 0.3,
                        child: GestureDetector(
                          onTap: _canGoNext() ? _nextMonth : null,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              color: Colors.white.withOpacity(0.95),
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 요일 헤더
                  Row(
                    children: weekdays.map((day) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Pretendard Variable',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // 날짜 그리드
                  SizedBox(
                    height: 160,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: 1.8,
                        mainAxisSpacing: 0.5,
                        crossAxisSpacing: 0.5,
                      ),
                      itemCount: 35,
                      itemBuilder: (context, index) {
                        final date = days[index];
                        final isCurrentMonth = date.month == _currentMonth.month;
                        final isSelectable = _isDateSelectable(date);
                        final isSelected = _isDateSelected(date);
                        final isToday = date.year == DateTime.now().year &&
                            date.month == DateTime.now().month &&
                            date.day == DateTime.now().day;

                        return GestureDetector(
                          onTap: () => _selectDate(date),
                          child: Container(
                            margin: const EdgeInsets.all(0.25),
                            child: isSelected
                                ? Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.white.withOpacity(0.15),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Pretendard Variable',
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: isToday
                                          ? Border.all(
                                              color: Colors.white.withOpacity(0.3),
                                              width: 0.8,
                                            )
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          color: isCurrentMonth && isSelectable
                                              ? Colors.white.withOpacity(0.95)
                                              : Colors.white.withOpacity(0.4),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          fontFamily: 'Pretendard Variable',
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Pretendard Variable',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(_selectedDate),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white.withOpacity(0.08),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '확인',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 11,
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
    );
  }
}