import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../room_settings_controller.dart';
import '../sheets/choice_sheet.dart';
import '../../widgets/mic_count_sheet.dart';
import '../../models/mic_layout.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'admin_log_page.dart';
import 'admin_permissions_page.dart';
import 'blacklist_page.dart';
import 'edit_text_page.dart';
import 'muted_users_page.dart';

class RoomSettingsPage extends StatefulWidget {
  final RoomSettingsController c;
  const RoomSettingsPage({super.key, required this.c});
  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  RoomSettingsController get c => widget.c;
  final ImagePicker _imagePicker = ImagePicker();
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    c.load();
  }

  List<MapEntry<Audience, String>> _opts(List<Audience> values) =>
      values.map((a) => MapEntry(a, audienceLabel(a))).toList();

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        showRsToast(context, 'حجم الصورة يجب ألا يتجاوز 5 ميجابايت');
        return;
      }
      setState(() => _uploadingCover = true);
      await c.setCoverBytes(bytes, image.name.isEmpty ? 'room-cover.jpg' : image.name);
      if (mounted) showRsToast(context, 'تم تحديث غلاف الغرفة');
    } catch (e) {
      if (mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const entryOptions = [Audience.everyone, Audience.membersOnly, Audience.ownerAndAdmins];
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
                  SettingsTile(
                    title: 'الغلاف',
                    trailing: _uploadingCover
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: RS.primary))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: c.coverUrl == null || c.coverUrl!.isEmpty
                                  ? const ColoredBox(color: Color(0xFFE9EEF2), child: Icon(Icons.add_photo_alternate_outlined, color: RS.gray))
                                  : Image.network(c.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE9EEF2), child: Icon(Icons.broken_image_outlined, color: RS.gray))),
                            ),
                          ),
                    onTap: _pickCover,
                  ),
                  SettingsTile(
                    title: 'الإسم',
                    value: c.name,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTextPage(title: 'الإسم', initial: c.name, maxLength: 20, onSave: c.setName))),
                  ),
                  SettingsTile(
                    title: 'الإعلان',
                    value: c.announcement,
                    valueMaxLines: 5,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTextPage(title: 'الإعلان', initial: c.announcement, maxLength: 200, onSave: c.setAnnouncement))),
                  ),
                  SettingsTile(
                    title: 'عدد المقاعد',
                    value: c.seats.toString(),
                    onTap: () async {
                      final layoutId = await showMicCountSheet(
                        context,
                        currentId: c.micLayoutId,
                      );
                      if (layoutId == null || !mounted) return;
                      final layout = micLayoutById(layoutId);
                      await _run(() => c.setMicLayout(layout.id, layout.count));
                    },
                  ),

                  SettingsTile(
                    title: 'من يمكنه دخول الغرفة',
                    value: audienceLabel(c.whoEnter),
                    onTap: () async {
                      final value = await showChoiceSheet<Audience>(context, title: 'من يمكنه دخول الغرفة', options: _opts(entryOptions), selected: c.whoEnter);
                      if (value != null) await _run(() => c.setWhoEnter(value));
                    },
                  ),
                  SettingsTile(
                    title: 'من يمكنه التحدث بالميكروفون',
                    value: audienceLabel(c.whoMic),
                    onTap: () async {
                      final value = await showChoiceSheet<Audience>(context, title: 'من يمكنه التحدث بالميكروفون', options: _opts(three), selected: c.whoMic);
                      if (value != null) await _run(() => c.setWhoMic(value));
                    },
                  ),
                  SettingsTile(
                    title: 'من يمكنه الدردشة',
                    value: audienceLabel(c.whoChat),
                    onTap: () async {
                      final value = await showChoiceSheet<Audience>(context, title: 'من يمكنه الدردشة', options: _opts(three), selected: c.whoChat);
                      if (value != null) await _run(() => c.setWhoChat(value));
                    },
                  ),
                  SettingsTile(
                    title: 'من يمكنه إرسال حقيبة الحظ',
                    value: audienceLabel(c.whoLuck),
                    onTap: () async {
                      final value = await showChoiceSheet<Audience>(context, title: 'من يمكنه إرسال حقيبة الحظ', options: _opts(three), selected: c.whoLuck);
                      if (value != null) await _run(() => c.setWhoLuck(value));
                    },
                  ),
                  SettingsTile(
                    title: 'قائمة الكتم',
                    value: c.muted.length.toString(),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MutedUsersPage(c: c))),
                  ),
                  SettingsTile(
                    title: 'القائمة السوداء',
                    value: (c.bans.length + c.kicks.length).toString(),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BlacklistPage(c: c))),
                  ),
                  SettingsTile(
                    title: 'سجل عمليات المشرف',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLogPage(c: c))),
                  ),
                  SettingsTile(
                    title: 'إعدادات صلاحيات المشرفين',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPermissionsPage(c: c))),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
      ),
    );
  }
}
