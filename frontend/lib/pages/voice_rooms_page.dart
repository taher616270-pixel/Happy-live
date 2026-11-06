import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'room_page.dart';

class VoiceRoomsPage extends StatefulWidget {
  const VoiceRoomsPage({super.key, required this.accessToken});
  final String accessToken;

  @override
  State<VoiceRoomsPage> createState() => _VoiceRoomsPageState();
}

class _VoiceRoomsPageState extends State<VoiceRoomsPage> {
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  static const Color _background = Color(0xFF0D0B13);
  static const Color _gold = Color(0xFFD9A93C);
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('$_apiBase/rooms'))
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true && data['rooms'] is List) {
        final rooms = (data['rooms'] as List)
            .whereType<Map>()
            .map((room) => Map<String, dynamic>.from(room))
            .toList();
        if (mounted) setState(() => _rooms = rooms);
      } else {
        if (mounted) setState(() => _error = 'تعذر تحميل الغرف الصوتية الآن');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تحقق من اتصال الإنترنت ثم حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => RoomPage(room: room, accessToken: widget.accessToken),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));
    if (mounted) _loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 19),
          ),
          title: const Text('الغرف الصوتية',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadRooms,
              icon: const Icon(Icons.refresh_rounded, color: _gold),
              tooltip: 'تحديث الغرف',
            ),
          ],
        ),
        body: RefreshIndicator(
          color: _gold,
          backgroundColor: const Color(0xFF21182B),
          onRefresh: _loadRooms,
          child: _loading && _rooms.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : _error != null && _rooms.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 150),
                      Icon(Icons.wifi_off_rounded, color: Colors.white.withOpacity(.55), size: 42),
                      const SizedBox(height: 14),
                      Text(_error!, textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 14),
                      Center(child: TextButton(onPressed: _loadRooms,
                          child: const Text('إعادة المحاولة', style: TextStyle(color: _gold)))),
                    ])
                  : _rooms.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 150),
                          Icon(Icons.meeting_room_outlined, color: _gold, size: 48),
                          SizedBox(height: 14),
                          Text('لا توجد غرف صوتية نشطة حاليًا',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                          SizedBox(height: 7),
                          Text('اسحب للأسفل لتحديث القائمة',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ])
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                          itemCount: _rooms.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 11),
                          itemBuilder: (context, index) {
                            final room = _rooms[index];
                            final name = (room['name'] ?? 'غرفة صوتية').toString();
                            final description = (room['description'] ?? '').toString();
                            final image = (room['imageUrl'] ?? '').toString();
                            final code = (room['roomCode'] ?? '').toString();
                            return Material(
                              color: const Color(0xFF1B1722),
                              borderRadius: BorderRadius.circular(17),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(17),
                                onTap: () => _openRoom(room),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(17),
                                    border: Border.all(color: const Color(0x44D9A93C)),
                                  ),
                                  child: Row(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: SizedBox(
                                        width: 62, height: 62,
                                        child: image.startsWith('https://')
                                            ? Image.network(image, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => _roomPlaceholder())
                                            : _roomPlaceholder(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                                        if (description.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                        ],
                                        const SizedBox(height: 5),
                                        Text('ID: $code', style: const TextStyle(color: _gold, fontSize: 10)),
                                      ],
                                    )),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.play_circle_fill_rounded, color: _gold, size: 29),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
  }

  Widget _roomPlaceholder() => Container(
    color: const Color(0xFF30263A),
    alignment: Alignment.center,
    child: const Icon(Icons.graphic_eq_rounded, color: _gold, size: 30),
  );
}
