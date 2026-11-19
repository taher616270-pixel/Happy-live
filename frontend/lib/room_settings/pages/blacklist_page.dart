import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key});
  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}
class _BlacklistPageState extends State<BlacklistPage> {
  int tab = 1;
  static const tabs = ['طرد ابدي', 'طرد مؤقت'];
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: RsAppBar(title: 'القائمة السوداء', actions: [IconButton(icon: const Icon(Icons.search, color: RS.text, size: 24), onPressed: () => showRsToast(context, 'البحث غير متاح حاليًا'))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: Row(children: [
        for (var i = 0; i < tabs.length; i++) ...[
          GestureDetector(onTap: () => setState(() => tab = i), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: tab == i ? RS.chipFill : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: tab == i ? RS.primary : const Color(0xFFE3E4E8))), child: Text(tabs[i], style: const TextStyle(color: RS.text, fontSize: 11.5, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 8),
        ],
      ])),
      const Expanded(child: EmptyState('قائمة الحظر لم يتم ربطها بالخادم بعد')),
    ]),
  );
}
