import 'package:flutter/material.dart';
import '../models.dart';
import '../room_settings_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class AdminLogPage extends StatefulWidget {
  final RoomSettingsController c;
  const AdminLogPage({super.key, required this.c});
  @override
  State<AdminLogPage> createState() => _AdminLogPageState();
}
class _AdminLogPageState extends State<AdminLogPage> {
  static const cats = ['طرد', 'تعيين الأدوار', 'مغادرة من المقعد', 'قفل الغرفة'];
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final items = widget.c.logs.where((e) => e.category == cats[tab]).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: RsAppBar(title: 'سجل عمليات المشرف', actions: [IconButton(icon: const Icon(Icons.search, color: RS.text, size: 24), onPressed: () => showRsToast(context, 'البحث غير متاح حاليًا'))]),
      body: Column(children: [
        SizedBox(height: 46, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), itemCount: cats.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) {
          final on = i == tab;
          return GestureDetector(onTap: () => setState(() => tab = i), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, decoration: BoxDecoration(color: on ? RS.primaryDark : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? RS.primaryDark : const Color(0xFFE3E4E8))), child: Text(cats[i], style: TextStyle(color: on ? Colors.white : RS.gray, fontSize: 12, fontWeight: FontWeight.w800))));
        })),
        Expanded(child: items.isEmpty ? const EmptyState('لا توجد سجلات محفوظة للغرفة') : ListView.separated(itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1, color: RS.divider), itemBuilder: (_, i) => _LogTile(e: items[i]))),
      ]),
    );
  }
}
class _LogTile extends StatelessWidget {
  final AdminLogEntry e;
  const _LogTile({required this.e});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    UserAvatar(url: e.user.avatarUrl, size: 40), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(e.user.name, style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w900)), const SizedBox(width: 6), LevelBadge(e.user.level)]),
      const SizedBox(height: 4), Text(e.text, style: const TextStyle(color: RS.gray, fontSize: 12, height: 1.4)),
    ])),
    const SizedBox(width: 8), Text(e.time, style: const TextStyle(color: RS.gray, fontSize: 11)),
  ]));
}
