import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'square_country_flag.dart';
import 'package:flutter/services.dart';
import '../pages/edit_profile_page.dart';
import 'package:country_picker/country_picker.dart';
import '../pages/room_upgrade_page.dart' show kLevels;

class RoomMember {
  const RoomMember({
    required this.avatarUrl,
    required this.role,
    this.isOwner = false,
    this.name = '',
    this.id = '',
    this.userId = '',
  });
  final String avatarUrl;
  final String role;
  final bool isOwner;
  final String name;
  final String id;
  final String userId;
}

class RoomInfo {
  const RoomInfo({
    required this.name, required this.flag, required this.id,
    required this.imageUrl, required this.imageBadge, required this.likes,
    required this.tribeName, required this.tribeOwner, required this.tribeLogoUrl,
    required this.level, this.experienceLevel = 1, required this.palaceStatus, required this.membersCount,
    required this.membersMax, required this.members, required this.announcement,
    required this.groupName, required this.groupCount, required this.groupDesc,
    this.isRoomOwner = false,
    this.ownerAvatarUrl = '',
  });
  final String name, flag, id, imageUrl, imageBadge, tribeName, tribeOwner, tribeLogoUrl;
  final int likes, level, experienceLevel, membersCount, membersMax, groupCount;
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
  static const goldBg = Color(0xFF2A251F);
  static const levelBg = Color(0xFF1B2725);
  static const level = Color(0xFF37A73C);
  static const palace = Color(0xFFDB8D15);
  static const tribeBg = Color(0xFF1C2D2A);
  static const tribeTitle = Color(0xFF39AF61);
  static const tribeSub = Color(0xFF2E6B45);
  static const levelSub = Color(0xFF2D6236);
  static const palaceSub = Color(0xFF9C6A1A);
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
  VoidCallback? onUpgrade,
  VoidCallback? onLevelTap,
  String? accessToken,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomInfoSheet(info: info, onJoin: onJoin, onFollow: onFollow, onMembersTap: onMembersTap, onSettings: onSettings, onInvite: onInvite, onUpgrade: onUpgrade, onLevelTap: onLevelTap, accessToken: accessToken ?? ''),
  );
}

