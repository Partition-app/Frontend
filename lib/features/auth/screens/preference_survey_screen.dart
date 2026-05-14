import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:partition_app/core/router/app_router.dart';
import 'package:partition_app/core/storage/storage_service.dart';
import 'package:partition_app/features/partition/theme/partition_ui_tokens.dart';
import 'package:partition_app/features/auth/widgets/auth_flow_widgets.dart';
import 'package:partition_app/shared/widgets/glassmorphism_button.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/features/auth/models/preference_response_model.dart';

class PreferenceSurveyScreen extends StatefulWidget {
  const PreferenceSurveyScreen({super.key});

  @override
  State<PreferenceSurveyScreen> createState() => _PreferenceSurveyScreenState();
}

class _PreferenceSurveyScreenState extends State<PreferenceSurveyScreen> {
  // 집안일 목록
  final List<String> _chores = [
    '설거지 하기',
    '요리 하기',
    '빨래 하기',
    '음식물 쓰레기 버리기',
    '재활용 쓰레기 버리기',
    '청소기 돌리기',
    '바닥 닦기',
    '창문, 창틀 닦기',
    '화장실 청소하기',
    '냉장고 청소하기',
  ];

  // 각 집안일의 선호도 (1-5점)
  final Map<String, int> _preferences = {};

  // 공용 물품 카테고리 및 물품 목록
  final Map<String, List<String>> _sharedItems = {
    '주방용품': ['가위', '칼', '도마', '수세미', '주방세제', '키친타올', '쓰레기봉투', '고무장갑'],
    '욕실용품': ['샴푸', '린스', '바디워시', '치약', '핸드워시'],
    '청소용품': ['청소포', '청소솔', '세탁세제', '섬유유연제', '유리세정제', '욕실 세제'],
    '위생용품': ['휴지', '물티슈', '방향제'],
    '식료품': ['쌀', '생수', '기름', '기본 조미료', '기본 양념', '계란', '우유', '식빵', '김치', '라면', '야채'],
    '기타': ['멀티탭', '각티슈', '방향제', '형광등', '건전지', '모기약', '전기파리채'],
  };

  // 선택된 공용 물품 (Set으로 관리)
  final Set<String> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    // 초기값 0 (선택 안 됨)
    for (var chore in _chores) {
      _preferences[chore] = 0;
    }
  }

  void _updatePreference(String chore, int score) {
    setState(() {
      _preferences[chore] = score;
    });
  }

  void _toggleItem(String item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
      } else {
        _selectedItems.add(item);
      }
    });
  }

  // 집안일 이름을 choreType으로 매핑
  String _getChoreType(String choreName) {
    final mapping = {
      '설거지 하기': 'DISH_WASHING',
      '요리 하기': 'COOKING',
      '빨래 하기': 'LAUNDRY',
      '음식물 쓰레기 버리기': 'FOODTRASH',
      '재활용 쓰레기 버리기': 'RECYCLING',
      '청소기 돌리기': 'VACUUM',
      '바닥 닦기': 'MOPPING',
      '창문, 창틀 닦기': 'WINDOW',
      '화장실 청소하기': 'BATHROOM',
      '냉장고 청소하기': 'FRIDGE',
    };
    return mapping[choreName] ?? '';
  }

  Future<void> _handleNext() async {
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

      // 선호도 데이터를 API 형식으로 변환 (점수가 1~5 범위인 것만)
      final preferences = <PreferenceItem>[];
      for (var entry in _preferences.entries) {
        // 점수가 1~5 범위인 경우만 포함
        if (entry.value >= 1 && entry.value <= 5) {
          final choreType = _getChoreType(entry.key);
          if (choreType.isNotEmpty) {
            preferences.add(PreferenceItem(
              choreType: choreType,
              score: entry.value,
            ));
          }
        }
      }

      // 최소 1개 이상의 선호도가 있어야 함
      if (preferences.isEmpty) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('최소 1개 이상의 집안일에 대한 선호도를 선택해주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // API 호출
      final authService = AuthService();
      final response = await authService.registerPreferences(
        preferences: preferences,
      );

      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      }

      if (response.isSuccess) {
        // 온보딩 완료 처리
        await StorageService.setOnboardingCompleted(true);

        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRouter.partitionMain);
        }
      } else {
        // 에러 처리
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '선호도 등록에 실패했습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        
        String errorMessage = '선호도 등록 중 오류가 발생했습니다.';
        
        // 에러 타입에 따라 메시지 구분
        if (e.toString().contains('500') || e.toString().contains('INTERNAL_SERVER_ERROR')) {
          errorMessage = '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
        } else if (e.toString().contains('403') || e.toString().contains('FORBIDDEN')) {
          errorMessage = '권한이 없습니다. 다시 로그인해주세요.';
        } else if (e.toString().contains('401') || e.toString().contains('UNAUTHORIZED')) {
          errorMessage = '인증이 필요합니다. 다시 로그인해주세요.';
        } else if (e.toString().contains('400') || e.toString().contains('BAD_REQUEST')) {
          errorMessage = '잘못된 요청입니다. 입력값을 확인해주세요.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
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
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      width: screenWidth * 0.9,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '나중에도 추가할 수 있어요.',
                    style: TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.72),
                      fontSize: 13,
                      fontFamily: 'Pretendard Variable',
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Q1 헤더
                  Text(
                    'Q1',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '각 집안일에 대한 선호도를 입력해주세요.',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 집안일 목록
                  ..._chores.map((chore) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildChoreRow(chore),
                      )),
                  const SizedBox(height: 32),
                  // Q2 헤더
                  Text(
                    'Q2',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '룸메이트와 공유하는 공동물품을 선택해주세요.',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 공용 물품 카테고리별 표시
                  ..._sharedItems.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildCategoryBox(entry.key, entry.value),
                      )),
                  const SizedBox(height: 24),
                  // 다음으로 버튼
                  SizedBox(
                    width: double.infinity,
                    height: PartitionUiTokens.actionButtonHeight,
                    child: GlassmorphismButton(
                      text: '다음으로',
                      onTap: _handleNext,
                      width: screenWidth * 0.9 - 40,
                      height: PartitionUiTokens.actionButtonHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _choreRowHeight = 41; // 기존 31px의 약 1.3배

  Widget _buildChoreRow(String chore) {
    final currentScore = _preferences[chore] ?? 0;

    return Container(
      height: _choreRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
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
        borderRadius: BorderRadius.circular(0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 집안일 이름
              Expanded(
                child: Text(
                  chore,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _PreferenceSelector(
                currentScore: currentScore,
                onScoreChanged: (score) => _updatePreference(chore, score),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBox(String categoryName, List<String> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 카테고리 이름 (컴포넌트 안에 포함)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  categoryName,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Pretendard Variable',
                    height: 1.0,
                  ),
                ),
              ),
              // 물품 버튼들 (Wrap으로 자동 줄바꿈)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((item) => _buildItemButton(item)).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemButton(String item) {
    final isSelected = _selectedItems.contains(item);

    return _SharedItemButton(
      item: item,
      isSelected: isSelected,
      onTap: () => _toggleItem(item),
    );
  }
}

/// 선호도 1~5점 — 탭·가로 드래그 모두 지원
class _PreferenceSelector extends StatelessWidget {
  final int currentScore;
  final ValueChanged<int> onScoreChanged;

  static const double circleSize = 16.8; // 기존 14px의 1.2배
  static const double circleSpacing = 5;

  const _PreferenceSelector({
    required this.currentScore,
    required this.onScoreChanged,
  });

  int _scoreFromLocalX(double localX) {
    final step = circleSize + circleSpacing;
    final firstCenter = circleSize / 2;
    final lastCenter = firstCenter + step * 4;
    final clampedX = localX.clamp(firstCenter, lastCenter);
    final index = ((clampedX - firstCenter) / step).round();
    return (index + 1).clamp(1, 5);
  }

  @override
  Widget build(BuildContext context) {
    const totalWidth = circleSize * 5 + circleSpacing * 4;

    return SizedBox(
      width: totalWidth,
      height: circleSize + 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          onScoreChanged(_scoreFromLocalX(details.localPosition.dx));
        },
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localX = box.globalToLocal(details.globalPosition).dx;
          onScoreChanged(_scoreFromLocalX(localX));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = currentScore >= score;
            return _PreferenceCircle(
              isSelected: isSelected,
              size: circleSize,
              onTap: () => onScoreChanged(score),
              margin: EdgeInsets.only(left: index == 0 ? 0 : circleSpacing),
            );
          }),
        ),
      ),
    );
  }
}

