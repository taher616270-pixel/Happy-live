import 'package:flutter/material.dart';
import 'cannon_api.dart';
import 'cannon_models.dart';

Future<void> showCannonLuckSheet(
  BuildContext context, {
  required String roomId,
  required int level,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _CannonLuckSheet(roomId: roomId, level: level),
    ),
  );
}

class _CannonLuckSheet extends StatefulWidget {
  final String roomId;
  final int level;
  const _CannonLuckSheet({required this.roomId, required this.level});

  @override
  State<_CannonLuckSheet> createState() => _CannonLuckSheetState();
}

class _CannonLuckSheetState extends State<_CannonLuckSheet> {
  late Future<List<CannonWinner>?> _future;

  @override
  void initState() {
    super.initState();
    _future = CannonApi.fetchWinners(widget.roomId, widget.level);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Container(
      height: height * 0.88,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A8A), Color(0xFF05053F), Color(0xFF030330)],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Stack(
              children: [
                const Center(
                  child: Text(
                    'ترتيب الحظ',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.chevron_right, color: Color(0xFFD6D6D6), size: 30),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            color: const Color(0x553AA8FF),
          ),
          Expanded(
            child: FutureBuilder<List<CannonWinner>?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF3AA8FF)));
                }
                if (snapshot.data == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تعذر تحميل ترتيب الحظ', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => setState(() {
                            _future = CannonApi.fetchWinners(widget.roomId, widget.level);
                          }),
                          child: const Text('إعادة المحاولة', style: TextStyle(color: Color(0xFF9EDFFF))),
                        ),
                      ],
                    ),
                  );
                }
                final winners = snapshot.data!;
                if (winners.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا توجد جوائز مستلمة لهذا المستوى حتى الآن',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFD6D6D6), fontSize: 14),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: winners.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) => _WinnerTile(winner: winners[index], rank: index + 1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerTile extends StatelessWidget {
  final CannonWinner winner;
  final int rank;
  const _WinnerTile({required this.winner, required this.rank});

  @override
  Widget build(BuildContext context) {
    final avatar = winner.avatarUrl;
    final prize = winner.prizeIcon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xFF102C79), Color(0xFF09194E)],
        ),
        border: Border.all(color: const Color(0x553AA8FF), width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank', textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFF33436D),
            backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null,
            child: avatar.startsWith('http') ? null : const Icon(Icons.person, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(winner.userName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(winner.rewardName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFFD66B), fontSize: 11, fontWeight: FontWeight.w600)),
                if (winner.rewardType == 'coins')
                  Text('${winner.rewardValue} عملة',
                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: prize.startsWith('http')
              ? Image.network(prize, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFFD66B), size: 34))
              : const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFFD66B), size: 34),
          ),
        ],
      ),
    );
  }
}
