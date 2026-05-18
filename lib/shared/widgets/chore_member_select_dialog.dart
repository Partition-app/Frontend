import 'package:flutter/material.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 직접 배정 — 그룹 멤버 단일 선택
class ChoreMemberSelectDialog extends StatefulWidget {
  const ChoreMemberSelectDialog({
    super.key,
    required this.members,
    this.initialUserId,
  });

  final List<HouseholdMemberBrief> members;
  final int? initialUserId;

  @override
  State<ChoreMemberSelectDialog> createState() => _ChoreMemberSelectDialogState();
}

class _ChoreMemberSelectDialogState extends State<ChoreMemberSelectDialog> {
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.initialUserId;
    if (_selectedUserId != null &&
        !widget.members.any((m) => m.userId == _selectedUserId)) {
      _selectedUserId =
          widget.members.isNotEmpty ? widget.members.first.userId : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogW = (size.width - 48).clamp(280.0, 340.0);
    final dialogH = (size.height * 0.5).clamp(280.0, 460.0);

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
                    '담당자 선택',
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
            child: widget.members.isEmpty
                ? Center(
                    child: Text(
                      '불러올 멤버가 없어요.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontFamily: 'Pretendard Variable',
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.members.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withOpacity(0.08),
                    ),
                    itemBuilder: (context, index) {
                      final member = widget.members[index];
                      final selected = _selectedUserId == member.userId;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedUserId = member.userId),
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
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                    color: selected
                                        ? Colors.white
                                        : Colors.transparent,
                                  ),
                                  child: selected
                                      ? Center(
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.black,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    member.name,
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
              onTap: _selectedUserId == null
                  ? null
                  : () => Navigator.pop(context, _selectedUserId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    '선택 완료',
                    style: TextStyle(
                      color: _selectedUserId == null
                          ? Colors.white38
                          : Colors.white,
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
