import 'package:flutter/material.dart';
import 'square_country_flag.dart';
import 'package:flutter/services.dart';
import '../pages/edit_profile_page.dart';
import 'package:country_picker/country_picker.dart';

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
    this.isRoomOwner = false,
    this.ownerAvatarUrl = '',
  });
  final String name, flag, id, imageUrl, imageBadge, tribeName, tribeOwner, tribeLogoUrl;
  final int likes, level, membersCount, membersMax, groupCount;
  final String palaceStatus, announcement, groupName, groupDesc;
  final List<RoomMember> members;
  final bool isRoomOwner;
  final String ownerAvatarUrl;
}

class _RoomInfoColors {
  static const bg = Color(0xFF1E2133);
  static const text = Color(0xFFF3F4FA);
  static const muted = Color(0xFFB5B9CC);
  static const chip = Color(0xFF2B3047);
  static const gold = Color(0xFFF2C66D);
  static const goldBg = Color(0xFF353044);
  static const levelBg = Color(0xFF3A2D48);
  static const level = Color(0xFFFF9BC2);
  static const palace = Color(0xFFFFD27A);
  static const join = Color(0xFF2EE0D0);
  static const follow = Color(0xFFFF6B2C);
}

Future<void> showRoomInfoSheet(
  BuildContext context,
  RoomInfo info, {
  VoidCallback? onJoin,
  VoidCallback? onFollow,
  VoidCallback? onMembersTap,
  VoidCallback? onSettings,
  VoidCallback? onInvite,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomInfoSheet(info: info, onJoin: onJoin, onFollow: onFollow, onMembersTap: onMembersTap, onSettings: onSettings, onInvite: onInvite),
  );
}

