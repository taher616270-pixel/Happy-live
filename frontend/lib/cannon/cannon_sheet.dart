import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'cannon_art.dart';
import 'cannon_models.dart';
import 'cannon_rules_sheet.dart';
import 'cannon_reward_dialog.dart';
import 'cannon_service.dart';
import 'prize_pool_box.dart';

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

Future<void> showCannonSheet(BuildContext context, {required String roomId, VoidCallback? onSendGift}) {
  return showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => Directionality(textDirection: TextDirection.rtl, child: CannonSheet(roomId: roomId, onSendGift: onSendGift)),
  );
}

class CannonSheet extends StatefulWidget {
  final String roomId;
  final VoidCallback? onSendGift;
  const CannonSheet({super.key, required this.roomId, this.onSendGift});
  @override
  State<CannonSheet> createState() => _CannonSheetState();
}

class _CannonSheetState extends State<CannonSheet> {
  final CannonService _svc = CannonService.instance;
  late final PageController _pc;
  late int _page;
  final Set<String> _shownClaims = <String>{};
  int _syncedLevel = 0;

  @override
  void initState() {
    super.initState();
    _page = ((_svc.state?.level ?? 1) - 1).clamp(0, 149).toInt();
    _pc = PageController(initialPage: _page);
    _svc.refreshNow();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _showPendingClaim(CannonClaim claim) {
    if (_shownClaims.contains(claim.id)) return;
    _shownClaims.add(claim.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showCannonRewardDialog(context, claim);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.88,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A8A), Color(0xFF05053F), Color(0xFF030330)]),
      ),
      child: ListenableBuilder(
        listenable: _svc,
        builder: (context, _) {
          final st = _svc.state;
          if (st == null || st.levels.isEmpty) {
            return Center(
              child: _svc.isUnavailable
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('مدفع الغرفة متوقف مؤقتًا أو تعذر الاتصال بالخادم.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  )
                : const CircularProgressIndicator(color: Color(0xFF3AA8FF)),
            );
          }
          if (_syncedLevel != st.level) {
            _syncedLevel = st.level;
            final targetPage = (st.level - 1).clamp(0, st.levels.length - 1).toInt();
            if (targetPage != _page) {
              _page = targetPage;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _pc.hasClients) _pc.jumpToPage(targetPage);
              });
            }
          }
          if (st.pending.isNotEmpty) _showPendingClaim(st.pending.first);
          return _content(context, st);
        },
      ),
    );
  }

  Widget _content(BuildContext context, CannonState st) {
    final levels = st.levels;
    final pageIdx = _page.clamp(0, levels.length - 1).toInt();
    final lv = levels[pageIdx];
    final isCurrent = lv.level == st.level;
    final locked = lv.level > st.level;
    final done = lv.level < st.level;
    final ratio = isCurrent ? st.ratio : (done ? 1.0 : 0.0);
    final ordered = [...lv.prizes.where((p) => p.top1), ...lv.prizes.where((p) => !p.top1)];

    return LayoutBuilder(builder: (context, sheetConstraints) {
      // Match the FittedBox scale below so the floor's lower edge stays
      // exactly where the original 270px floor ended.
      final availableHeight = (sheetConstraints.maxHeight - 60).clamp(0.0, double.infinity);
      final contentScale = math.min(1.0, availableHeight / 680);
      final floorHeight = 60 + (270 * contentScale);

      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: floorHeight,
            child: Image.asset(
              'assets/images/cannon/cannon_floor_lights.gif',
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF071A52), Color(0xFF02091F)],
                  ),
                ),
              ),
            ),
          ),
          Column(children: [
      SizedBox(height: 60, child: Stack(children: [
        const Center(child: _Tab(title: 'مدفع الغرفة')),
        Align(alignment: Alignment.centerLeft, child: IconButton(
          onPressed: () => showCannonRulesSheet(context),
          icon: Container(width: 28, height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3AA8FF), width: 1.6)),
            child: const Icon(Icons.question_mark_rounded, size: 17, color: Color(0xFF3AA8FF)),
          ),
        )),
        Align(alignment: Alignment.centerRight, child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_right, color: Color(0xFF3AA8FF), size: 30),
        )),
      ])),
      Expanded(child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: 680,
            child: Column(children: [
          SizedBox(height: 270, child: Column(children: [
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0x33205BFF), border: Border.all(color: const Color(0xFF3AA8FF), width: 1.2)),
                  child: Text('LV${lv.level}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF6FE7FF), fontSize: 16, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
                ),
                Expanded(child: PageView.builder(
                  controller: _pc, itemCount: levels.length,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    if (levels[i].level < st.level) _svc.loadContributorsForLevel(levels[i].level);
                  },
                  itemBuilder: (_, i) => _CannonVisual(level: levels[i], dim: levels[i].level > st.level, completed: levels[i].level < st.level),
                )),
                Transform.translate(
                  offset: const Offset(0, 34),
                  child: done
                    ? Transform.translate(
                        offset: const Offset(0, 3),
                        child: const Text(
                          'اكتمل',
                        style: TextStyle(
                          color: Color(0xFFDDF7FF),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const _Bolt(size: 22), const SizedBox(width: 8),
                        Text(_fmt(lv.need), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFF1FD27A), borderRadius: BorderRadius.circular(6)),
                          child: const Text('يحتاج', style: TextStyle(color: Color(0xFF05301C), fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                ),
                const SizedBox(height: 14),
              ])),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
            Transform.translate(offset: const Offset(0, 27), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
              value: ratio, minHeight: 5, backgroundColor: const Color(0xFF1A2A7A),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2BE3A0)),
            )),),
            const SizedBox(height: 8),
            Transform.translate(offset: const Offset(0, 23), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const Text('مساهمتك', style: TextStyle(color: Color(0xFF9AA6D8), fontSize: 12)),
                const SizedBox(width: 4), const _Bolt(size: 13), const SizedBox(width: 3),
                Text(isCurrent ? _fmt(st.myContribution) : '0', style: const TextStyle(color: Color(0xFF9AA6D8), fontSize: 12)),
              ]),
              const Row(children: [
                Text('1', style: TextStyle(color: Color(0xFFFFD66B), fontSize: 12)),
                SizedBox(width: 3), Text('🪙', style: TextStyle(fontSize: 12)),
                Text(' = 1 ', style: TextStyle(color: Color(0xFFFFD66B), fontSize: 12)),
                _Bolt(size: 13),
              ]),
            ]),),
          ])),
          const SizedBox(height: 16),
          Transform.translate(offset: const Offset(0, 10), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Opacity(
            opacity: (isCurrent || done) ? 1 : 0.4,
            child: GestureDetector(
              onTap: isCurrent ? () {
                Navigator.pop(context);
                widget.onSendGift?.call();
              } : null,
              child: Container(
                height: 62, width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFF39B6FF), Color(0xFF1458E8)]),
                  border: Border.all(color: const Color(0xFF9FE0FF), width: 1.4),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (done)
                    const Text('تم الإنجاز',
                      style: TextStyle(color: Color(0xFFD6D6D6), fontSize: 17, fontWeight: FontWeight.w800))
                  else ...[
                    Text(locked ? 'مقفل' : 'إرسال هدية',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    const Text('أرسل أي هدية وشارك في اليانصيب', style: TextStyle(color: Color(0xFFFFE9A8), fontSize: 11)),
                  ],
                ]),
              ),
            ),
          ))),
          const SizedBox(height: 18),
          if (done) ...[
            const _ContributionRankingTab(),
            const SizedBox(height: 8),
            _TopThreeContributors(contributors: _svc.contributors),
          ] else
            Opacity(
              opacity: locked ? 0.45 : 1,
              child: PrizePoolBox(
                items: [
                  for (final prize in ordered.take(5))
                    PrizePoolItem(
                      imageUrl: prize.icon,
                      title: prize.name,
                      isGold: prize.top1,
                      badgeText: prize.top1 ? 'Top1 only' : null,
                    ),
                ],
              ),
            ),
            ]),
          ),
        ),
      )),
          ]),
        ],
      );
    });
  }
}

