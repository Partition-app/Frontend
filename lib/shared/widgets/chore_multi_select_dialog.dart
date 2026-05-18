import 'package:flutter/material.dart';
import 'package:partition_app/shared/widgets/chore_assignment_common.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// AI·직접 배정 모달 공통 — 집안일 다중 선택 다이얼로그
class ChoreMultiSelectDialog extends StatefulWidget {
  const ChoreMultiSelectDialog({
    super.key,
    required this.initialSelected,
    this.allChores = kChoreDisplayNames,
  });

  final Set<String> initialSelected;
  final List<String> allChores;

  @override
  State<ChoreMultiSelectDialog> createState() => _ChoreMultiSelectDialogState();
}

class _ChoreMultiSelectDialogState extends State<ChoreMultiSelectDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  void _toggle(String chore) {
    setState(() {
      if (_selected.contains(chore)) {
        _selected.remove(chore);
      } else {
        _selected.add(chore);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogW = (size.width - 48).clamp(280.0, 340.0);
    final dialogH = (size.height * 0.58).clamp(320.0, 500.0);

    return PartitionGlassDialog(
      constraints: BoxConstraints.tightFor(
        width: dialogW,
        height: dialogH,
      ),
      borderRadius: BorderRadius.circular(24),
      blurSigma: 18,
      borderColor: Colors.white.withOpacity(0.22),
      gradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '집안일 선택',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Pretendard Variable',
                      height: 1.2,
                    ),
                  ),
                ),
                PartitionModalCloseButton(
                  onPressed: () => Navigator.pop(context),
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withOpacity(0.22),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              physics: const BouncingScrollPhysics(),
              itemCount: widget.allChores.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.white.withOpacity(0.08),
              ),
              itemBuilder: (context, index) {
                final chore = widget.allChores[index];
                final selected = _selected.contains(chore);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggle(chore),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              color:
                                  selected ? Colors.white : Colors.transparent,
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.black,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              chore,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontFamily: 'Pretendard Variable',
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withOpacity(0.22),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context, Set<String>.from(_selected)),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    '선택 완료',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard Variable',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
