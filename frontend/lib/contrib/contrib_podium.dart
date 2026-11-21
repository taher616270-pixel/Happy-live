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
      padding: const EdgeInsets.fromLTRB(5, 12, 5, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _TopContributor(entry: at(3), rank: 3)),
          const SizedBox(width: 2),
          Expanded(child: _TopContributor(entry: at(1), rank: 1)),
          const SizedBox(width: 2),
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
        final frameHeight = width * (isFirst ? 1.43 : 1.34);
        final avatarSize = width * (isFirst ? .39 : .37);

        return Transform.translate(
          offset: Offset(0, isFirst ? 0 : 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: frameHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (frame.isNotEmpty)
                      Positioned.fill(
                        child: ContribImage(
                          source: frame,
                          width: width,
                          height: frameHeight,
                          fit: BoxFit.fill,
                          fallback: const SizedBox.shrink(),
                        ),
                      ),
                    if (frame.isEmpty)
                      Positioned.fill(
                        child: _FramePathPlaceholder(rank: rank),
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
                      left: 7,
                      right: 7,
                      child: Text(
                        entry?.name.isNotEmpty == true ? entry!.name : 'سيتم تحديده',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: rank == 1
                              ? const Color(0xFFFFE59A)
                              : Colors.white.withOpacity(.88),
                          fontSize: isFirst ? 14 : 12,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(color: Colors.black26, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 3,
                margin: EdgeInsets.symmetric(horizontal: width * .08),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      rank == 1
                          ? const Color(0xFF69D75D)
                          : const Color(0xFF287C45).withOpacity(.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$rank',
                style: TextStyle(
                  color: Colors.white.withOpacity(.24),
                  fontSize: isFirst ? 25 : 21,
                  fontWeight: FontWeight.w900,
                  height: 1,
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
      1 => const [Color(0xFFFFE6A1), Color(0xFFB96A22), Color(0xFF6E3518)],
      2 => const [Color(0xFFE7F5FF), Color(0xFF6D9DBB), Color(0xFF31536D)],
      _ => const [Color(0xFFFFD7B8), Color(0xFFB66B4B), Color(0xFF633A2C)],
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 5),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(48),
          bottom: Radius.circular(24),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xFFFFE7B5), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
    );
  }
}