class _RoomInfoSheet extends StatelessWidget {
  const _RoomInfoSheet({required this.info, this.onJoin, this.onFollow, this.onMembersTap, this.onSettings, this.onInvite});
  final RoomInfo info;
  final VoidCallback? onJoin, onFollow, onMembersTap, onSettings, onInvite;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .60),
        decoration: const BoxDecoration(color: _RoomInfoColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Transform.translate(
                  offset: const Offset(0, 1),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 60, height: 64, child: Stack(children: [
                    Transform.translate(
                      offset: const Offset(2, 2),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _networkImage(info.imageUrl, 60, 60)),
                    ),
                    Positioned(left: 0, right: 0, bottom: 0, child: Container(
                      alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF3B5C), Color(0xFFFF6B3D)]), borderRadius: BorderRadius.circular(6)),
                      child: Text(info.imageBadge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    )),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _countryFlag(context, info.flag),
                      const SizedBox(width: 6),
                      Flexible(child: Transform.translate(offset: const Offset(0, -3), child: Text(info.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.text, fontSize: 18, fontWeight: FontWeight.w700)))),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: info.id));
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الـ ID'), duration: Duration(seconds: 1)));
                        },
                        child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('ID:${info.id}', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 12)),
                          const SizedBox(width: 6), const Icon(Icons.copy_rounded, color: _RoomInfoColors.muted, size: 16),
                        ])),
                      ),
                      _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF7A2F), size: 18),
                        const SizedBox(width: 6),
                        Text(_format(info.likes), style: const TextStyle(color: Color(0xFFFF7A2F), fontSize: 13)),
                      ]), color: const Color(0xFF382A32)),
                    ]),
                  ])),
                  const Icon(Icons.error_outline, color: _RoomInfoColors.muted, size: 28),
                  ]),
                ),
                const SizedBox(height: 14),
                SizedBox(height: 52, child: Row(children: [
                  Expanded(flex: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: _RoomInfoColors.goldBg, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF4A3B1A))),
                    child: Row(children: [
                      _networkImage(info.tribeLogoUrl, 34, 34),
                      const SizedBox(width: 8),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(info.tribeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(info.tribeOwner, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xBFE8A92B), fontSize: 12)),
                      ])),
                    ]),
                  )),
                  const SizedBox(width: 7),
                  Expanded(flex: 3, child: _stat('Lv.${info.level}', 'مستوى الغرفة', _RoomInfoColors.levelBg, _RoomInfoColors.level)),
                  const SizedBox(width: 7),
                  Expanded(flex: 2, child: _stat('قصر', info.palaceStatus, _RoomInfoColors.goldBg, _RoomInfoColors.palace)),
                ])),
                const SizedBox(height: 16),
                Transform.translate(
                  offset: const Offset(0, -5),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Transform.translate(
                      offset: const Offset(2, 0),
                      child: const Text('أعضاء', style: TextStyle(color: _RoomInfoColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    GestureDetector(onTap: onMembersTap, child: Row(children: [
                      Text('${info.membersCount}/${info.membersMax}', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 14)),
                      const Icon(Icons.chevron_right, color: _RoomInfoColors.muted),
                    ])),
                  ]),
                ),
                const SizedBox(height: 10),
                Transform.translate(
                  offset: const Offset(0, -10),
                  child: SizedBox(height: 60, child: ListView.separated(
                  scrollDirection: Axis.horizontal, itemCount: info.members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final m = info.members[i];
                    final avatarUrl = (m.isOwner && info.ownerAvatarUrl.trim().isNotEmpty)
                        ? info.ownerAvatarUrl.trim()
                        : m.avatarUrl.trim();
                    return SizedBox(width: 44, child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                      ClipOval(
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: avatarUrl.startsWith('https://')
                              ? Image.network(
                                  avatarUrl,
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: _RoomInfoColors.chip,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.person, color: _RoomInfoColors.muted),
                                  ),
                                )
                              : Container(
                                  color: _RoomInfoColors.chip,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.person, color: _RoomInfoColors.muted),
                                ),
                        ),
                      ),
                      Positioned(bottom: 5, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: m.isOwner ? const Color(0xFFFF4F81) : const Color(0xFFFF9800), borderRadius: BorderRadius.circular(10)),
                        child: Text(m.role, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), 
                      )),
                    ]));
                  },
                )),
                ),
                const SizedBox(height: 15),
                const Text('الإعلان', style: TextStyle(color: _RoomInfoColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(info.announcement.isEmpty ? 'لا يوجد إعلان لهذه الغرفة حاليًا' : info.announcement, style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 13, height: 1.3)),
                const SizedBox(height: 15),
                const Text('مجموعة الغرفة', style: TextStyle(color: _RoomInfoColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 32, backgroundColor: _RoomInfoColors.chip, backgroundImage: info.imageUrl.startsWith('http') ? NetworkImage(info.imageUrl) : null, child: info.imageUrl.startsWith('http') ? null : const Icon(Icons.groups, color: _RoomInfoColors.muted)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(info.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.text, fontSize: 17, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      _chip(Text('${info.groupCount} عضو', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 12))),
                    ]),
                    const SizedBox(height: 4),
                    Text(info.groupDesc.isEmpty ? 'لا يوجد وصف للمجموعة' : info.groupDesc, style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 14, height: 1.4)),
                  ])),
                ]),
                const SizedBox(height: 12),
              ]),
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 10), child: Row(children: [
              if (info.isRoomOwner) ...[
                Expanded(child: _button('الإعدادات', const Color(0xFF353044), const Color(0xFFF2C66D), onSettings, icon: Icons.settings_outlined)),
                const SizedBox(width: 14),
                Expanded(child: _button('دعوة', const Color(0xFF30364A), const Color(0xFFE5E8F5), onInvite, icon: Icons.person_add_alt_1_rounded)),
              ] else ...[
                Expanded(child: _button('متابعة', const Color(0xFF5A2A18), _RoomInfoColors.follow, onFollow)),
                const SizedBox(width: 14),
                Expanded(child: _button('انضمام', const Color(0xFF1B5E63), _RoomInfoColors.join, onJoin)),
              ],
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _countryFlag(BuildContext context, String countryName) {
    final savedProfileFlag = countryFlagForProfileName(countryName);
    if (savedProfileFlag == 'SOUTH_ARABIA') {
      return SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: SquareCountryFlag('SOUTH_ARABIA', size: 22),
        ),
      );
    }
    if (savedProfileFlag.isNotEmpty) {
      return SizedBox(
        width: 22,
        height: 22,
        child: Center(child: SquareCountryFlag(savedProfileFlag, size: 22)),
      );
    }
    if (countryName.trim().isEmpty) return const SizedBox.shrink();
    for (final country in CountryService().getAll()) {
      final translated = country.getTranslatedName(context) ?? country.name;
      if (translated.trim() == countryName.trim() ||
          country.name.trim().toLowerCase() == countryName.trim().toLowerCase()) {
        return SizedBox(
          width: 22,
          height: 22,
          child: Center(child: SquareCountryFlag(country.flagEmoji, size: 22)),
        );
      }
    }
    // Backward compatibility for older room snapshots that carried ISO codes.
    final code = countryName.trim().toUpperCase();
    if (code.length == 2 &&
        code.codeUnits.every((unit) => unit >= 65 && unit <= 90)) {
      return SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: SquareCountryFlag(String.fromCharCodes(code.codeUnits.map((unit) => 0x1F1E6 + unit - 65)), size: 22),
        ),
      );
    }
    return const SizedBox.shrink();
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

  static Widget _button(String title, Color bg, Color fg, VoidCallback? action, {IconData? icon}) => SizedBox(
    height: 54,
    child: ElevatedButton(
      onPressed: action,
      style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 7)],
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  static String _format(int value) => value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