void _showInactiveRoomGroupSheet(BuildContext context, RoomInfo info) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned.fill(
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: _RoomInfoColors.bg.withOpacity(.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(.12)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(.24), blurRadius: 22, offset: const Offset(0, 7)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_rounded, color: _RoomInfoColors.gold, size: 25),
                    SizedBox(width: 10),
                    Text(
                      'لم تنشط مجموعة الغرفة بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _RoomInfoColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

class _RoomInfoSheet extends StatelessWidget {
  const _RoomInfoSheet({required this.info, this.onJoin, this.onFollow, this.onMembersTap, this.onSettings, this.onInvite, this.onUpgrade, this.onLevelTap, required this.accessToken});
  final RoomInfo info;
  final VoidCallback? onJoin, onFollow, onMembersTap, onSettings, onInvite, onUpgrade, onLevelTap;
  final String accessToken;

  int get _selectedLevelIndex =>
      (info.level - 1).clamp(0, kLevels.length - 1).toInt();

  int get _membersLimitForLevel {
    for (final perk in kLevels[_selectedLevelIndex].perks) {
      if (perk.title.trim() == 'أعضاء الغرفة') {
        final match = RegExp(r'\d+').firstMatch(perk.desc);
        return match == null ? info.membersMax : int.parse(match.group(0)!);
      }
    }
    return info.membersMax;
  }

  @override
  Widget build(BuildContext context) {
    final selectedLevel = kLevels[_selectedLevelIndex];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .60 + 7),
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
                  SizedBox(width: 66, height: 70, child: Stack(children: [
                    Transform.translate(
                      offset: const Offset(2, 8),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _networkImage(info.imageUrl, 66, 66)),
                    ),

                  ])),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Transform.translate(
                      offset: const Offset(3, 7),
                      child: Row(children: [
                        _countryFlag(context, info.flag),
                        const SizedBox(width: 6),
                        Flexible(child: Transform.translate(offset: const Offset(0, 0), child: Text(info.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.text, fontSize: 20, fontWeight: FontWeight.w700)))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: info.id));
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الـ ID'), duration: Duration(seconds: 1)));
                        },
                        child: Transform.translate(
                          offset: const Offset(7, 6),
                          child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('ID:${info.id}', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 12)),
                            const SizedBox(width: 6), Transform.translate(offset: const Offset(3.5, 0), child: const Icon(Icons.copy_rounded, color: _RoomInfoColors.muted, size: 16)),
                          ]), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6), radius: 8),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(7, 6),
                        child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.favorite, color: Color(0xFFFF7A2F), size: 16),
                          const SizedBox(width: 6),
                          Text(_format(info.likes), style: const TextStyle(color: Color(0xFFFF7A2F), fontSize: 12)),
                        ]), color: const Color(0xFF382A32), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6), radius: 8),
                      ),
                    ]),
                  ])),
                  Transform.translate(
                    offset: const Offset(0, 7),
                    child: GestureDetector(
                      onTap: () => _showRoomReportSheet(context),
                      child: const Icon(Icons.error_outline, color: _RoomInfoColors.muted, size: 28),
                    ),
                  ),
                  ]),
                ),
                const SizedBox(height: 14),
                SizedBox(height: 52, child: Row(children: [
                  Expanded(flex: 6, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: _RoomInfoColors.tribeBg, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(info.tribeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.tribeTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(info.tribeOwner, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.tribeSub, fontSize: 12)),
                      ])),
                      const SizedBox(width: 8),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF4CEB7A), Color(0xFF2FB95A)]),
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        child: _networkImage(info.tribeLogoUrl, 34, 34),
                      ),
                    ]),
                  )),
                  const SizedBox(width: 7),
                  Expanded(flex: 3, child: GestureDetector(onTap: onLevelTap, behavior: HitTestBehavior.opaque, child: Transform.translate(offset: const Offset(-5, 0), child: Padding(padding: const EdgeInsets.only(left: 12), child: _stat('Lv.${info.experienceLevel}', 'مستوى الغرفة', _RoomInfoColors.levelBg, _RoomInfoColors.level, subColor: _RoomInfoColors.levelSub))))),
                  const SizedBox(width: 1),
                  Expanded(flex: 3, child: GestureDetector(onTap: onUpgrade, child: _stat(selectedLevel.name, 'فعّال', _RoomInfoColors.goldBg, _RoomInfoColors.palace, subColor: _RoomInfoColors.palaceSub))),
                ])),
                Transform.translate(
                  offset: const Offset(0, 6),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Transform.translate(
                      offset: const Offset(2, -1),
                      child: const Text('أعضاء', style: TextStyle(color: _RoomInfoColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    GestureDetector(onTap: () { onMembersTap?.call(); _showRoomMembersSheet(context); }, child: Row(children: [
                      Text('${info.membersCount}/$_membersLimitForLevel', style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 14)),
                      const Icon(Icons.chevron_right, color: _RoomInfoColors.muted),
                    ])),
                  ]),
                ),
                const SizedBox(height: 10),
                Transform.translate(
                  offset: const Offset(-8, 5),
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
                          width: 32,
                          height: 32,
                          child: avatarUrl.startsWith('http')
                              ? Image.network(
                                  avatarUrl,
                                  width: 32,
                                  height: 32,
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
                      Positioned(top: 23, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                        decoration: BoxDecoration(color: m.isOwner ? const Color(0xFFFF4F81) : const Color(0xFFFF9800), borderRadius: BorderRadius.circular(10)),
                        child: Text(m.role, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600)), 
                      )),
                    ]));
                  },
                )),
                ),
                const SizedBox(height: 15),
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -3),
                        child: const Text('الإعلان', style: TextStyle(color: _RoomInfoColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      Text(info.announcement.isEmpty ? 'لا يوجد إعلان لهذه الغرفة حاليًا' : info.announcement, style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 13, height: 1.3)),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: info.groupCount == 0
                        ? () => _showInactiveRoomGroupSheet(context, info)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('مجموعة الغرفة', style: TextStyle(color: _RoomInfoColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(radius: 20, backgroundColor: _RoomInfoColors.chip, backgroundImage: info.imageUrl.startsWith('http') ? NetworkImage(info.imageUrl) : null, child: info.imageUrl.startsWith('http') ? null : const Icon(Icons.groups, color: _RoomInfoColors.muted)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _RoomInfoColors.text, fontSize: 13, fontWeight: FontWeight.w600))),
                              const SizedBox(width: 6),
                              _chip(
                                Text(
                                  info.groupCount == 0 ? 'لم يتم التنشيط بعد' : '${info.groupCount} عضو',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 9),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                radius: 7,
                              ),
                            ]),
                            const SizedBox(height: 3),
                            Text(info.groupDesc.isEmpty ? 'لا يوجد وصف للمجموعة' : info.groupDesc, style: const TextStyle(color: _RoomInfoColors.muted, fontSize: 11, height: 1.25)),
                          ])),
                        ]),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
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

  Widget _levelPerksSection() {
    final levelIndex = (info.level - 1).clamp(0, kLevels.length - 1).toInt();
    final level = kLevels[levelIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: _RoomInfoColors.palace, size: 18),
            const SizedBox(width: 7),
            Text(
              'مميزات مستوى ${level.name}',
              style: const TextStyle(
                color: _RoomInfoColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (level.perks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _RoomInfoColors.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'مميزات هذا المستوى لم تُحدد بعد',
              style: TextStyle(color: _RoomInfoColors.muted, fontSize: 12),
            ),
          )
        else
          ...level.perks.map((perk) => Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: _RoomInfoColors.chip.withOpacity(.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(perk.icon, color: _RoomInfoColors.palace, size: 19),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            perk.title,
                            style: const TextStyle(
                              color: _RoomInfoColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            perk.desc,
                            style: const TextStyle(
                              color: _RoomInfoColors.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  void _showRoomMembersSheet(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق قائمة الأعضاء',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final searchController = TextEditingController();
        final searchFocus = FocusNode();
        var searching = false;
        var query = '';
        return StatefulBuilder(
          builder: (panelContext, setPanelState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filteredMembers = info.members.where((member) {
              if (normalizedQuery.isEmpty) return true;
              return member.name.toLowerCase().contains(normalizedQuery) ||
                  member.id.toLowerCase().contains(normalizedQuery);
            }).toList();
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: _RoomInfoColors.bg,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(panelContext).width,
                    height: double.infinity,
                    child: SafeArea(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 58,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Text(
                                  'أعضاء',
                                  style: TextStyle(
                                    color: _RoomInfoColors.text,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    onPressed: () => Navigator.of(dialogContext).pop(),
                                    icon: const Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        color: _RoomInfoColors.text,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: TextField(
                                      controller: searchController,
                                      focusNode: searchFocus,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        color: Color(0xFF202020),
                                        fontSize: 14,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText: 'ابحث عن اسم مستخدم أو المعرّف',
                                        hintStyle: TextStyle(
                                          color: Color(0xFF8A8A8A),
                                          fontSize: 13,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: Color(0xFF777777),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                                      ),
                                      onTap: () => setPanelState(() => searching = true),
                                      onChanged: (value) => setPanelState(() {
                                        searching = true;
                                        query = value;
                                      }),
                                    ),
                                  ),
                                ),
                                if (searching) ...[
                                  const SizedBox(width: 9),
                                  TextButton(
                                    onPressed: () {
                                      searchController.clear();
                                      searchFocus.unfocus();
                                      setPanelState(() {
                                        query = '';
                                        searching = false;
                                      });
                                    },
                                    child: const Text(
                                      'إلغاء',
                                      style: TextStyle(
                                        color: _RoomInfoColors.text,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Expanded(
                            child: filteredMembers.isEmpty
                                ? const Center(
                                    child: Text(
                                      'لا توجد نتائج',
                                      style: TextStyle(color: _RoomInfoColors.muted),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    itemCount: filteredMembers.length,
                                    separatorBuilder: (_, __) => const Divider(
                                      color: Color(0x332B3047),
                                      height: 1,
                                    ),
                                    itemBuilder: (_, index) {
                                      final member = filteredMembers[index];
                                      final avatar = member.avatarUrl.trim();
                                      final displayName = member.name.trim().isEmpty
                                          ? 'مستخدم'
                                          : member.name.trim();
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: _RoomInfoColors.chip,
                                              backgroundImage: avatar.startsWith('http')
                                                  ? NetworkImage(avatar)
                                                  : null,
                                              child: avatar.startsWith('http')
                                                  ? null
                                                  : const Icon(Icons.person, color: _RoomInfoColors.muted),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    displayName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: _RoomInfoColors.text,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (member.id.trim().isNotEmpty)
                                                    Text(
                                                      'ID: ${member.id}',
                                                      style: const TextStyle(
                                                        color: _RoomInfoColors.muted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              member.role,
                                              style: TextStyle(
                                                color: member.isOwner
                                                    ? const Color(0xFFFF4F81)
                                                    : const Color(0xFFFF9800),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  void _showRoomReportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF3E8D2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Transform.translate(
                  offset: const Offset(0, -16),
                  child: const Text(
                    'لماذا تريد التبليغ عن هذه الغرفة؟',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _RoomReportPage(targetName: info.name, roomCode: info.id, accessToken: accessToken),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF30291F),
                    ),
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: const Text(
                        'انتهاك صفحة الملف الشخصي للغرفة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF17120B),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFBDAE94)),
                SizedBox(
                  height: 46,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

  Widget _countryFlag(BuildContext context, String countryName) {
    final value = countryName.trim();
    if (value.isEmpty) return const SizedBox.shrink();

    // Resolve the saved profile name first. South Arabia must never be
    // interpreted as Yemen or another ISO country.
    final savedProfileFlag = countryFlagForProfileName(value);
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ').trim();
    if (savedProfileFlag == 'SOUTH_ARABIA' ||
        normalized == 'south arabia' ||
        normalized == 'الجنوب العربي' ||
        normalized == 'دولة الجنوب العربي') {
      return const SizedBox(
        width: 26,
        height: 26,
        child: Center(child: SquareCountryFlag('SOUTH_ARABIA', size: 26)),
      );
    }

    // Accept both ISO-2 values and the country names commonly returned by
    // older profile/API responses (Arabic and English).
    const aliases = <String, String>{
      'saudi arabia': 'SA', 'saudi': 'SA', 'ksa': 'SA',
      'السعودية': 'SA', 'المملكة العربية السعودية': 'SA',
      'yemen': 'YE', 'اليمن': 'YE',
      'kuwait': 'KW', 'الكويت': 'KW',
      'united arab emirates': 'AE', 'uae': 'AE',
      'الإمارات': 'AE', 'الامارات': 'AE', 'الإمارات العربية المتحدة': 'AE',
      'qatar': 'QA', 'قطر': 'QA',
      'morocco': 'MA', 'المغرب': 'MA',
      'egypt': 'EG', 'مصر': 'EG',
      'syria': 'SY', 'سوريا': 'SY',
      'turkey': 'TR', 'türkiye': 'TR', 'تركيا': 'TR',
      'algeria': 'DZ', 'الجزائر': 'DZ',
      'bahrain': 'BH', 'البحرين': 'BH',
      'iraq': 'IQ', 'العراق': 'IQ',
      'jordan': 'JO', 'الأردن': 'JO', 'الاردن': 'JO',
      'lebanon': 'LB', 'لبنان': 'LB',
      'oman': 'OM', 'عمان': 'OM', 'عُمان': 'OM',
      'pakistan': 'PK', 'باكستان': 'PK',
      'palestine': 'PS', 'فلسطين': 'PS',
      'sudan': 'SD', 'السودان': 'SD',
    };
    final code = aliases[normalized] ??
        (RegExp(r'^[a-z]{2}$').hasMatch(normalized) ? normalized.toUpperCase() : '');
    if (code.isNotEmpty) {
      return SizedBox(
        width: 26,
        height: 26,
        child: Center(child: SquareCountryFlag(code, size: 26)),
      );
    }

    // Fallback for localized names not covered by the saved profile list.
    for (final country in CountryService().getAll()) {
      final translated = country.getTranslatedName(context) ?? country.name;
      if (translated.trim().toLowerCase() == normalized ||
          country.name.trim().toLowerCase() == normalized) {
        return SizedBox(
          width: 26,
          height: 26,
          child: Center(child: SquareCountryFlag(country.flagEmoji, size: 26)),
        );
      }
    }

    return const SizedBox.shrink();
  }

  static Widget _networkImage(String url, double width, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: url.startsWith('http') ? Image.network(url, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imageFallback(width, height)) : _imageFallback(width, height),
  );

  static Widget _imageFallback(double width, double height) => Container(width: width, height: height, color: _RoomInfoColors.chip, alignment: Alignment.center, child: const Icon(Icons.image_outlined, color: _RoomInfoColors.muted));

  static Widget _chip(Widget child, {Color color = _RoomInfoColors.chip, EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8), double radius = 10}) => Container(
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
    child: child,
  );

  static Widget _stat(String title, String sub, Color bg, Color color, {Color? subColor}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.bold))),
      const SizedBox(height: 2),
      FittedBox(fit: BoxFit.scaleDown, child: Text(sub, style: TextStyle(color: subColor ?? color.withOpacity(.75), fontSize: 12))),
    ]),
  );

  static Widget _button(String title, Color bg, Color fg, VoidCallback? action, {IconData? icon}) => SizedBox(
    height: 46,
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


class _RoomReportPalette {
  static const teal = Color(0xFF1BBFA8);
  static const tealSoft = Color(0xFFC9F3EE);
  static const pink = Color(0xFFE8325F);
  static const grey = Color(0xFF8A8F99);
  static const line = Color(0xFFF0F1F4);
  static const buttonGrey = Color(0xFFEEF0F6);
}

class _RoomReportPage extends StatefulWidget {
  const _RoomReportPage({required this.targetName, required this.roomCode, required this.accessToken});
  final String targetName;
  final String roomCode;
  final String accessToken;

  @override
  State<_RoomReportPage> createState() => _RoomReportPageState();
}

class _RoomReportPageState extends State<_RoomReportPage> {
  static const _targets = ['اسم الغرفة', 'غلاف الغرفة', 'إعلان الغرفة'];
  static const _violations = [
    'اهانة',
    'مضايقة',
    'إباحية',
    'إعلانات / توجيه',
    'احتيال',
    'هكر',
    'الخصوصية والأمان',
    'عنف / مشاهد دموية / إرهاب',
    'انتهاكات سياسية / دينية',
    'انتحال الهوية',
    'اخرى',
  ];

  final Set<String> _selectedTargets = {};
  String? _violation = 'اهانة';
  bool _isSubmitting = false;

  bool get _canSubmit => _selectedTargets.isNotEmpty && _violation != null;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text(
            'إبلاغ',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.black, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _reportHeader(
                    'يُرجى تحديد نوع انتهاك صفحة الملف الشخصي المحدد',
                    withSubtitle: true,
                  ),
                  for (final target in _targets)
                    _RoomReportOptionRow(
                      label: target,
                      selected: _selectedTargets.contains(target),
                      selectedColor: const Color(0xFFD4AF37),
                      onTap: () => setState(() {
                        _selectedTargets.contains(target)
                            ? _selectedTargets.remove(target)
                            : _selectedTargets.add(target);
                      }),
                    ),
                  Container(height: 8, color: _RoomReportPalette.line),
                  _reportHeader('يُرجى تحديد الانتهاك'),
                  for (final violation in _violations)
                    _RoomReportOptionRow(
                      label: violation,
                      selected: _violation == violation,
                      selectedColor: const Color(0xFFD4AF37),
                      onTap: () => setState(() => _violation = violation),
                    ),
                ],
              ),
            ),
            _reportBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _reportHeader(String title, {bool withSubtitle = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                text: '*',
                style: TextStyle(color: _RoomReportPalette.pink),
              ),
              TextSpan(text: title),
            ]),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
          ),
          if (withSubtitle) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'ستقوم بالإبلاغ عن '),
                TextSpan(
                  text: "'${widget.targetName}'",
                  style: const TextStyle(
                    color: _RoomReportPalette.pink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'الغلاف والاسم والإعلان والمعلومات ذات الصلة كدليل',
              style: TextStyle(fontSize: 11, color: Colors.black),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportBottomButtons() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _RoomReportPillButton(
                text: 'إلغاء',
                background: _RoomReportPalette.buttonGrey,
                foreground: const Color(0xFF1C1C1E),
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RoomReportPillButton(
                text: _isSubmitting ? 'جارٍ الإرسال…' : 'تقدم طلب',
                background: _canSubmit
                    ? const Color(0xFFD4AF37)
                    : const Color(0xFFF5EACB),
                foreground: _canSubmit
                    ? Colors.white
                    : const Color(0xFFB49A5A),
                onTap: _canSubmit && !_isSubmitting ? _submitReport : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/reports/rooms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.accessToken}',
        },
        body: jsonEncode({
          'roomCode': widget.roomCode,
          'roomName': widget.targetName,
          'targets': _selectedTargets.toList(),
          'violation': _violation,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['message'] ?? 'تعذر إرسال البلاغ');
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إرسال البلاغ إلى إدارة Happy Live للمراجعة')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _RoomReportOptionRow extends StatelessWidget {
  const _RoomReportOptionRow({
    required this.label,
    required this.selected,
    this.selectedColor = _RoomReportPalette.teal,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _RoomReportPalette.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.black)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? selectedColor
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? selectedColor
                      : const Color(0xFFD5D8DE),
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomReportPillButton extends StatelessWidget {
  const _RoomReportPillButton({
    required this.text,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: background,
          shape: const StadiumBorder(),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