class _CannonVisual extends StatelessWidget {
  final CannonLevel level;
  final bool dim;
  final bool completed;
  const _CannonVisual({required this.level, required this.dim, this.completed = false});

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
    // The animated floor is supplied by the parent Stack. Keep only the cannon here
    // so changing levels moves the cannon without moving the fixed requirement label.
    Positioned(bottom: 30, child: CannonArt(level: level.level, size: 210, dim: dim, completed: completed)),
  ]);
}

class _ContributionRankingTab extends StatelessWidget {
  const _ContributionRankingTab();

  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x33205BFF),
      border: const Border(bottom: BorderSide(color: Color(0xFF3AA8FF), width: 1.2)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text('ترتيب المساهمة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
  );
}

class _TopThreeContributors extends StatelessWidget {
  final List<CannonContributor> contributors;
  const _TopThreeContributors({required this.contributors});

  @override
  Widget build(BuildContext context) {
    CannonContributor? rank(int index) => contributors.length > index ? contributors[index] : null;
    return SizedBox(
      height: 142,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _ContributorCard(rank: 3, contributor: rank(2))),
          const SizedBox(width: 5),
          Expanded(child: _ContributorCard(rank: 1, contributor: rank(0), gold: true)),
          const SizedBox(width: 5),
          Expanded(child: _ContributorCard(rank: 2, contributor: rank(1))),
        ],
      ),
    );
  }
}

