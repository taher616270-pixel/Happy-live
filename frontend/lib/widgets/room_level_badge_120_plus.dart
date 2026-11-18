import 'package:flutter/widgets.dart';

/// شارة مستوى الغرفة المتحركة لمستويات 120 فما فوق فقط.
/// الأساسي: GIF — الاحتياطي (يعمل فعليًا عند فشل تحميل/فك GIF): Animated WebP.
class RoomLevelBadge120Plus extends StatelessWidget {
  const RoomLevelBadge120Plus({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  static const String gifPath = 'assets/images/room_level_120_plus.gif';
  static const String webpPath = 'assets/images/room_level_120_plus.webp';

  /// استخدمها لتقرر هل تعرض هذه الشارة.
  static bool appliesTo(int roomLevel) => roomLevel >= 120;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// ويدجت اختياري إذا فشل GIF وWebP معًا (مثلاً صورة المستوى القديمة).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      gifPath,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      // GIF فشل -> نحمّل WebP المتحرك فعليًا
      errorBuilder: (context, error, stack) => Image.asset(
        webpPath,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stack) =>
            fallback ?? SizedBox(width: width, height: height),
      ),
    );
  }
}
