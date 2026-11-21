import 'package:flutter/material.dart';
import 'contrib_assets.dart';
import 'contrib_models.dart';
import 'contrib_widgets.dart';

class ContribPodium extends StatelessWidget {
  const ContribPodium({super.key, required this.top});
  final List<ContribEntry> top;

  @override
  Widget build(BuildContext context) {
    ContribEntry? at(int rank) => top.length >= rank ? top[rank - 1] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 17, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: _TopContributor(entry: at(3), rank: 3, size: 78)),
          const SizedBox(width: 3),
          Expanded(child: _TopContributor(entry: at(1), rank: 1, size: 96)),
          const SizedBox(width: 3),
          Expanded(child: _TopContributor(entry: at(2), rank: 2, size: 78)),
        ],
      ),
    );
  }
}

class _TopContributor extends StatelessWidget {
  const _TopContributor({
    required this.entry,
    required this.rank,
    required this.size,
  });

  final ContribEntry? entry;
  final int rank;
  final double size;

  static const _gold = [Color(0xFFFFE7A0), Color(0xFFD79A36), Color(0xFF81501C)];
  static const _silver = [Color(0xFFE9F0F2), Color(0xFF9CB5BD), Color(0xFF506B73)];
  static const _bronze = [Color(0xFFF2C6A8), Color(0xFFC47C55), Color(0xFF70402F)];

  @override
  Widget build(BuildContext context) {
    final colors = rank == 1 ? _gold : rank == 2 ? _silver : _bronze;
    final shield = rank <= ContribAssets.shields.length
        ? ContribAssets.shields[rank - 1]
        : '';
    final frame = rank <= ContribAssets.frames.length
        ? ContribAssets.frames[rank - 1]
        : '';
    final badge = rank <= ContribAssets.badges.length
        ? ContribAssets.badges[rank - 1]
        : '';
    final avatarSize = size * .57;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: size + 30,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              if (rank == 1)
                const Positioned(
                  top: -8,
                  child: Text('👑', style: TextStyle(fontSize: 24)),
                ),
              Positioned(
                top: rank == 1 ? 20 : 4,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (shield.isNotEmpty)
                        ContribImage(source: shield, width: size, height: size),
                      if (shield.isEmpty)
                        ClipPath(
                          clipper: _ContribShieldClipper(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: colors,
                              ),
                            ),
                            child: SizedBox(width: size, height: size),
                          ),
                        ),
                      ContribAvatar(
                        url: entry?.avatarUrl ?? '',
                        size: avatarSize,
                      ),
                      if (frame.isNotEmpty)
                        ContribImage(source: frame, width: size, height: size),
                      if (badge.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          child: ContribImage(
                            source: badge,
                            width: size * .48,
                            height: size * .30,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          entry?.name.isNotEmpty == true ? entry!.name : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: rank == 1 ? 13 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ContribCoin(size: 14),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                contribFmt(entry?.amount ?? 0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFE4A1),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '$rank',
          style: TextStyle(
            color: rank == 1 ? const Color(0xFFFFE5A0) : Colors.white70,
            fontSize: rank == 1 ? 17 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ContribShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * .5, 0)
      ..lineTo(size.width * .94, size.height * .16)
      ..lineTo(size.width * .88, size.height * .68)
      ..lineTo(size.width * .5, size.height)
      ..lineTo(size.width * .12, size.height * .68)
      ..lineTo(size.width * .06, size.height * .16)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
