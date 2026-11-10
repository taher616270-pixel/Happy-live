import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomMember {
  const RoomMember({required this.avatarUrl, required this.role, this.isOwner = false});
  final String avatarUrl;
  final String role;
  final bool isOwner;
}

class RoomInfo {
  const RoomInfo({
    required this.name, required this.flag, required this.id,
    required this.imageUrl, required this.imageBadge, required this.likes,
    required this.tribeName, required this.tribeOwner, required this.tribeLogoUrl,
    required this.level, required this.palaceStatus, required this.membersCount,
    required this.membersMax, required this.members, required this.announcement,
    required this.groupName, required this.groupCount, required this.groupDesc,
  });
  final String name, flag, id, imageUrl, imageBadge, tribeName, tribeOwner, tribeLogoUrl;
  final int likes, level, membersCount, membersMax, groupCount;
  final String palaceStatus, announcement, groupName, groupDesc;
  final List<RoomMember> members;
}

class _RoomInfoColors {
  static const bg = Color(0xFF1A1B2E);
  static const text = Color(0xFFE6E7F0);
  static const muted = Color(0xFF9A9CB0);
  static const chip = Color(0xFF262838);
  static const gold = Color(0xFFE8A92B);
  static const goldBg = Color(0xFF2A2417);
  static const levelBg = Color(0xFF2B1B2E);
  static const level = Color(0xFFC2456E);
  static const palace = Color(0xFFB8771A);
  static const join = Color(0xFF2EE0D0);
  static const follow = Color(0xFFFF6B2C);
}

Future<void> showRoomInfoSheet(
  BuildContext context,
  RoomInfo info, {
  VoidCallback? onJoin,
  VoidCallback? onFollow,
  VoidCallback? onMembersTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomInfoSheet(info: info, onJoin: onJoin, onFollow: onFollow, onMembersTap: onMembersTap),
  );
}

class _RoomInfoSheet extends StatelessWidget {
  const _RoomInfoSheet({required this.info, this.onJoin, this.onFollow, this.onMembersTap});
  final RoomInfo info;
  final VoidCallback? onJoin, onFollow, onMembersTap;

