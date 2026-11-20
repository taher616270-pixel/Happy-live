import 'package:flutter/material.dart';
import 'package:gif_view/gif_view.dart';
import 'cannon_config.dart';

/// Displays the configured airplane artwork. No drawn cannon fallback is used.
class CannonArt extends StatelessWidget {
  final int level;
  final double size;
  final bool dim;
  final bool completed;

  const CannonArt({
    super.key,
    required this.level,
    this.size = 160,
    this.dim = false,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = CannonConfig.cannonImages[level];
    final localAnimatedAsset = level >= 1 && level <= 4
        ? 'assets/images/cannon/airplane_lv$level.gif'
        : null;

    final Widget art = localAnimatedAsset != null
        ? GifView.asset(
            localAnimatedAsset,
            width: size,
            height: size,
            frameRate: 30,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _empty(),
          )
        : (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _empty(),
              )
            : _empty();

    return Opacity(opacity: dim ? 0.4 : 1, child: art);
  }

  Widget _empty() => SizedBox(width: size, height: size);
}
