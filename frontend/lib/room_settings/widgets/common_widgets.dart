import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import '../theme.dart';

class RsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const RsAppBar({super.key, required this.title, this.actions});
  @override
  Size get preferredSize => const Size.fromHeight(48);
  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 48,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: RS.text),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: RS.text, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: actions,
      );
}

class HintBar extends StatelessWidget {
  final String text;
  const HintBar(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: RS.hintBar,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(text, maxLines: 2,
            style: const TextStyle(color: RS.gray, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class GroupGap extends StatelessWidget {
  const GroupGap({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 6, color: RS.groupGap);
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? textColor;
  const PrimaryButton({super.key, required this.label, this.subtitle, this.onTap, this.backgroundColor, this.textColor});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final h = subtitle == null ? 44.0 : 54.0;
    return Material(
      color: enabled ? (backgroundColor ?? RS.primary) : RS.shade,
      borderRadius: BorderRadius.circular(h / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(h / 2),
        child: SizedBox(
          height: h, width: double.infinity,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: enabled ? (textColor ?? Colors.white) : RS.lightGray, fontSize: 15, fontWeight: FontWeight.w800)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ])),
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final String title;
  final String? value;
  final Offset valueOffset;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  const SettingsTile({super.key, required this.title, this.value, this.valueOffset = Offset.zero, this.trailing, this.chevron = true, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3), width: 1))),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w600))),
            if (value != null) Flexible(child: Transform.translate(offset: valueOffset, child: Text(value!, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RS.text, fontSize: 13, fontWeight: FontWeight.w800)))),
            if (trailing != null) trailing!,
            if (chevron) ...[const SizedBox(width: 10), const Icon(Icons.chevron_left, color: RS.lightGray, size: 18)],
          ]),
        ),
      );
}

class SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchTile({super.key, required this.title, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SettingsTile(
        title: title, chevron: false,
        trailing: CupertinoSwitch(value: value, activeColor: RS.switchGreen, onChanged: onChanged),
      );
}

class UserAvatar extends StatelessWidget {
  final String? url;
  final double size;
  const UserAvatar({super.key, this.url, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: const Color(0xFFD9DBE0),
          image: url == null || url!.isEmpty ? null : DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover),
        ),
        child: url == null || url!.isEmpty ? Icon(Icons.person, color: Colors.white, size: size * .6) : null,
      );
}

class LevelBadge extends StatelessWidget {
  final int level;
  const LevelBadge(this.level, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF3E9B6A), Color(0xFF2C7A52)]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('V$level', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}

class EmptyState extends StatelessWidget {
  final String text;
  final String? asset;
  const EmptyState(this.text, {super.key, this.asset});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          asset != null
              ? Image.asset(asset!, width: 130)
              : Container(width: 110, height: 110,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE9FBF7)),
                  child: const Icon(Icons.inbox_outlined, color: Color(0xFF9FE6D8), size: 52)),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: RS.gray, fontSize: 13)),
        ]),
      );
}

void showRsToast(BuildContext context, String msg) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => Positioned(
    top: MediaQuery.of(context).size.height * .55, left: 0, right: 0,
    child: Center(child: Material(color: Colors.transparent, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xCC333333), borderRadius: BorderRadius.circular(8)),
      child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
    ))),
  ));
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1500), () { if (entry.mounted) entry.remove(); });
}