  @override
  Widget build(BuildContext context) {
    final c = _RoomInfoColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .78),
        decoration: const BoxDecoration(color: _RoomInfoColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 66, height: 70, child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: _networkImage(info.imageUrl, 66, 66)),
                    Positioned(left: 0, right: 0, bottom: 0, child: Container(
                      alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF3B5C), Color(0xFFFF6B3D)]), borderRadius: BorderRadius.circular(6)),
                      child: Text(info.imageBadge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    )),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.text, fontSize: 20, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 6),
                      Text(info.flag, style: const TextStyle(fontSize: 18)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: info.id));
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الـ ID'), duration: Duration(seconds: 1)));
                        },
                        child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('ID:${info.id}', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 15)),
                          const SizedBox(width: 6), const Icon(Icons.copy_rounded, color: _RoomInfoColors.muted, size: 16),
                        ])),
                      ),
                      _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF7A2F), size: 18),
                        const SizedBox(width: 6),
                        Text(_format(info.likes), style: const TextStyle(color: Color(0xFFFF7A2F), fontSize: 16)),
                      ]), color: const Color(0xFF3A2218)),
                    ]),
                  ])),
                  const Icon(Icons.error_outline, color: _RoomInfoColors.muted, size: 28),
                ]),
                const SizedBox(height: 20),
                SizedBox(height: 74, child: Row(children: [
                  Expanded(flex: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF4A3B1A))),
                    child: Row(children: [
                      _networkImage(info.tribeLogoUrl, 42, 42),
                      const SizedBox(width: 8),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(info.tribeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(info.tribeOwner, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xBFE8A92B), fontSize: 12)),
                      ])),
                    ]),
                  )),
                  const SizedBox(width: 7),
                  Expanded(flex: 3, child: _stat('Lv.${info.level}', 'مستوى الغرفة', c.levelBg, c.level)),
                  const SizedBox(width: 7),
                  Expanded(flex: 2, child: _stat('قصر', info.palaceStatus, c.goldBg, c.palace)),
                ])),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('أعضاء', style: TextStyle(color: _RoomInfoColors.text, fontSize: 21, fontWeight: FontWeight.w600)),
                  GestureDetector(onTap: onMembersTap, child: Row(children: [
                    Text('${info.membersCount}/${info.membersMax}', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 18)),
                    const Icon(Icons.chevron_left, color: _RoomInfoColors.muted),
                  ])),
                ]),
                const SizedBox(height: 14),
                SizedBox(height: 80, child: ListView.separated(
                  scrollDirection: Axis.horizontal, itemCount: info.members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final m = info.members[i];
                    return SizedBox(width: 58, child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                      CircleAvatar(radius: 28, backgroundColor: c.chip, backgroundImage: m.avatarUrl.startsWith('http') ? NetworkImage(m.avatarUrl) : null, child: m.avatarUrl.startsWith('http') ? null : const Icon(Icons.person, color: c.muted)),
                      Positioned(bottom: 4, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(color: m.isOwner ? const Color(0xFFFF4F81) : const Color(0xFFFF9800), borderRadius: BorderRadius.circular(10)),
                        child: Text(m.role, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      )),
                    ]));
                  },
                )),
                const SizedBox(height: 22),
                const Text('الإعلان', style: TextStyle(color: _RoomInfoColors.text, fontSize: 21, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(info.announcement.isEmpty ? 'لا يوجد إعلان لهذه الغرفة حاليًا' : info.announcement, style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 15, height: 1.5)),
                const SizedBox(height: 22),
                const Text('مجموعة الغرفة', style: TextStyle(color: _RoomInfoColors.text, fontSize: 21, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 32, backgroundColor: c.chip, backgroundImage: info.imageUrl.startsWith('http') ? NetworkImage(info.imageUrl) : null, child: info.imageUrl.startsWith('http') ? null : const Icon(Icons.groups, color: c.muted)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(info.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      _chip(Text('${info.groupCount} عضو', style: const TextStyle(color: c.muted, fontSize: 12))),
                    ]),
                    const SizedBox(height: 4),
                    Text(info.groupDesc.isEmpty ? 'لا يوجد وصف للمجموعة' : info.groupDesc, style: const TextStyle(color: c.muted, fontSize: 14, height: 1.4)),
                  ])),
                ]),
                const SizedBox(height: 12),
              ]),
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 14), child: Row(children: [
              Expanded(child: _button('متابعة', const Color(0xFF5A2A18), c.follow, onFollow)),
              const SizedBox(width: 14),
              Expanded(child: _button('انضمام', const Color(0xFF1B5E63), c.join, onJoin)),
            ])),
          ]),
        ),
      ),
    );
  }

  static Widget _networkImage(String url, double width, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: url.startsWith('http') ? Image.network(url, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imageFallback(width, height)) : _imageFallback(width, height),
  );

  static Widget _imageFallback(double width, double height) => Container(width: width, height: height, color: _RoomInfoColors.chip, alignment: Alignment.center, child: const Icon(Icons.image_outlined, color: _RoomInfoColors.muted));

  static Widget _chip(Widget child, {Color color = _RoomInfoColors.chip}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: child,
  );

  static Widget _stat(String title, String sub, Color bg, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.bold))),
      const SizedBox(height: 2),
      FittedBox(fit: BoxFit.scaleDown, child: Text(sub, style: TextStyle(color: color.withOpacity(.75), fontSize: 12))),
    ]),
  );

  static Widget _button(String title, Color bg, Color fg, VoidCallback? action) => SizedBox(
    height: 54,
    child: ElevatedButton(
      onPressed: action,
      style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
      child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
    ),
  );

  static String _format(int value) => value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
