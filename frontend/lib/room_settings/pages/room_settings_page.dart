import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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

  Future<String?> _showCoverSourceSheet() {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      return showCupertinoModalPopup<String>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('تغيير صورة الغرفة'),
          message: const Text('اختر طريقة إضافة صورة الغرفة'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, 'gif'),
              child: const Text('اختيار ملف GIF'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, 'album'),
              child: const Text('ألبوم الصور'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, 'camera'),
              child: const Text('التقاط صورة'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'cancel'),
            child: const Text('إلغاء'),
          ),
        ),
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8D8DE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                _coverSourceOption(sheetContext, 'gif', 'اختيار ملف GIF', Icons.gif_box_outlined),
                _coverSourceOption(sheetContext, 'album', 'ألبوم الصور', Icons.photo_library_outlined),
                _coverSourceOption(sheetContext, 'camera', 'التقاط صورة', Icons.camera_alt_outlined),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        color: Color(0xFF777482),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverSourceOption(
    BuildContext sheetContext,
    String value,
    String title,
    IconData icon,
  ) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: const SizedBox.shrink(),
        title: Row(
          children: [
            Icon(icon, color: const Color(0xFFD99B25), size: 25),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: RS.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        onTap: () => Navigator.pop(sheetContext, value),
      );

  List<int> _forceGifInfiniteLoop(List<int> source) {
    final bytes = List<int>.from(source);
    if (bytes.length < 13) return bytes;
    final signature = String.fromCharCodes(bytes.take(6));
    if (signature != 'GIF87a' && signature != 'GIF89a') return bytes;

    const marker = 'NETSCAPE2.0';
    final markerBytes = marker.codeUnits;
    for (var i = 0; i <= bytes.length - markerBytes.length - 9; i++) {
      var matches = true;
      for (var j = 0; j < markerBytes.length; j++) {
        if (bytes[i + j] != markerBytes[j]) {
          matches = false;
          break;
        }
      }
      if (matches && i + 14 < bytes.length &&
          bytes[i + 11] == 0x03 && bytes[i + 12] == 0x01) {
        bytes[i + 13] = 0;
        bytes[i + 14] = 0;
        return bytes;
      }
    }

    final packed = bytes[10];
    var insertAt = 13;
    if ((packed & 0x80) != 0) {
      insertAt += 3 * (1 << ((packed & 0x07) + 1));
    }
    if (insertAt > bytes.length) return bytes;
    bytes.insertAll(insertAt, [
      0x21, 0xFF, 0x0B,
      ...markerBytes,
      0x03, 0x01, 0x00, 0x00, 0x00,
    ]);
    return bytes;
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    final choice = await _showCoverSourceSheet();
    if (!mounted || choice == null || choice == 'cancel') return;

    try {
      if (choice == 'gif') {
        final selected = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['gif'],
          withData: true,
        );
        if (selected == null || selected.files.isEmpty) return;
        final file = selected.files.single;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          showRsToast(context, 'تعذر قراءة ملف GIF من الجهاز');
          return;
        }
        if (bytes.length > 5 * 1024 * 1024) {
          showRsToast(context, 'حجم الصورة يجب ألا يتجاوز 5 ميجابايت');
          return;
        }
        setState(() => _uploadingCover = true);
        await c.setCoverBytes(
          Uint8List.fromList(_forceGifInfiniteLoop(bytes)),
          file.name.isEmpty ? 'room-cover.gif' : file.name,
        );
      } else {
        final image = await _imagePicker.pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
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
        await c.setCoverBytes(
          bytes,
          image.name.isEmpty ? 'room-cover.jpg' : image.name,
        );
      }
      if (mounted) showRsToast(context, 'تم تحديث صورة الغرفة');
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
                                  : HappyNetworkImage(c.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE9EEF2), child: Icon(Icons.broken_image_outlined, color: RS.gray))),
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
