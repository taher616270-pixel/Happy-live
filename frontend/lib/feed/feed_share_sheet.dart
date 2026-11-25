import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'feed_models.dart';
import 'feed_repository.dart';

Future<void> showFeedShare(
  BuildContext context,
  FeedRepository repo,
  FeedVideo video,
  VoidCallback onShared,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _ShareSheet(
          repo: repo,
          video: video,
          onShared: onShared,
          host: context,
        ),
      ),
    );

const _ink = Color(0xFF161823);

class _Target {
  final String label;
  final Widget icon;
  final Color bg;
  final Future<void> Function(String link) run;

  const _Target(this.label, this.icon, this.bg, this.run);
}

Future<void> _open(String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok) throw Exception('تعذر فتح التطبيق');
}

class _ShareSheet extends StatelessWidget {
  final FeedRepository repo;
  final FeedVideo video;
  final VoidCallback onShared;
  final BuildContext host;

  const _ShareSheet({
    required this.repo,
    required this.video,
    required this.onShared,
    required this.host,
  });

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(host)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = '${FeedConfig.shareBase}/v/${video.id}';
    const white = Colors.white;

    Future<void> done(Future<void> Function() action) async {
      Navigator.pop(context);
      try {
        await action();
        await repo.addShare(video.id);
        onShared();
      } catch (_) {
        _toast('تعذرت المشاركة');
      }
    }

    final apps = <_Target>[
      _Target(
        'إعادة النشر',
        const Icon(Icons.repeat_rounded, color: white, size: 30),
        const Color(0xFFFFC107),
        (link) async => _toast('تمت إعادة النشر'),
      ),
      _Target(
        'WhatsApp',
        const Icon(Icons.chat_rounded, color: white, size: 30),
        const Color(0xFF25D366),
        (link) => _open('https://wa.me/?text=${Uri.encodeComponent(link)}'),
      ),
      _Target(
        'نسخ الرابط',
        const Icon(Icons.link_rounded, color: white, size: 30),
        const Color(0xFF2F6BFF),
        (link) async {
          await Clipboard.setData(ClipboardData(text: link));
          _toast('تم نسخ الرابط');
        },
      ),
      _Target(
        'Snapchat',
        const Icon(Icons.chat_bubble_rounded, color: Colors.black, size: 28),
        const Color(0xFFFFFC00),
        (link) async => Share.share(link),
      ),
      _Target(
        'X',
        const Text(
          'X',
          style: TextStyle(
            color: white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        Colors.black,
        (link) => _open(
          'https://twitter.com/intent/tweet?text=${Uri.encodeComponent(link)}',
        ),
      ),
      _Target(
        'الرسائل القصيرة',
        const Icon(Icons.sms_rounded, color: white, size: 28),
        const Color(0xFF34C759),
        (link) => _open('sms:?body=${Uri.encodeComponent(link)}'),
      ),
      _Target(
        'البريد الإلكتروني',
        const Icon(Icons.mail_rounded, color: white, size: 28),
        const Color(0xFF29B6F6),
        (link) => _open('mailto:?body=${Uri.encodeComponent(link)}'),
      ),
      _Target(
        'Instagram',
        const Icon(Icons.camera_alt_rounded, color: white, size: 28),
        const Color(0xFFD62976),
        (link) async => Share.share(link),
      ),
      _Target(
        'Stories',
        const Icon(Icons.add_circle_outline_rounded, color: white, size: 30),
        const Color(0xFFFA7E1E),
        (link) async => Share.share(link),
      ),
      _Target(
        'المزيد',
        const Icon(Icons.more_horiz_rounded, color: white, size: 30),
        const Color(0xFF2F8BFF),
        (link) async => Share.share(link),
      ),
    ];

    final actions = <(String, IconData)>[
      ('إبلاغ', Icons.flag_rounded),
      ('غير مهتم', Icons.heart_broken_rounded),
      ('تنزيل', Icons.download_rounded),
      ('إضافة إلى قصة', Icons.add_circle_outline_rounded),
      ('الترويج', Icons.local_fire_department_rounded),
      ('دويتو', Icons.people_alt_rounded),
      ('الدمج', Icons.vertical_split_rounded),
      ('إنشاء مجموعة', Icons.group_add_rounded),
      ('مشاركة كـ GIF', Icons.gif_box_rounded),
    ];

    Widget circleItem(
      Widget child,
      Color background,
      String label,
      VoidCallback onTap,
    ) {
      return GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background,
                ),
                child: child,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Text(
                  'إرسال إلى',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _ink,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(
                      Icons.search_rounded,
                      color: _ink,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 108,
            child: FutureBuilder<List<FeedFriend>>(
              future: repo.friends(),
              builder: (_, snapshot) {
                final friends = snapshot.data ?? const <FeedFriend>[];
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: friends.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final friend = friends[index];
                    return GestureDetector(
                      onTap: () => done(() async {
                        await repo.sendToFriend(video.id, friend.id);
                        _toast('تم الإرسال إلى ${friend.name}');
                      }),
                      child: SizedBox(
                        width: 76,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 31,
                              backgroundColor: const Color(0xFFE6E6EA),
                              backgroundImage: friend.avatar.isNotEmpty
                                  ? NetworkImage(friend.avatar)
                                  : null,
                              child: friend.avatar.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      color: Color(0xFF8A8B91),
                                      size: 30,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              friend.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 12.5,
                              ),
                            ),
                            if (friend.streak > 0)
                              Text(
                                '${friend.streak}🔥',
                                style: const TextStyle(
                                  color: Color(0xFF8A8B91),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEDEF)),
          const SizedBox(height: 14),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, index) {
                final app = apps[index];
                return circleItem(
                  app.icon,
                  app.bg,
                  app.label,
                  () => done(() => app.run(link)),
                );
              },
            ),
          ),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: actions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, index) => circleItem(
                Icon(
                  actions[index].$2,
                  color: const Color(0xFF3A3A3C),
                  size: 28,
                ),
                const Color(0xFFEFEFF1),
                actions[index].$1,
                () {
                  Navigator.pop(context);
                  _toast('${actions[index].$1}: قريبا');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
