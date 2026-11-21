import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cannon/cannon_art.dart';
import '../cannon/cannon_sheet.dart';
import 'kick_log_sheet.dart';
import 'room_tools_api.dart';
import 'room_tools_controller.dart';
import 'room_tools_models.dart';

class RoomToolsAssets {
  static const Map<String, String> icons = {};
}

Future<void> showRoomToolsSheet(BuildContext context, RoomToolsController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Directionality(
      textDirection: TextDirection.rtl,
      child: _RoomToolsSheet(controller: controller, host: context),
    ),
  );
}

class _RoomToolsSheet extends StatelessWidget {
  final RoomToolsController controller;
  final BuildContext host;
  const _RoomToolsSheet({required this.controller, required this.host});

  void _soon(String name) {
    ScaffoldMessenger.maybeOf(host)?.showSnackBar(
      SnackBar(content: Text('$name: لم يتم ربط خدمته بعد'), duration: const Duration(seconds: 2)),
    );
  }

  void _run(BuildContext sheetCtx, ToolCb? cb, String name) {
    Navigator.of(sheetCtx).pop();
    Future.microtask(() {
      if (cb != null) {
        cb(host);
      } else {
        _soon(name);
      }
    });
  }

  Widget _w(IconData icon) => Icon(icon, color: Colors.white, size: 26);

