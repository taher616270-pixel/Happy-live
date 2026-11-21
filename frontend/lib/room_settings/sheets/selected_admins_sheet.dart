import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

Future<List<String>?> showSelectedAdminsSheet(BuildContext context, {required List<RoomUser> admins, required List<String> initial}) {
  return showModalBottomSheet<List<String>>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _Sheet(admins: admins, initial: initial),
  );
}

class _Sheet extends StatefulWidget {
  final List<RoomUser> admins;
  final List<String> initial;
  const _Sheet({required this.admins, required this.initial});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final Set<String> selected = widget.initial.toSet();
  String query = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.admins.where((u) => u.name.toLowerCase().contains(query.toLowerCase()) || u.numericId.contains(query)).toList();
    return Container(
      height: MediaQuery.of(context).size.height * .92,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, size: 22, color: RS.text)),
          const Expanded(child: Center(child: Text('المشرفين المحددين', style: TextStyle(color: RS.text, fontSize: 16, fontWeight: FontWeight.w900)))),
          const SizedBox(width: 22),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(hintText: 'بحث', hintStyle: const TextStyle(color: RS.lightGray, fontSize: 14), prefixIcon: const Icon(Icons.search, color: RS.gray, size: 20), filled: true, fillColor: RS.bg, contentPadding: const EdgeInsets.symmetric(vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)),
        )),
        const SizedBox(height: 8),
        Expanded(child: list.isEmpty ? const EmptyState('لا يوجد مشرفون معيّنون للغرفة') : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final u = list[i], on = selected.contains(list[i].id);
            return InkWell(onTap: () => setState(() => on ? selected.remove(u.id) : selected.add(u.id)), child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                UserAvatar(url: u.avatarUrl, size: 62), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w800))), const SizedBox(width: 6), LevelBadge(u.level)]),
                  const SizedBox(height: 4), Text('ID: ${u.numericId}', style: const TextStyle(color: RS.gray, fontSize: 12)),
                ])),
                Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0xFFD4AF37) : Colors.transparent, border: Border.all(color: on ? const Color(0xFFD4AF37) : RS.lightGray)), child: on ? const Icon(Icons.check, size: 15, color: Colors.white) : null),
              ]),
            ));
          },
        )),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: PrimaryButton(label: 'تم (${selected.length})', backgroundColor: const Color(0xFFD4AF37), onTap: selected.isEmpty ? null : () => Navigator.pop(context, selected.toList()))),
      ])),
    );
  }
}
