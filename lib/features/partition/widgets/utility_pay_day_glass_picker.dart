import 'package:flutter/material.dart';
import 'package:partition_app/shared/widgets/partition_glass_dialog.dart';
import 'package:partition_app/shared/widgets/partition_modal_close_button.dart';

/// 매달 결제일(1–31일) — 글래스모피즘 목록 모달.
Future<int?> showGlassUtilityPayDayPicker(
  BuildContext context, {
  required int currentDay,
}) {
  final selected = currentDay.clamp(1, 31);
  final mq = MediaQuery.of(context);
  final dialogW = (mq.size.width - 48).clamp(280.0, 360.0);
  final dialogH = (mq.size.height * 0.52).clamp(280.0, 480.0);

  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.52),
    builder: (ctx) {
      return PartitionGlassDialog(
        constraints: BoxConstraints.tightFor(
          width: dialogW,
          height: dialogH,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '매달 결제일',
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
                    onPressed: () => Navigator.pop(ctx),
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
                itemCount: 31,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.white.withOpacity(0.08),
                ),
                itemBuilder: (c, i) {
                  final day = i + 1;
                  final sel = day == selected;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, day),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '매월 $day일',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w500,
                                  fontFamily: 'Pretendard Variable',
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            if (sel)
                              const Icon(
                                Icons.check_rounded,
                                color: Colors.white70,
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
          ],
        ),
      );
    },
  );
}
