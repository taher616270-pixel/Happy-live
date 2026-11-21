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
  static const cats = ['طرد', 'كتم', 'تعيين الأدوار'];
  int tab = 0;
  String query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.c,
      builder: (context, _) {
        final items = widget.c.logs.where((e) {
          final categoryMatches = e.category == cats[tab];
          final queryMatches = e.user.name.toLowerCase().contains(query.toLowerCase()) ||
              e.text.toLowerCase().contains(query.toLowerCase());
          return categoryMatches && queryMatches;
        }).toList();
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: RsAppBar(
            title: 'سجل عمليات المشرف',
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: RS.text),
                onPressed: widget.c.refreshModeration,
                tooltip: 'تحديث',
              ),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: TextField(
                onChanged: (value) => setState(() => query = value.trim()),
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'بحث في السجل',
                  hintStyle: const TextStyle(color: RS.gray, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: RS.gray, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF6F7F8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final on = i == tab;
                  return GestureDetector(
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? const Color(0xFFD4AF37) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: on ? const Color(0xFFD4AF37) : const Color(0xFFE3E4E8)),
                      ),
                      child: Text(cats[i], style: TextStyle(color: on ? Colors.white : RS.gray, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  );
                },
              ),
            ),
            if (widget.c.moderationError != null) HintBar(widget.c.moderationError!),
            Expanded(
              child: widget.c.moderationLoading
                  ? const Center(child: CircularProgressIndicator(color: RS.primary))
                  : items.isEmpty
                      ? const EmptyState('لا توجد عمليات مسجلة للغرفة')
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: RS.divider),
                          itemBuilder: (_, i) => _LogTile(e: items[i]),
                        ),
            ),
          ]),
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  final AdminLogEntry e;
  const _LogTile({required this.e});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const UserAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.user.name, style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(e.text, style: const TextStyle(color: RS.gray, fontSize: 12, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(e.time, style: const TextStyle(color: RS.gray, fontSize: 11)),
        ]),
      );
}
