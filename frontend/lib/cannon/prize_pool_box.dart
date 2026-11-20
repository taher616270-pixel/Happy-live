import 'package:flutter/material.dart';

class PrizePoolItem {
  final String imageUrl;
  final String title;
  final bool isGold;
  final String? badgeText;

  const PrizePoolItem({
    required this.imageUrl,
    required this.title,
    this.isGold = false,
    this.badgeText,
  });
}

/// Reusable RTL prize-pool layout: one wide top prize and up to four
/// regular prizes arranged as one small top card and three bottom cards.
class PrizePoolBox extends StatelessWidget {
  final List<PrizePoolItem> items;

  const PrizePoolBox({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final visible = items.take(5).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PrizePoolHeader(),
          const SizedBox(height: 8),
          if (visible.length >= 2)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _PrizePoolCard(item: visible[0], wide: true),
                ),
                const SizedBox(width: 8),
                Expanded(child: _PrizePoolCard(item: visible[1])),
              ],
            )
          else
            _PrizePoolCard(item: visible.first, wide: true),
          if (visible.length > 2) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 2; i < visible.length; i++) ...[
                  if (i > 2) const SizedBox(width: 8),
                  Expanded(child: _PrizePoolCard(item: visible[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PrizePoolHeader extends StatelessWidget {
  const _PrizePoolHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _GreenPixels(),
        SizedBox(width: 9),
        _PrizePoolTab(),
        SizedBox(width: 9),
        _GreenPixels(),
      ],
    );
  }
}

class _GreenPixels extends StatelessWidget {
  const _GreenPixels();

  @override
  Widget build(BuildContext context) {
    const shades = [
      Color(0xFF8BFFC0),
      Color(0xFF27E987),
      Color(0xFF176E53),
      Color(0xFF42FF9B),
    ];
    return SizedBox(
      width: 23,
      height: 19,
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final shade in shades)
            Container(width: 7, height: 7, color: shade),
        ],
      ),
    );
  }
}

class _PrizePoolTab extends StatelessWidget {
  const _PrizePoolTab();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _PrizePoolTabClipper(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x99205BFF),
          border: Border.all(color: const Color(0xFF2F7BFF), width: 1),
        ),
        child: const Text(
          'حوض الجوائز',
          style: TextStyle(
            color: Color(0xFFDDF8FF),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PrizePoolTabClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - 15, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _PrizePoolCard extends StatelessWidget {
  final PrizePoolItem item;
  final bool wide;

  const _PrizePoolCard({required this.item, this.wide = false});

  Color get _edge => item.isGold
      ? const Color(0xFFD9A441)
      : const Color(0xFF2F7BFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: item.isGold
              ? const [Color(0xFF5A3A0C), Color(0xFF3A2508)]
              : const [Color(0xFF14338F), Color(0xFF0B1F6B)],
        ),
        border: Border.all(color: _edge, width: 1),
        boxShadow: [
          BoxShadow(
            color: _edge.withOpacity(0.20),
            blurRadius: 7,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: CustomPaint(
                painter: _PrizeScanlinePainter(
                  color: Colors.white.withOpacity(0.055),
                ),
              ),
            ),
          ),
          Positioned(right: -5, top: 39, child: _PrizeNotch(color: _edge)),
          Positioned(left: -5, top: 49, child: _PrizeNotch(color: _edge)),
          Padding(
            padding: const EdgeInsets.all(7),
            child: wide ? _wideContent() : _normalContent(),
          ),
        ],
      ),
    );
  }

  Widget _wideContent() {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: _PrizeImage(url: item.imageUrl, size: 54),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if ((item.badgeText ?? '').isNotEmpty)
                _GoldPrizeBadge(text: item.badgeText!),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFD77D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _normalContent() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: _PrizeImage(url: item.imageUrl, size: 48),
          ),
        ),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFD0DFFF),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PrizeImage extends StatelessWidget {
  final String url;
  final double size;

  const _PrizeImage({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return Icon(Icons.card_giftcard_rounded,
          size: size * 0.72, color: const Color(0xFF9FD0FF));
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF48CFFF),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Icon(
        Icons.card_giftcard_rounded,
        size: size * 0.72,
        color: const Color(0xFF9FD0FF),
      ),
    );
  }
}

class _GoldPrizeBadge extends StatelessWidget {
  final String text;

  const _GoldPrizeBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFFEBA3),
                Color(0xFFE7AE39),
                Color(0xFFD18B20),
              ],
            ),
            border: Border.all(color: const Color(0xFFFFD978), width: 0.8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF573609),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const Positioned(right: -3, child: _GoldBadgeNotch()),
        const Positioned(left: -3, child: _GoldBadgeNotch()),
      ],
    );
  }
}

class _GoldBadgeNotch extends StatelessWidget {
  const _GoldBadgeNotch();

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 9,
        decoration: BoxDecoration(
          color: const Color(0xFFE7AE39),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _PrizeNotch extends StatelessWidget {
  final Color color;

  const _PrizeNotch({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 25,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
      );
}

class _PrizeScanlinePainter extends CustomPainter {
  final Color color;

  const _PrizeScanlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    for (double y = 4; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PrizeScanlinePainter oldDelegate) =>
      oldDelegate.color != color;
}
