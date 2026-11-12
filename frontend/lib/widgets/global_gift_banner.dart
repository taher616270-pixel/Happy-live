import 'dart:async';

import 'package:flutter/material.dart';

class GiftBannerData {
  const GiftBannerData({
    required this.senderName,
    required this.receiverName,
    required this.giftImage,
    this.senderAvatar = '',
    this.receiverAvatar = '',
    this.message = '',
    this.level = 0,
    this.style = 'green',
  });

  final String senderName;
  final String receiverName;
  final String giftImage;
  final String senderAvatar;
  final String receiverAvatar;
  final String message;
  final int level;
  final String style;

  factory GiftBannerData.fromMap(Map<String, dynamic> value) {
    return GiftBannerData(
      senderName: (value['senderName'] ?? 'مستخدم').toString(),
      receiverName: (value['receiverName'] ?? 'مستخدم').toString(),
      giftImage: (value['giftImage'] ?? '').toString(),
      senderAvatar: (value['senderAvatar'] ?? '').toString(),
      receiverAvatar: (value['receiverAvatar'] ?? '').toString(),
      message: (value['message'] ?? '').toString(),
      level: (value['level'] as num?)?.toInt() ?? 0,
      style: (value['style'] ?? 'green').toString(),
    );
  }
}

class GiftBannerHost extends StatefulWidget {
  const GiftBannerHost({super.key, required this.stream});
  final Stream<Map<String, dynamic>> stream;

  @override
  State<GiftBannerHost> createState() => _GiftBannerHostState();
}

class _GiftBannerHostState extends State<GiftBannerHost> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<GiftBannerData> _queue = <GiftBannerData>[];
  GiftBannerData? _current;
  Timer? _hideTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant GiftBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.stream.listen((event) {
      _queue.add(GiftBannerData.fromMap(event));
      _pump();
    });
  }

  Future<void> _pump() async {
    if (_busy || !mounted || _queue.isEmpty) return;
    _busy = true;
    setState(() => _current = _queue.removeAt(0));
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _current = null);
      _busy = false;
      _pump();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            offset: _current == null ? const Offset(0, -1.4) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _current == null ? 0 : 1,
              child: _current == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 110, left: 12, right: 12),
                      child: _GiftBannerCard(data: _current!),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftBannerCard extends StatelessWidget {
  const _GiftBannerCard({required this.data});
  final GiftBannerData data;

  @override
  Widget build(BuildContext context) {
    final special = data.style == 'blue';
    final start = special ? const Color(0xFF145C9E) : const Color(0xFF176B49);
    final end = special ? const Color(0xFF102F67) : const Color(0xFF103D35);
    final image = data.giftImage;
    final imageIsUrl = image.startsWith('https://') || image.startsWith('http://');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [start, end]),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withOpacity(.28)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 7)),
          ],
        ),
        child: Row(
          children: [
            _BannerAvatar(url: data.senderAvatar, name: data.senderName),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.message.isEmpty
                        ? '${data.senderName} أرسل هدية إلى ${data.receiverName}'
                        : data.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'إلى ${data.receiverName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFDCE9E2), fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Container(
              width: 43,
              height: 43,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(12)),
              child: imageIsUrl
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(image, width: 39, height: 39, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 25))),
                    )
                  : Text(image.isEmpty ? '🎁' : image, style: const TextStyle(fontSize: 25)),
            ),
            const SizedBox(width: 8),
            _BannerAvatar(url: data.receiverAvatar, name: data.receiverName),
          ],
        ),
      ),
    );
  }
}

class _BannerAvatar extends StatelessWidget {
  const _BannerAvatar({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final valid = url.startsWith('https://') || url.startsWith('http://');
    return CircleAvatar(
      radius: 17,
      backgroundColor: Colors.white.withOpacity(.18),
      backgroundImage: valid ? NetworkImage(url) : null,
      child: valid ? null : Text(name.isEmpty ? '؟' : name.characters.first, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class GiftComboBanner extends StatelessWidget {
  const GiftComboBanner({
    super.key,
    required this.senderName,
    required this.receiverName,
    required this.giftImage,
    required this.count,
    required this.child,
  });

  final String senderName;
  final String receiverName;
  final String giftImage;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isUrl = giftImage.startsWith('https://') || giftImage.startsWith('http://');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE91A1720),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x88D4AF37)),
      ),
      child: Row(
        children: [
          if (isUrl)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(giftImage, width: 34, height: 34, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(width: 34, height: 34, child: Center(child: Text('🎁')))),
            )
          else
            SizedBox(width: 34, child: Center(child: Text(giftImage.isEmpty ? '🎁' : giftImage, style: const TextStyle(fontSize: 23)))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$senderName ← $receiverName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 7),
          Text('×$count', style: const TextStyle(color: Color(0xFFFFD76A), fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          child,
        ],
      ),
    );
  }
}

class GiftComboButton extends StatefulWidget {
  const GiftComboButton({
    super.key,
    required this.onResend,
    required this.onExpired,
  });

  final Future<void> Function(int quantity) onResend;
  final VoidCallback onExpired;

  @override
  State<GiftComboButton> createState() => _GiftComboButtonState();
}

class _GiftComboButtonState extends State<GiftComboButton> {
  Timer? _timer;
  int _remainingMs = 3000;
  bool _sending = false;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _expired) return;
      _remainingMs -= 100;
      if (_remainingMs <= 0) {
        timer.cancel();
        setState(() => _expired = true);
        widget.onExpired();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _resend() async {
    if (_sending || _expired) return;
    setState(() {
      _sending = true;
      _remainingMs = 3000;
    });
    try {
      await widget.onResend(1);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _sending ? null : _resend,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xE82B2419),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD4AF37)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.replay_rounded, color: Color(0xFFFFD76A), size: 17),
                const SizedBox(width: 7),
                Text(_sending ? 'جارٍ التكرار…' : 'إرسال مرة أخرى',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 9),
                Text('${(_remainingMs / 1000).ceil()}',
                    style: const TextStyle(color: Color(0xFFFFD76A), fontSize: 12, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
