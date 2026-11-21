import 'package:flutter/material.dart';
import '../models.dart';
import '../room_settings_controller.dart';
import '../sheets/selected_admins_sheet.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class PermissionPickerPage extends StatefulWidget {
  final RoomSettingsController c;
  final AdminPermission permission;
  const PermissionPickerPage({super.key, required this.c, required this.permission});
  @override
  State<PermissionPickerPage> createState() => _PermissionPickerPageState();
}
class _PermissionPickerPageState extends State<PermissionPickerPage> {
  late PermissionLevel level = widget.permission.level;
  late List<String> ids = List.of(widget.permission.adminIds);
  @override
  Widget build(BuildContext context) {
    final p = widget.permission;
    return Scaffold(backgroundColor: Colors.white, appBar: RsAppBar(title: p.title), body: Column(children: [
      HintBar(p.hint), const SizedBox(height: 6),
      for (final l in PermissionLevel.values)
        InkWell(onTap: () => setState(() => level = l), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17), child: Row(children: [
          _Radio(on: level == l), const SizedBox(width: 10),
          Text(levelLabel(l), style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w600)),
        ]))),
      if (level == PermissionLevel.selectedAdmins)
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Align(alignment: AlignmentDirectional.centerStart, child: GestureDetector(
          onTap: () async {
            final r = await showSelectedAdminsSheet(context, admins: widget.c.admins, initial: ids);
            if (r != null) setState(() => ids = r);
          },
          child: Container(width: 50, height: 50, decoration: const BoxDecoration(color: RS.penBg, shape: BoxShape.circle), child: const Icon(Icons.edit_outlined, color: RS.penIcon, size: 22)),
        ))),
      const Spacer(),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 18), child: PrimaryButton(label: 'تم', backgroundColor: const Color(0xFFD4AF37), onTap: () async {
        try {
          await widget.c.savePermission(p, level, ids);
          if (context.mounted) { Navigator.pop(context); showRsToast(context, 'تم بنجاح'); }
        } catch (e) { if (context.mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', '')); }
      }))),
    ]));
  }
}
class _Radio extends StatelessWidget {
  final bool on;
  const _Radio({required this.on});
  @override
  Widget build(BuildContext context) => Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0xFFD4AF37) : Colors.transparent, border: Border.all(color: on ? const Color(0xFFD4AF37) : RS.lightGray, width: 1.2)), child: on ? const Icon(Icons.check, size: 14, color: Colors.white) : null);
}
