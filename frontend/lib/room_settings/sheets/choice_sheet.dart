import 'package:flutter/material.dart';
import '../theme.dart';

Future<T?> showChoiceSheet<T>(BuildContext context, {required String title, required List<MapEntry<T, String>> options, required T selected}) {
  return showModalBottomSheet<T>(
    context: context, backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(title, style: const TextStyle(color: RS.gray, fontSize: 12))),
        const Divider(height: 1, color: RS.divider),
        for (final o in options)
          InkWell(onTap: () => Navigator.pop(ctx, o.key), child: SizedBox(height: 56, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(o.value, style: const TextStyle(color: RS.text, fontSize: 15, fontWeight: FontWeight.w800)),
            if (o.key == selected) ...[const SizedBox(width: 10), const Icon(Icons.check, color: RS.primary, size: 20)],
          ]))),
        Container(height: 8, color: RS.groupGap),
        InkWell(onTap: () => Navigator.pop(ctx), child: const SizedBox(height: 54, child: Center(child: Text('إلغاء', style: TextStyle(color: RS.gray, fontSize: 14))))),
      ])),
    ),
  );
}
