import 'package:flutter/material.dart';
import 'room_tools_api.dart';
import 'room_tools_models.dart';

Future<void> showKickLogSheet(BuildContext context, String roomId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _KickLogSheet(roomId: roomId),
  );
}

class _KickLogSheet extends StatefulWidget {
  const _KickLogSheet({required this.roomId});
  final String roomId;

  @override
  State<_KickLogSheet> createState() => _KickLogSheetState();
}

class _KickLogSheetState extends State<_KickLogSheet> {
  late Future<List<KickEntry>> _entries = RoomToolsApi.fetchKicks(widget.roomId);

  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .68,
        padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.paddingOf(context).bottom + 12),
        decoration: const BoxDecoration(
          color: Color(0xFF21152F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('سجل الطرد', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => setState(() => _entries = RoomToolsApi.fetchKicks(widget.roomId)), icon: const Icon(Icons.refresh, color: Color(0xFFE8C477))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
              ],
            ),
            Expanded(
              child: FutureBuilder<List<KickEntry>>(
                future: _entries,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFE8C477)));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('تعذر تحميل سجل الطرد', style: TextStyle(color: Colors.white70)),
                        TextButton(onPressed: () => setState(() => _entries = RoomToolsApi.fetchKicks(widget.roomId)), child: const Text('إعادة المحاولة')),
                      ]),
                    );
                  }
                  final rows = snapshot.data ?? const <KickEntry>[];
                  if (rows.isEmpty) return const Center(child: Text('لا توجد عمليات طرد مسجلة', style: TextStyle(color: Colors.white60)));
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: Colors.white12,
                          backgroundImage: item.avatar.startsWith('http') ? NetworkImage(item.avatar) : null,
                          child: item.avatar.startsWith('http') ? null : const Icon(Icons.person, color: Colors.white70),
                        ),
                        title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('بواسطة: ${item.by}${item.reason.isEmpty ? '' : ' • ${item.reason}'}\n${_date(item.time)}', style: const TextStyle(color: Colors.white60, height: 1.5)),
                        isThreeLine: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
