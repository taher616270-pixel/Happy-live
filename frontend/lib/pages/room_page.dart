import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.room});

  final Map<String, dynamic> room;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  static const _background = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _purple = Color(0xFF9B63D9);
  static const _gold = Color(0xFFE8C477);
  static const _muted = Color(0xFFAAA2B5);

  int? _mySeat;

  String get _roomName => (widget.room['name'] ?? 'غرفة صوتية').toString();
  String get _roomCode => (widget.room['roomCode'] ?? '').toString();
  String? get _imageUrl {
    final value = widget.room['imageUrl']?.toString();
    return value != null && value.startsWith('https://') ? value : null;
  }

  Future<void> _copyRoomCode() async {
    if (_roomCode.length != 8) return;
    await Clipboard.setData(ClipboardData(text: _roomCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رقم الغرفة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleSeat(int index) {
    setState(() {
      _mySeat = _mySeat == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _roomName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x665F4775)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: SizedBox(
                              width: 58,
                              height: 58,
                              child: _imageUrl == null
                                  ? const ColoredBox(
                                      color: Color(0xFF241A32),
                                      child: Icon(Icons.groups_rounded, color: _gold, size: 29),
                                    )
                                  : Image.network(
                                      _imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const ColoredBox(
                                        color: Color(0xFF241A32),
                                        child: Icon(Icons.groups_rounded, color: _gold, size: 29),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _roomName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                                if ((widget.room['description'] ?? '').toString().trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.room['description'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _copyRoomCode,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF120E19),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x665F4775)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tag_rounded, color: _gold, size: 19),
                            const SizedBox(width: 8),
                            const Text('رقم الغرفة', style: TextStyle(color: _muted, fontSize: 13)),
                            const Spacer(),
                            Text(
                              _roomCode.isEmpty ? '--------' : _roomCode,
                              style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.copy_rounded, color: _purple, size: 17),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Text('المايكات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                        Spacer(),
                        Text('6 مقاعد', style: TextStyle(color: _muted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.88,
                      ),
                      itemBuilder: (context, index) {
                        final occupied = _mySeat == index;
                        return InkWell(
                          onTap: () => _toggleSeat(index),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            decoration: BoxDecoration(
                              color: occupied ? const Color(0xFF251936) : _surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: occupied ? _purple : const Color(0x665F4775),
                                width: occupied ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: occupied ? _purple.withOpacity(0.22) : const Color(0xFF241A32),
                                    border: Border.all(color: occupied ? _gold : const Color(0x665F4775)),
                                  ),
                                  child: Icon(
                                    occupied ? Icons.mic_rounded : Icons.mic_none_rounded,
                                    color: occupied ? _gold : _muted,
                                    size: 27,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  'مايك ${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  occupied ? 'أنت هنا' : 'فارغ',
                                  style: TextStyle(color: occupied ? _gold : _muted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
                decoration: const BoxDecoration(
                  color: _surface,
                  border: Border(top: BorderSide(color: Color(0x665F4775))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF241A32),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.person_rounded, color: _gold, size: 25),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('أنت صاحب الغرفة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                          SizedBox(height: 3),
                          Text('مكانك هنا أسفل المايكات', style: TextStyle(color: _muted, fontSize: 11)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _mySeat == null ? null : () => setState(() => _mySeat = null),
                      child: const Text('مغادرة المايك', style: TextStyle(color: _gold, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
