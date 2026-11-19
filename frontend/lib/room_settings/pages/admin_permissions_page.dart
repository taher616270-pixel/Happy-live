import 'package:flutter/material.dart';
import '../room_settings_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'permission_picker_page.dart';

class AdminPermissionsPage extends StatelessWidget {
  final RoomSettingsController c;
  const AdminPermissionsPage({super.key, required this.c});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final children = <Widget>[const HintBar('يمتلك المالك دائمًا جميع صلاحيات المشرفين')];
      for (var i = 0; i < c.permissions.length; i++) {
        final p = c.permissions[i];
        if (i > 0 && c.permissions[i - 1].group != p.group) children.add(const GroupGap());
        children.add(InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PermissionPickerPage(c: c, permission: p))),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4), Text(p.subtitle, style: const TextStyle(color: RS.gray, fontSize: 11.5)),
            ])),
            const Icon(Icons.chevron_left, color: RS.lightGray, size: 18),
          ])),
        ));
      }
      children.add(const SizedBox(height: 24));
      return Scaffold(backgroundColor: Colors.white, appBar: const RsAppBar(title: 'اعدادات صلاحيات المشرفين'), body: ListView(padding: EdgeInsets.zero, children: children));
    },
  );
}
