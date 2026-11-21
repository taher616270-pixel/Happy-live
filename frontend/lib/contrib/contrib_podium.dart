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
      padding: const EdgeInsets.fromLTRB(3, 10, 3, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _TopContributor(entry: at(3), rank: 3)),
          const SizedBox(width: 1),
          Expanded(child: _TopContributor(entry: at(1), rank: 1)),
          const SizedBox(width: 1),
          Expanded(child: _TopContributor(entry: at(2), rank: 2)),
        ],
      ),
    );
  }
}

class _TopContributor extends StatelessWidget {
  const _TopContributor({required this.entry, required this.rank});

  final ContribEntry? entry;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final frame = ContribAssets.frames[rank - 1];
    final isFirst = rank == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Larger portrait-shaped podiums, with the winner visibly taller.
        final frameHeight = width * (isFirst ? 1.72 : 1.58);
        final avatarSize = width * (isFirst ? .43 : .405);
        final tiltY = rank == 3 ? .035 : rank == 2 ? -.035 : 0.0;

        final frameArtwork = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: frame.isNotEmpty
                  ? ContribImage(
                      source: frame,
                      width: width,
                      height: frameHeight,
                      fit: BoxFit.fill,
                      fallback: const SizedBox.shrink(),
                    )
                  : _FramePathPlaceholder(rank: rank),
            ),
            Positioned(
              top: frameHeight * .135,
              left: (width - avatarSize) / 2,
              child: ContribAvatar(
                url: entry?.avatarUrl ?? '',
                size: avatarSize,
              ),
            ),
            Positioned(
              top: frameHeight * .635,
              left: 5,
              right: 5,
              child: Text(
                entry?.name.isNotEmpty == true ? entry!.name : 'سيتم تحديده',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rank == 1
                      ? const Color(0xFFFFE59A)
                      : Colors.white.withOpacity(.92),
                  fontSize: isFirst ? 15 : 13,
                  fontWeight: FontWeight.w900,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 5, offset: Offset(0, 2)),
                    Shadow(color: Colors.white24, blurRadius: 1, offset: Offset(0, -1)),
                  ],
                ),
              ),
            ),
          ],
        );

        return Transform.translate(
          offset: Offset(0, isFirst ? 0 : 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: frameHeight,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateX(-0.055)
                    ..rotateY(tiltY)
                    ..scale(1.015, 1.015, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.48),
                          blurRadius: 15,
                          spreadRadius: 1,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: (rank == 1
                                  ? const Color(0xFFFFD36B)
                                  : rank == 2
                                      ? const Color(0xFF9DDFFF)
                                      : const Color(0xFFFFB68C))
                              .withOpacity(.24),
                          blurRadius: 13,
                          spreadRadius: -3,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          frameArtwork,
                          // Subtle glossy highlight gives the frame a raised, 3D finish.
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white.withOpacity(.17),
                                    Colors.white.withOpacity(.035),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, .24, .72],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                height: 4,
                margin: EdgeInsets.symmetric(horizontal: width * .07),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      rank == 1
                          ? const Color(0xFF8CFF69)
                          : const Color(0xFF3DAB58).withOpacity(.85),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF35C95B).withOpacity(.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$rank',
                style: TextStyle(
                  color: Colors.white.withOpacity(.28),
                  fontSize: isFirst ? 27 : 23,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 3)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FramePathPlaceholder extends StatelessWidget {
  const _FramePathPlaceholder({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = switch (rank) {
      1 => const [Color(0xFFFFF0BC), Color(0xFFD78B32), Color(0xFF713916)],
      2 => const [Color(0xFFF0FAFF), Color(0xFF83B9D8), Color(0xFF294E70)],
      _ => const [Color(0xFFFFE0C8), Color(0xFFC47B57), Color(0xFF633A2C)],
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(3, 5, 3, 4),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(54),
          bottom: Radius.circular(28),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xFFFFE7B5), width: 2.2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 7)),
          BoxShadow(color: Colors.white30, blurRadius: 5, offset: Offset(0, -2)),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(.28),
            border: Border.all(color: Colors.white.withOpacity(.38), width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 8, spreadRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}
