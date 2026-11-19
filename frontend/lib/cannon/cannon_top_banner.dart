import 'package:flutter/material.dart';
import 'cannon_art.dart';
import 'cannon_service.dart';
import 'cannon_config.dart';

class CannonTopBanner extends StatefulWidget {
  final Widget child;
  final String currentRoomId;
  final String accessToken;
  final Future<void> Function(String roomId)? onOpenRoom;
  final double topOffset;
  const CannonTopBanner({
    super.key, required this.child, required this.currentRoomId,
    required this.accessToken, this.onOpenRoom, this.topOffset = 56,
  });

  @override
  State<CannonTopBanner> createState() => _CannonTopBannerState();
}

class _CannonTopBannerState extends State<CannonTopBanner> {
  final CannonService _service = CannonService.instance;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _service.enterRoom(widget.currentRoomId, widget.accessToken);
    _service.startBanners(widget.accessToken);
  }

  @override
  void didUpdateWidget(covariant CannonTopBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoomId != widget.currentRoomId || oldWidget.accessToken != widget.accessToken) {
      _service.enterRoom(widget.currentRoomId, widget.accessToken);
      _service.startBanners(widget.accessToken);
    }
  }

  @override
  void dispose() {
    _service.leaveRoom();
    _service.stopBanners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          final candidates = _service.banners.where((b) => b.roomId != widget.currentRoomId).toList();
          if (candidates.isEmpty) return const SizedBox.shrink();
          final banner = candidates[_index % candidates.length];
          return Positioned(
            top: widget.topOffset, left: 12, right: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onOpenRoom == null ? null : () => widget.onOpenRoom!(banner.roomId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    image: CannonConfig.bannerImageUrl.isNotEmpty
                      ? DecorationImage(image: NetworkImage(CannonConfig.bannerImageUrl), fit: BoxFit.cover,
                          colorFilter: const ColorFilter.mode(Color(0x99000020), BlendMode.darken))
                      : null,
                    gradient: const LinearGradient(colors: [Color(0xFF142D8C), Color(0xFF061044)]),
                    border: Border.all(color: const Color(0xFF55C8FF), width: 1.2),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Stack(alignment: Alignment.center, children: [
                      CannonArt(level: banner.cannonLevel, size: 42),
                      if (CannonConfig.frameImageUrl.isNotEmpty)
                        Image.network(CannonConfig.frameImageUrl, width: 46, height: 46, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ]),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(banner.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      Text(banner.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB9DFFF), fontSize: 11)),
                    ])),
                    Text(banner.launching ? 'إطلاق' : '${banner.percent}%', style: const TextStyle(color: Color(0xFFFFD66B), fontWeight: FontWeight.w900)),
                    const SizedBox(width: 5),
                    const Icon(Icons.chevron_left, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
