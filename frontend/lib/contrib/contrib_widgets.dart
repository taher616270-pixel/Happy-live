import 'package:flutter/material.dart';
import 'contrib_assets.dart';

class ContribImage extends StatelessWidget {
  const ContribImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final value = source.trim();
    if (value.isEmpty) return fallback ?? _fallback();
    final uri = Uri.tryParse(value);
    final isNetwork = uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    if (isNetwork) {
      return Image.network(
        value,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback ?? _fallback(),
      );
    }
    return Image.asset(
      value,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback ?? _fallback(),
    );
  }

  Widget _fallback() => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: Colors.white38, size: 22),
        ),
      );
}

class ContribAvatar extends StatelessWidget {
  const ContribAvatar({
    super.key,
    required this.url,
    this.size = 48,
  });

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(.72), width: 1.2),
      ),
      child: ClipOval(
        child: ContribImage(
          source: url.isEmpty ? ContribAssets.avatarPlaceholder : url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fallback: Container(
            color: const Color(0xFF174B35),
            alignment: Alignment.center,
            child: const Icon(Icons.person_rounded,
                color: Colors.white70, size: 25),
          ),
        ),
      ),
    );
  }
}

class ContribCoin extends StatelessWidget {
  const ContribCoin({super.key, this.size = 17});
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = ContribAssets.coin;
    if (asset.isNotEmpty) {
      return ContribImage(source: asset, width: size, height: size);
    }
    return Icon(Icons.monetization_on_rounded,
        color: const Color(0xFFFFD76A), size: size);
  }
}

String contribFmt(int value) {
  final raw = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
    out.write(raw[i]);
  }
  return value < 0 ? '-${out.toString()}' : out.toString();
}