// 선호도 선택 동그라미 위젯 (클릭 효과 포함)
class _PreferenceCircle extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final EdgeInsets margin;
  final double size;

  const _PreferenceCircle({
    required this.isSelected,
    required this.onTap,
    required this.margin,
    this.size = 16.8,
  });

  @override
  State<_PreferenceCircle> createState() => _PreferenceCircleState();
}

class _PreferenceCircleState extends State<_PreferenceCircle> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _isPressed = false;
        });
        widget.onTap();
      },
      onTapCancel: () {
        setState(() {
          _isPressed = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        width: widget.size,
        height: widget.size,
        margin: widget.margin,
        transform: Matrix4.identity()..scale(_isPressed ? 0.85 : 1.0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isSelected
              ? Colors.white
              : Colors.transparent,
          gradient: widget.isSelected
              ? null
              : const RadialGradient(
                  center: Alignment(0.1014, 0.2027),
                  radius: 1.4214,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.15),
                    Color.fromRGBO(255, 255, 255, 0.30),
                  ],
                  stops: [0.0, 1.0],
                ),
          border: widget.isSelected
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1,
                ),
        ),
      ),
    );
  }
}

// 공용 물품 버튼 위젯 (클릭 효과 포함)
class _SharedItemButton extends StatefulWidget {
  final String item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SharedItemButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SharedItemButton> createState() => _SharedItemButtonState();
}

class _SharedItemButtonState extends State<_SharedItemButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _isPressed = false;
        });
        widget.onTap();
      },
      onTapCancel: () {
        setState(() {
          _isPressed = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()..scale(_isPressed ? 0.95 : 1.0),
        child: IntrinsicWidth(
          child: Container(
            constraints: BoxConstraints(
              minWidth: widget.item.characters.length <= 2 ? 48 : 0,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(31.369),
              gradient: const RadialGradient(
                center: Alignment(-0.1212, -0.1178),
                radius: 1.6319,
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.15),
                  Color.fromRGBO(255, 255, 255, 0.41),
                ],
                stops: [0.0, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.25),
                  blurRadius: 18.822,
                  spreadRadius: 0,
                  offset: const Offset(2.51, 2.51),
                ),
              ],
              border: widget.isSelected
                  ? Border.all(
                      color: Colors.white,
                      width: 1.5,
                    )
                  : Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 0.5,
                    ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(31.369),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.273855686187744, sigmaY: 6.273855686187744),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  child: Text(
                    widget.item,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

