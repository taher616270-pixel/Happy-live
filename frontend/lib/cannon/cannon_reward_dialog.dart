import 'package:flutter/material.dart';
import '../widgets/centered_notification.dart';
import 'cannon_models.dart';
import 'cannon_service.dart';

Future<void> showCannonRewardDialog(BuildContext context, CannonClaim claim) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF08083F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF3AA8FF))),
        title: const Text('مكافأة مدفع الغرفة', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFFD66B), size: 52),
          const SizedBox(height: 12),
          Text(claim.name, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD66B), fontSize: 17, fontWeight: FontWeight.w700)),
          if (claim.type == 'coins') ...[
            const SizedBox(height: 6),
            Text('${claim.value} عملة', style: const TextStyle(color: Colors.white70)),
          ],
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () async {
              final ok = await CannonService.instance.claim(claim);
              if (!dialogContext.mounted) return;
              if (ok) {
                Navigator.pop(dialogContext);
              } else {
                showCenteredNotification(dialogContext, const SnackBar(content: Text('تعذر استلام المكافأة، حاول مرة أخرى')));
              }
            },
            child: const Text('استلام المكافأة'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لاحقًا')),
        ],
      ),
    ),
  );
}