  List<RoomTool> _tools(BuildContext sheetCtx) {
    final actions = controller.actions;
    final c = controller;
    RoomTool tool(String id, String label, ToolSection section, Widget icon, VoidCallback onTap) =>
        RoomTool(id: id, label: label, section: section, icon: icon, onTap: onTap);
    RoomTool simple(String id, String label, ToolSection section, Widget icon, ToolCb? callback) =>
        tool(id, label, section, icon, () => _run(sheetCtx, callback, label));

    const interactive = ToolSection.interactive;
    const admin = ToolSection.admin;
    const other = ToolSection.other;
    const more = ToolSection.more;

    return [
      simple('counter', 'عداد', interactive, const Icon(Icons.shield_rounded, color: Color(0xFFFFA726), size: 30), actions.counter),
      simple('pk', 'PK', interactive, const _PkIcon(), actions.pk),
      tool('salute', 'تحية', interactive, const CannonArt(level: 1, size: 36), () {
        Navigator.of(sheetCtx).pop();
        Future.microtask(() {
          if (actions.salute != null) {
            actions.salute!(host);
          } else {
            showCannonSheet(host, roomId: c.roomId, onSendGift: actions.onOpenGifts);
          }
        });
      }),
      simple('redEnvelope', 'ظرف أحمر', interactive, const _RedEnvelopeIcon(), actions.redEnvelope),
      simple('games', 'مركز الألعاب', interactive, const Icon(Icons.sports_esports_rounded, color: Color(0xFF9B7BFF), size: 30), actions.games),
      simple('lucky', 'يانصيب الحظ', interactive, const _LuckyIcon(), actions.lucky),

      if (c.role.canManage) ...[
        tool('clearChat', 'مسح الكتابة', admin, _w(Icons.cleaning_services_rounded), () => _confirmClear(sheetCtx)),
        simple('settings', 'إعدادات', admin, _w(Icons.tune_rounded), actions.settings),
        simple('music', 'موسيقى', admin, _w(Icons.music_note_rounded), actions.music),
        simple('soundEffect', 'مؤثر صوتي', admin, _w(Icons.graphic_eq_rounded), actions.soundEffect),
        tool('lock', c.loadingLock ? 'جارٍ التحميل' : (c.locked ? 'فتح الغرفة' : 'قفل الغرفة'), admin,
            _w(c.loadingLock ? Icons.hourglass_top_rounded : (c.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded)), () async {
          if (c.loadingLock) return;
          final ok = await c.toggleLock();
          if (!host.mounted) return;
          ScaffoldMessenger.maybeOf(host)?.showSnackBar(SnackBar(
            duration: const Duration(seconds: 1),
            content: Text(ok ? (c.locked ? 'تم قفل الغرفة' : 'تم فتح الغرفة') : 'تعذر تنفيذ الأمر'),
          ));
        }),
        simple('micMode', 'وضع الميكروفون', admin, _w(Icons.event_seat_rounded), actions.micMode),
        simple('background', 'خلفية', admin, _w(Icons.image_outlined), actions.background),
        tool('kickLog', 'سجل الطرد', admin, _w(Icons.person_remove_alt_1_rounded), () {
          Navigator.of(sheetCtx).pop();
          Future.microtask(() => showKickLogSheet(host, c.roomId));
        }),
      ],

      simple('visualEffect', 'مؤثر بصري', other, _w(Icons.auto_awesome_outlined), actions.visualEffect),
      tool('share', 'مشاركة', other,
          Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: _w(Icons.reply_rounded)),
          () async {
        final link = '${RoomToolsConfig.shareBase}/room/${c.roomId}';
        await Clipboard.setData(ClipboardData(text: link));
        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        ScaffoldMessenger.maybeOf(host)?.showSnackBar(
          const SnackBar(content: Text('تم نسخ رابط الغرفة'), duration: Duration(seconds: 1)),
        );
      }),
      tool('mic', c.micOpen ? 'المايك مفتوح' : 'المايك مغلق', other,
          _w(c.micOpen ? Icons.volume_up_rounded : Icons.volume_off_rounded), c.toggleMic),

      simple('store', 'متجر', more, _w(Icons.storefront_outlined), actions.store),
      simple('activity', 'نشاط', more, _w(Icons.flag_outlined), actions.activity),
    ];
  }

  void _confirmClear(BuildContext sheetCtx) {
    showDialog<void>(
      context: sheetCtx,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF2B1160),
          title: const Text('مسح الكتابة', style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text('هل تريد مسح رسائل الدردشة؟', style: TextStyle(color: Color(0xFFB9A9DC))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _run(sheetCtx, controller.actions.clearChat, 'مسح الكتابة');
              },
              child: const Text('مسح', style: TextStyle(color: Color(0xFFFF6B6B))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Container(
      height: height * .72,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B0A5E), Color(0xFF1E0E5A), Color(0xFF1B2272)],
        ),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final tools = _tools(context);
          const titles = {
            ToolSection.interactive: 'الميزات التفاعلية',
            ToolSection.admin: 'أداة إدارة',
            ToolSection.other: 'أداة أخرى',
            ToolSection.more: 'آخرون',
          };
          return LayoutBuilder(builder: (context, box) {
            final columnWidth = (box.maxWidth - 16) / 4;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.paddingOf(context).bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final section in ToolSection.values)
                    if (tools.any((item) => item.section == section)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 26, 12, 14),
                        child: Text(titles[section]!,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      Wrap(
                        runSpacing: 14,
                        children: [
                          for (final item in tools.where((item) => item.section == section))
                            _Tile(tool: item, width: columnWidth),
                        ],
                      ),
                    ],
                ],
              ),
            );
          });
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final RoomTool tool;
  final double width;
  const _Tile({required this.tool, required this.width});

  @override
  Widget build(BuildContext context) {
    final pillWidth = width * .62;
    final url = RoomToolsAssets.icons[tool.id];
    final icon = url != null && url.isNotEmpty
        ? Image.network(url, width: 34, height: 34, fit: BoxFit.contain, errorBuilder: (_, __, ___) => tool.icon)
        : tool.icon;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tool.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: pillWidth,
              height: pillWidth * .69,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(pillWidth),
              ),
              child: icon,
            ),
            const SizedBox(height: 8),
            Text(tool.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB9A9DC), fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _PkIcon extends StatelessWidget {
  const _PkIcon();
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (rect) => const LinearGradient(colors: [Color(0xFFFF4FD8), Color(0xFF4FA3FF)]).createShader(rect),
    child: const Text('PK', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
  );
}

class _RedEnvelopeIcon extends StatelessWidget {
  const _RedEnvelopeIcon();
  @override
  Widget build(BuildContext context) => Container(
    width: 22, height: 30, alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF5252), Color(0xFFD32F2F)]),
    ),
    child: Container(
      width: 10, height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFD54F), border: Border.all(color: const Color(0xFFFFB300))),
    ),
  );
}

class _LuckyIcon extends StatelessWidget {
  const _LuckyIcon();
  @override
  Widget build(BuildContext context) => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFB57CFF), width: 2), color: const Color(0x33B57CFF)),
    child: const Icon(Icons.apps_rounded, color: Colors.white, size: 22),
  );
}