class _ContributorCard extends StatelessWidget {
  final int rank;
  final CannonContributor? contributor;
  final bool gold;
  const _ContributorCard({required this.rank, required this.contributor, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final border = gold ? const Color(0xFFFFC94A) : const Color(0xFF368CFF);
    final textColor = gold ? const Color(0xFFFFD66B) : const Color(0xFF55E9FF);
    return Container(
      height: gold ? 140 : 132,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: gold
            ? const [Color(0xFF4A3410), Color(0xFF2A1C08)]
            : const [Color(0xFF102C79), Color(0xFF0A1A58)],
        ),
        border: Border.all(color: border, width: gold ? 1.5 : 1.1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('TOP$rank', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w900)),
          CircleAvatar(
            radius: 19,
            backgroundColor: const Color(0xFF33436D),
            backgroundImage: contributor != null && contributor!.avatarUrl.startsWith('http')
              ? NetworkImage(contributor!.avatarUrl) : null,
            child: contributor == null || !contributor!.avatarUrl.startsWith('http')
              ? const Icon(Icons.person, color: Colors.white54, size: 22) : null,
          ),
          Text(
            contributor?.userName ?? 'مقعد فارغ',
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(color: gold ? const Color(0xFFFFE5A0) : Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bolt, color: Color(0xFF2BE3A0), size: 13),
              Flexible(child: Text(
                contributor == null ? '—' : _fmt(contributor!.contribution),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF2BE3A0), fontSize: 10, fontWeight: FontWeight.w800),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String title;
  const _Tab({required this.title});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0x331E56FF),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      border: const Border(bottom: BorderSide(color: Color(0xFF3AA8FF), width: 1.6)),
    ),
    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
  );
}

class _PrizePoolTab extends StatelessWidget {
  const _PrizePoolTab();

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _PrizePoolTrapezoidClipper(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 43, vertical: 10.5),
      decoration: const BoxDecoration(
        color: Color(0x33205BFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3AA8FF), width: 1.6),
        ),
      ),
      child: const Text('حوض الجوائز', style: TextStyle(
        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800,
      )),
    ),
  );
}

class _PrizePoolTrapezoidClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * 0.12, 0)
    ..lineTo(size.width * 0.88, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _Bolt extends StatelessWidget {
  final double size;
  const _Bolt({required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: const BoxDecoration(color: Color(0xFF1FD27A), shape: BoxShape.circle),
    child: Icon(Icons.bolt, size: size * 0.75, color: Colors.white),
  );
}

class _PrizeCard extends StatelessWidget {
  final CannonPrize prize;
  final bool wide;
  const _PrizeCard({required this.prize, this.wide = false});

  Widget _icon() => prize.icon.isNotEmpty
    ? Image.network(prize.icon, height: wide ? 64 : 46, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback())
    : _fallback();

  Widget _fallback() {
    final big = wide ? 58.0 : 40.0;
    if (prize.type == 'coins') {
      return Container(
        width: big * 0.8, height: big * 0.8,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFE0A020)])),
        child: Icon(Icons.star_rounded, color: Colors.white, size: big * 0.5),
      );
    }
    return Icon(prize.top1 ? Icons.workspace_premium_rounded : Icons.card_giftcard_rounded,
      size: big, color: prize.top1 ? const Color(0xFFFFD66B) : const Color(0xFF9FD0FF));
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 95, padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: wide ? const [Color(0xFF4A3410), Color(0xFF2A1C08)] : const [Color(0xFF0E2A8C), Color(0xFF0A1A5E)]),
      border: Border.all(color: wide ? const Color(0xFFB8862B) : const Color(0xFF2D6BFF), width: 1.3),
    ),
    child: wide ? Row(children: [
      Expanded(child: _icon()),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: const LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFD9962A)])),
          child: const Text('Top1 only', style: TextStyle(color: Color(0xFF5A3A08), fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        Text(prize.name, style: const TextStyle(color: Color(0xFFFFD66B), fontSize: 13)),
      ])),
    ]) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Expanded(child: Center(child: _icon())),
      Text(prize.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB9C6FF), fontSize: 12)),
    ]),
  );
}
