import 'package:flutter/material.dart';
import '../models.dart';
import '../room_settings_controller.dart';
import '../sheets/choice_sheet.dart';
import '../sheets/seats_sheet.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'admin_log_page.dart';
import 'admin_permissions_page.dart';
import 'blacklist_page.dart';
import 'edit_text_page.dart';

class RoomSettingsPage extends StatefulWidget {
  final RoomSettingsController c;
  const RoomSettingsPage({super.key, required this.c});
  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  RoomSettingsController get c => widget.c;
  @override
  void initState() { super.initState(); c.load(); }

  List<MapEntry<Audience, String>> _opts(List<Audience> l) => l.map((a) => MapEntry(a, audienceLabel(a))).toList();

  Future<void> _run(Future<void> Function() action) async {
    try { await action(); }
    catch (e) { if (mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', '')); }
  }

  @override
  Widget build(BuildContext context) {
    const two = [Audience.everyone, Audience.membersOnly];
    const three = [Audience.everyone, Audience.membersOnly, Audience.ownerAndAdmins];
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.white,
        appBar: const RsAppBar(title: 'الإعدادات'),
        body: c.loading
            ? const Center(child: CircularProgressIndicator(color: RS.primary))
            : Container(
                color: Colors.white,
                child: ListView(padding: EdgeInsets.zero, children: [
          if (c.error != null) HintBar(c.error!),
          SettingsTile(title: 'الغلاف', trailing: ClipRRect(borderRadius: BorderRadius.circular(3), child: Container(width: 44, height: 44, color: const Color(0xFFB9C4D6), child: c.coverUrl == null || c.coverUrl!.isEmpty ? const Icon(Icons.image, color: Colors.white) : Image.network(c.coverUrl!, fit: BoxFit.cover))), onTap: () => showRsToast(context, 'رفع الغلاف غير مربوط بالخادم بعد')),
          SettingsTile(title: 'الإسم', value: c.name, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTextPage(title: 'الإسم', initial: c.name, maxLength: 30, onSave: c.setName)))),
          SettingsTile(title: 'الإعلان', value: c.announcement, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTextPage(title: 'الإعلان', initial: c.announcement, maxLength: 200, onSave: c.setAnnouncement)))),
          SettingsTile(title: 'مكافأة الغرفة', onTap: () => showRsToast(context, 'قريبًا')),
          SettingsTile(title: 'عدد المقاعد', value: '${c.seats}', onTap: () async { final v = await showSeatsSheet(context, current: c.seats); if (v != null) await _run(() => c.setSeats(v)); }),
          SettingsTile(title: 'أخذ مايك يتطلب تقديم طلب', value: c.micRequestMode, onTap: () async { final v = await showChoiceSheet<String>(context, title: 'أخذ مايك يتطلب تقديم طلب', options: const [MapEntry('إغلاق', 'إغلاق'), MapEntry('تفعيل', 'تفعيل')], selected: c.micRequestMode); if (v != null) await _run(() => c.setMicRequestMode(v)); }),
          SwitchTile(title: 'إطلاق الألعاب النارية في الغرفة تلقائيًا', value: c.autoGames, onChanged: (v) => _run(() => c.setAutoGames(v))),
          SettingsTile(title: 'من يمكنه دخول الغرفة', value: audienceLabel(c.whoEnter), onTap: () async { final v = await showChoiceSheet<Audience>(context, title: 'من يمكنه دخول الغرفة', options: _opts(two), selected: c.whoEnter); if (v != null) await _run(() => c.setWhoEnter(v)); }),
          SettingsTile(title: 'من يمكنه التحدث بالميكروفون', value: audienceLabel(c.whoMic), onTap: () async { final v = await showChoiceSheet<Audience>(context, title: 'من يمكنه التحدث بالميكروفون', options: _opts(three), selected: c.whoMic); if (v != null) await _run(() => c.setWhoMic(v)); }),
          SettingsTile(title: 'من يمكنه الدردشة', value: audienceLabel(c.whoChat), onTap: () async { final v = await showChoiceSheet<Audience>(context, title: 'من يمكنه الدردشة', options: _opts(three), selected: c.whoChat); if (v != null) await _run(() => c.setWhoChat(v)); }),
          SettingsTile(title: 'من يمكنه ارسال حقيبة الحظ', value: audienceLabel(c.whoLuck), onTap: () async { final v = await showChoiceSheet<Audience>(context, title: 'من يمكنه ارسال حقيبة الحظ', options: _opts(three), selected: c.whoLuck); if (v != null) await _run(() => c.setWhoLuck(v)); }),
          SettingsTile(title: 'قائمة الكتم', onTap: () => showRsToast(context, 'قائمة الكتم غير مربوطة بالخادم بعد')),
          SettingsTile(title: 'القائمة السوداء', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlacklistPage()))),
          SettingsTile(title: 'سجل عمليات المشرف', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLogPage(c: c)))),
          SettingsTile(title: 'اعدادات صلاحيات المشرفين', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPermissionsPage(c: c)))),
          const SizedBox(height: 24),
                ]),
              ),
      ),
    );
  }
}
