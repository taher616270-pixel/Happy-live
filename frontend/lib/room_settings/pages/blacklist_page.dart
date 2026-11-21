import 'package:flutter/material.dart';
import '../room_settings_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class BlacklistPage extends StatefulWidget {
  final RoomSettingsController c;
  const BlacklistPage({super.key, required this.c});
  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  int tab = 0;
  String query = '';
  static const tabs = ['حظر دائم', 'طرد مؤقت'];

  Future<void> _run(String action, Map<String, dynamic> row) async {
    final userId = (row['user_id'] ?? '').toString();
    if (userId.isEmpty) return;
    final name = (row['display_name'] ?? 'المستخدم').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(action == 'unban' ? 'رفع الحظر' : 'إلغاء الطرد', style: const TextStyle(color: Colors.black)),
        content: Text('هل تريد تنفيذ الإجراء على $name؟', style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.c.moderate(action, userId);
      if (mounted) showRsToast(context, 'تم تنفيذ الإجراء');
    } catch (e) {
      if (mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.c,
      builder: (context, _) {
        final source = tab == 0 ? widget.c.bans : widget.c.kicks;
        final items = source.where((row) {
          final name = (row['display_name'] ?? '').toString();
          final id = (row['public_id'] ?? '').toString();
          return name.toLowerCase().contains(query.toLowerCase()) || id.contains(query);
        }).toList();
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: RsAppBar(
            title: 'القائمة السوداء',
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  width: 170,
                  height: 36,
                  child: TextField(
                    onChanged: (v) => setState(() => query = v.trim()),
                    style: const TextStyle(color: Colors.black, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو ID',
                      hintStyle: const TextStyle(color: RS.gray, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: RS.gray, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      filled: true,
                      fillColor: const Color(0xFFF6F7F8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => tab = i),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: tab == i ? const Color(0xFFD4AF37) : RS.divider, width: tab == i ? 2 : 1)),
                          ),
                          child: Text(tabs[i], style: TextStyle(color: tab == i ? Colors.black : RS.gray, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.c.moderationError != null) HintBar(widget.c.moderationError!),
            Expanded(
              child: widget.c.moderationLoading
                  ? const Center(child: CircularProgressIndicator(color: RS.primary))
                  : items.isEmpty
                      ? EmptyState(tab == 0 ? 'لا يوجد مستخدمون محظورون' : 'لا يوجد طرد مؤقت نشط')
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: RS.divider),
                          itemBuilder: (context, index) {
                            final row = items[index];
                            final name = (row['display_name'] ?? 'مستخدم').toString();
                            final publicId = (row['public_id'] ?? '').toString();
                            final until = DateTime.tryParse((row['kicked_until'] ?? '').toString())?.toLocal();
                            final expiry = until == null ? '' : 'ينتهي ${until.year}/${until.month}/${until.day} ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
                            return ListTile(
                              title: Text(name, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                              subtitle: Text('ID: $publicId${expiry.isEmpty ? '' : ' • $expiry'}', style: const TextStyle(color: RS.gray, fontSize: 12)),
                              trailing: TextButton(
                                onPressed: () => _run(tab == 0 ? 'unban' : 'unkick', row),
                                child: Text(tab == 0 ? 'رفع الحظر' : 'إلغاء الطرد', style: const TextStyle(color: Color(0xFF168F79), fontWeight: FontWeight.w700)),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        );
      },
    );
  }
}
