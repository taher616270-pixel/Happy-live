import 'package:flutter/material.dart';
import 'package:gif_view/gif_view.dart';

/// Network image renderer used throughout Happy Live.
/// GIF URLs use GifView so animation keeps playing on Flutter Web as well
/// as mobile, and always loops instead of stopping after one play.
class HappyNetworkImage extends StatelessWidget {
  const HappyNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  bool get _isGif {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase().split('?').first;
    return path.endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    if (_isGif) {
      return GifView.network(
        url,
        width: width,
        height: height,
        fit: fit,
        autoPlay: true,
        loop: true,
        errorBuilder: (context, error, tryAgain) =>
            errorBuilder?.call(context, error, null) ??
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: errorBuilder,
    );
  }
}

/// Circular profile image that preserves GIF animation (unlike
/// CircleAvatar.backgroundImage, which cannot host GifView's widget animation).
class HappyNetworkAvatar extends StatelessWidget {
  const HappyNetworkAvatar({
    super.key,
    required this.url,
    required this.size,
    this.backgroundColor = const Color(0xFFEFE7D7),
    this.fallback,
    this.border,
  });

  final String url;
  final double size;
  final Color backgroundColor;
  final Widget? fallback;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final valid = url.startsWith('https://') || url.startsWith('http://');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: valid
          ? HappyNetworkImage(url, width: size, height: size, fit: BoxFit.cover)
          : Center(child: fallback ?? const Icon(Icons.person_rounded)),
    );
  }
}
