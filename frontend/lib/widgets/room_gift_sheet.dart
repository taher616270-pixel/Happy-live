import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:happy_live/widgets/global_gift_banner.dart';
import 'package:flutter_svga/flutter_svga.dart';
import 'package:gif_view/gif_view.dart';

typedef GiftCatalogLoader = Future<List<Map<String, dynamic>>> Function(String category);
typedef RoomGiftSender = Future<int> Function(Map<String, dynamic> gift, int quantity, String recipientId);
typedef CustomGiftRequester = Future<void> Function(String name, String description, Uint8List bytes, String fileName, String mediaType, int durationMs, Uint8List? soundBytes, String? soundFileName);

Future<void> showRoomGiftSheet(
  BuildContext context, {
  required int balance,
  required String avatarUrl,
  required List<Map<String, dynamic>> recipients,
  String initialRecipientId = '',
  required GiftCatalogLoader loadGifts,
  required RoomGiftSender onSend,
  required CustomGiftRequester onRequestCustomGift,
  required VoidCallback onRecharge,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (_) => _RoomGiftSheet(
      balance: balance,
      avatarUrl: avatarUrl,
      recipients: recipients,
      initialRecipientId: initialRecipientId,
      loadGifts: loadGifts,
      onSend: onSend,
      onRequestCustomGift: onRequestCustomGift,
      onRecharge: onRecharge,
    ),
  );
}

class _RoomGiftSheet extends StatefulWidget {
  const _RoomGiftSheet({
    required this.balance,
    required this.avatarUrl,
    required this.recipients,
    required this.initialRecipientId,
    required this.loadGifts,
    required this.onSend,
    required this.onRequestCustomGift,
    required this.onRecharge,
  });

  final int balance;
  final String avatarUrl;
  final List<Map<String, dynamic>> recipients;
  final String initialRecipientId;
  final GiftCatalogLoader loadGifts;
  final RoomGiftSender onSend;
  final CustomGiftRequester onRequestCustomGift;
  final VoidCallback onRecharge;

  @override
  State<_RoomGiftSheet> createState() => _RoomGiftSheetState();
}

class _RoomGiftSheetState extends State<_RoomGiftSheet> {
  static const _gold = Color(0xFFE8C477);
  static const _muted = Color(0xFFAAA2B5);
  static const _tabs = <List<String>>[
    ['event', 'حدث'],
    ['trending', 'رائج'],
    ['country', 'الدولة'],
    ['lucky', 'حظ'],
    ['vip', 'VIP'],
    ['custom', 'مخصص'],
  ];
  static const _quantities = <int>[1, 7, 17, 77, 177, 777];

  late Future<List<Map<String, dynamic>>> _giftsFuture;
  late int _balance;
  String _tab = 'trending';
  final Set<String> _recipientIds = <String>{};
  Map<String, dynamic>? _selectedGift;
  int _quantity = 1;
  bool _sending = false;
  Map<String, dynamic>? _comboGift;
  String? _comboRecipientId;
  int _comboCount = sentQuantity;
  int _comboNonce = 0;
  bool _requesting = false;
  String? _message;
  final _customName = TextEditingController();
  final _customDescription = TextEditingController();
  bool _customCreating = false;
  Uint8List? _customMediaBytes;
  String? _customMediaName;
  String? _customMediaType;
  int? _customMediaDurationMs;
  Uint8List? _customSoundBytes;
  String? _customSoundName;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _giftsFuture = widget.loadGifts(_tab);
    final initialId = widget.initialRecipientId.trim();
    if (initialId.isNotEmpty && widget.recipients.any((r) => (r['userId'] ?? '').toString() == initialId)) {
      _recipientIds.add(initialId);
    } else if (widget.recipients.length == 1) {
      _recipientIds.add((widget.recipients.first['userId'] ?? '').toString());
    }
  }

  @override
  void dispose() {
    _customName.dispose();
    _customDescription.dispose();
    super.dispose();
  }

  void _selectTab(String tab) {
    setState(() {
      _tab = tab;
      _selectedGift = null;
      _customCreating = false;
      if (tab != 'vip') _giftsFuture = widget.loadGifts(tab);
    });
  }

  void _showMessage(String value) {
    if (!mounted) return;
    setState(() => _message = value);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _message == value) setState(() => _message = null);
    });
  }

  Future<void> _sendGift() async {
    final gift = _selectedGift;
    final recipientIds = _recipientIds.toList();
    final sentQuantity = _quantity;
    if (gift == null || _sending) return;
    if (recipientIds.isEmpty) {
      _showMessage('اختر مستلم الهدية أولًا');
      return;
    }
    final price = (gift['coinPrice'] as num?)?.toInt() ?? 0;
    if (price < 1 || price * sentQuantity * recipientIds.length > _balance) {
      _showMessage('رصيدك من العملات غير كافٍ لإرسال الهدايا المحددة');
      return;
    }
    setState(() => _sending = true);
    var sent = 0;
    try {
      for (final recipientId in recipientIds) {
        _balance = await widget.onSend(gift, sentQuantity, recipientId);
        sent++;
        if (mounted) setState(() {});
      }
      if (mounted) {
        setState(() {
          _selectedGift = null;
          _comboGift = recipientIds.length == 1 ? Map<String, dynamic>.from(gift) : null;
          _comboRecipientId = recipientIds.length == 1 ? recipientIds.first : null;
          _comboCount = 1;
          _comboNonce++;
        });
        _showMessage(recipientIds.length == 1 ? 'تم إرسال الهدية بنجاح' : 'تم إرسال الهدية إلى $sent مستلمين');
      }
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '');
      _showMessage(sent > 0 ? 'تم الإرسال إلى $sent مستلمين، وتعذر إكمال الباقي: $detail' : detail);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickCustomMedia() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gif', 'svga'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      final extension = (file.extension ?? file.name.split('.').last).toLowerCase();
      if (bytes == null || bytes.isEmpty) throw Exception('تعذر قراءة الملف المحدد');
      if (bytes.length > 10 * 1024 * 1024) throw Exception('الحد الأقصى لحجم الملف 10 ميجابايت');
      if (extension != 'gif' && extension != 'svga') throw Exception('اختر ملف GIF أو SVGA فقط');

      int durationMs;
      if (extension == 'gif') {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          if (codec.frameCount < 2) throw Exception('ملف GIF يجب أن يحتوي على حركة');
          var total = 0;
          for (var i = 0; i < codec.frameCount; i++) {
            final frame = await codec.getNextFrame();
            total += frame.duration.inMilliseconds;
            frame.image.dispose();
            if (total > 5000) break;
          }
          durationMs = total;
        } finally {
          codec.dispose();
        }
      } else {
        final movie = await SVGAParser.shared.decodeFromBuffer(bytes);
        final fps = movie.params.fps;
        final frames = movie.params.frames;
        movie.releaseMemory();
        if (fps <= 0 || frames <= 0) throw Exception('ملف SVGA غير صالح أو لا يحتوي على مدة واضحة');
        durationMs = ((frames * 1000) / fps).ceil();
      }
      if (durationMs < 1 || durationMs > 5000) throw Exception('مدة الحركة تتجاوز 5 ثوانٍ');
      if (!mounted) return;
      setState(() {
        _customMediaBytes = bytes;
        _customMediaName = file.name;
        _customMediaType = extension;
        _customMediaDurationMs = durationMs;
      });
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickCustomSound() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['mp3'], withData: true, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      final extension = (file.extension ?? file.name.split('.').last).toLowerCase();
      if (bytes == null || bytes.isEmpty) throw Exception('تعذر قراءة ملف الصوت');
      if (extension != 'mp3' || bytes.length > 5 * 1024 * 1024) throw Exception('اختر ملف MP3 لا يتجاوز 5 ميجابايت');
      if (!mounted) return;
      setState(() { _customSoundBytes = bytes; _customSoundName = file.name; });
    } catch (error) { _showMessage(error.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> _submitCustomRequest() async {
    final name = _customName.text.trim();
    final description = _customDescription.text.trim();
    final bytes = _customMediaBytes;
    final fileName = _customMediaName;
    final mediaType = _customMediaType;
    final durationMs = _customMediaDurationMs;
    final soundBytes = _customSoundBytes;
    final soundFileName = _customSoundName;
    if (name.length < 2) { _showMessage('اكتب اسم الهدية المقترحة'); return; }
    if (bytes == null || fileName == null || mediaType == null || durationMs == null) { _showMessage('اختر ملف GIF أو SVGA أولًا'); return; }
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await widget.onRequestCustomGift(name, description, bytes, fileName, mediaType, durationMs, soundBytes, soundFileName);
      _customName.clear();
      _customDescription.clear();
      setState(() {
        _customMediaBytes = null;
        _customMediaName = null;
        _customMediaType = null;
        _customMediaDurationMs = null;
        _customSoundBytes = null;
        _customSoundName = null;
        _customCreating = false;
      });
      _showMessage('تم رفع الهدية وإرسالها للإدارة للمراجعة');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * .56,
        decoration: const BoxDecoration(
          color: Color(0xF20B0912),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Color(0x33E8C477))),
        ),
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                children: [
                  _topRow(),
                  _tabsRow(),
                  if (_tab == 'vip')
                    const Expanded(child: Center(child: Text('قريبًا', style: TextStyle(color: _muted, fontSize: 15))))
                  else if (_tab == 'custom')
                    Expanded(child: _customCreating ? _customRequestForm() : _customHome())
                  else
                    Expanded(child: _giftGrid()),
                  if (_comboGift != null && _comboRecipientId != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: GiftComboBanner(
                        senderName: 'أنت',
                        receiverName: (widget.recipients.firstWhere(
                          (item) => (item['userId'] ?? '').toString() == _comboRecipientId,
                          orElse: () => const <String, dynamic>{'name': 'المستلم'},
                        )['name'] ?? 'المستلم').toString(),
                        giftImage: (_comboGift!['mediaUrl'] ?? _comboGift!['iconEmoji'] ?? '🎁').toString(),
                        count: _comboCount,
                        child: GiftComboButton(
                          key: ValueKey('gift-combo-$_comboNonce'),
                          onResend: (quantity) async {
                            try {
                              final updatedBalance = await widget.onSend(
                                _comboGift!,
                                quantity,
                                _comboRecipientId!,
                              );
                              if (mounted) {
                                setState(() {
                                  _balance = updatedBalance;
                                  _comboCount += quantity;
                                });
                              }
                            } catch (error) {
                              _showMessage(error.toString().replaceFirst('Exception: ', ''));
                            }
                          },
                          onExpired: () {
                            if (!mounted) return;
                            setState(() {
                              _comboGift = null;
                              _comboRecipientId = null;
                            });
                          },
                        ),
                      ),
                    ),
                  if (_tab != 'vip') _bottomBar(),
                ],
              ),
              if (_message != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 72,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .52),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xF02A2530),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x55E8C477)),
                          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 4))],
                        ),
                        child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topRow() {
    final avatar = widget.avatarUrl;
    final allRecipientIds = widget.recipients
        .where((r) => r['isMe'] != true)
        .map((r) => (r['userId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final allSelected = allRecipientIds.isNotEmpty && _recipientIds.containsAll(allRecipientIds);
    Widget avatarFor(String url, String name, {bool selected = false, VoidCallback? onTap}) {
      final hasImage = url.startsWith('https://') || url.startsWith('http://');
      final child = CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFF302B36),
        backgroundImage: hasImage ? NetworkImage(url) : null,
        child: hasImage ? null : Text(name.isEmpty ? '؟' : name.characters.first,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      );
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? _gold : Colors.transparent, width: 2),
          ),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          avatarFor(avatar, 'أنا'),
          const SizedBox(width: 9),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.recipients.map((recipient) {
                  final id = (recipient['userId'] ?? '').toString();
                  if (id.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 7),
                    child: avatarFor(
                      (recipient['avatarUrl'] ?? recipient['avatar'] ?? '').toString(),
                      (recipient['name'] ?? 'مستخدم').toString(),
                      selected: _recipientIds.contains(id),
                      onTap: () => setState(() {
                        if (_recipientIds.contains(id)) {
                          _recipientIds.remove(id);
                        } else {
                          _recipientIds.add(id);
                        }
                      }),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: allRecipientIds.isEmpty ? null : () => setState(() {
              if (allSelected) {
                _recipientIds.removeAll(allRecipientIds);
              } else {
                _recipientIds.addAll(allRecipientIds);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: allSelected ? _gold.withOpacity(.22) : const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: allSelected ? _gold : Colors.white24),
              ),
              child: Text('الجميع', style: TextStyle(
                color: allSelected ? _gold : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _tabs.map((tab) {
                  final active = _tab == tab[0];
                  return GestureDetector(
                    onTap: () => _selectTab(tab[0]),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 18),
                      child: Column(children: [
                        Text(tab[1], style: TextStyle(color: active ? Colors.white : _muted, fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                        const SizedBox(height: 4),
                        Container(width: 18, height: 2, color: active ? _gold : Colors.transparent),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showMessage('الحقيبة قريبًا'),
            child: const Padding(
              padding: EdgeInsetsDirectional.only(start: 4),
              child: Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _giftMedia(Map<String, dynamic> gift) {
    final url = (gift['mediaUrl'] ?? '').toString().trim();
    final type = (gift['mediaType'] ?? 'emoji').toString().toLowerCase();
    if (url.isEmpty || type == 'emoji') {
      return Text((gift['iconEmoji'] ?? '🎁').toString(), style: const TextStyle(fontSize: 34));
    }
    if (type == 'svga') {
      return SVGAEasyPlayer(resUrl: url, fit: BoxFit.contain, volume: 0, muted: true);
    }
    if (type == 'gif' || type == 'apng') {
      return GifView.network(
        url,
        width: 58,
        height: 58,
        fit: BoxFit.contain,
        frameRate: 24,
        errorBuilder: (context, error, tryAgain) => const Icon(Icons.broken_image_outlined, color: _muted, size: 28),
      );
    }
    if (type == 'webp') {
      return Image.network(
        url,
        width: 58,
        height: 58,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: _muted, size: 28),
      );
    }
    return Text((gift['iconEmoji'] ?? '🎁').toString(), style: const TextStyle(fontSize: 34));
  }

  Widget _giftGrid() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _giftsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: _gold, strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعذر تحميل قائمة الهدايا', style: TextStyle(color: Colors.white70)),
            TextButton(onPressed: () => setState(() => _giftsFuture = widget.loadGifts(_tab)), child: const Text('إعادة المحاولة', style: TextStyle(color: _gold))),
          ]));
        }
        final gifts = snapshot.data ?? const <Map<String, dynamic>>[];
        if (gifts.isEmpty) return const Center(child: Text('لا توجد هدايا متاحة حاليًا', style: TextStyle(color: _muted)));
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: .78, mainAxisSpacing: 5, crossAxisSpacing: 5),
          itemCount: gifts.length,
          itemBuilder: (_, index) {
            final gift = gifts[index];
            final selected = _selectedGift?['id'] == gift['id'];
            return GestureDetector(
              onTap: () => setState(() => _selectedGift = gift),
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? const Color(0x44E8C477) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? _gold : Colors.transparent, width: 1.2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 58, height: 58, child: Center(child: _giftMedia(gift))),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text((gift['name'] ?? 'هدية').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                  const SizedBox(height: 3),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text((gift['coinPrice'] ?? 0).toString(), style: const TextStyle(color: _muted, fontSize: 10)),
                    const SizedBox(width: 3),
                    const Icon(Icons.monetization_on, color: _gold, size: 11),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _customHome() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _customCreating = true),
              icon: const Icon(Icons.add_circle_outline, color: _gold, size: 18),
              label: const Text('اقترح هدية مخصصة', style: TextStyle(color: _gold, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0x66E8C477)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
        Expanded(child: _giftGrid()),
      ],
    );
  }

  Widget _customRequestForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: _requesting ? null : () => setState(() => _customCreating = false),
          icon: const Icon(Icons.arrow_forward, color: _gold, size: 18),
          label: const Text('رجوع', style: TextStyle(color: _gold, fontSize: 12)),
        )),
        const Text('إنشاء هدية مخصصة', style: TextStyle(color: _gold, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(controller: _customName, maxLength: 80, style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'اسم الهدية', hintStyle: TextStyle(color: _muted, fontSize: 12), filled: true, fillColor: Color(0xFF100D15), border: OutlineInputBorder(borderSide: BorderSide.none))),
        const SizedBox(height: 8),
        TextField(controller: _customDescription, maxLength: 500, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'وصف مختصر (اختياري)', hintStyle: TextStyle(color: _muted, fontSize: 11), filled: true, fillColor: Color(0xFF100D15), border: OutlineInputBorder(borderSide: BorderSide.none))),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _requesting ? null : _pickCustomMedia, icon: const Icon(Icons.upload_file, color: _gold),
          label: Text(_customMediaName == null ? 'اختيار ملف GIF أو SVGA' : 'تغيير الملف', style: const TextStyle(color: _gold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0x66E8C477)))),
        if (_customMediaName != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF211D27), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.movie_creation_outlined, color: _gold, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(_customMediaName! + '\n' + (_customMediaType ?? '').toUpperCase() + ' · ' + (_customMediaDurationMs ?? 0).toString() + ' ms', style: const TextStyle(color: Colors.white, fontSize: 11))),
              IconButton(onPressed: _requesting ? null : () => setState(() { _customMediaBytes = null; _customMediaName = null; _customMediaType = null; _customMediaDurationMs = null; }), icon: const Icon(Icons.close, color: _muted, size: 18)),
            ])),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _requesting ? null : _pickCustomSound,
          icon: const Icon(Icons.music_note, color: _gold),
          label: Text(_customSoundName == null ? 'إضافة صوت MP3 (اختياري)' : 'تغيير صوت MP3', style: const TextStyle(color: _gold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0x66E8C477))),
        ),
        if (_customSoundName != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            const Icon(Icons.audiotrack, color: _gold, size: 18),
            const SizedBox(width: 7),
            Expanded(child: Text(_customSoundName!, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: _requesting ? null : () => setState(() { _customSoundBytes = null; _customSoundName = null; }), icon: const Icon(Icons.close, color: _muted, size: 17)),
          ])),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('GIF أو SVGA حتى 5 ثوانٍ و10MB · صوت MP3 اختياري حتى 5MB', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 10))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _requesting ? null : _submitCustomRequest, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A2BFF), foregroundColor: Colors.white),
          child: _requesting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('رفع وإرسال للإدارة')),
      ]),
    );
  }

  Widget _bottomBar() {
    final selectedPrice = (_selectedGift?['coinPrice'] as num?)?.toInt() ?? 0;
    final total = selectedPrice * _quantity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(children: [
        GestureDetector(
          onTap: widget.onRecharge,
          child: Row(children: [
            const Icon(Icons.monetization_on, color: _gold, size: 16),
            const SizedBox(width: 4),
            Text(_balance.toString(), style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Icon(Icons.chevron_left, color: _muted, size: 18),
          ]),
        ),
        const Spacer(),
        Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFF211D27), borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            PopupMenuButton<int>(
              color: const Color(0xFF211D27),
              onSelected: (value) => setState(() => _quantity = value),
              itemBuilder: (_) => _quantities.map((value) => PopupMenuItem<int>(value: value, child: Text(value.toString(), style: const TextStyle(color: Colors.white)))).toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [Text(_quantity.toString(), style: const TextStyle(color: Colors.white, fontSize: 13)), const Icon(Icons.keyboard_arrow_down, color: _muted, size: 18)]),
              ),
            ),
            GestureDetector(
              onTap: _sending || _selectedGift == null || total > _balance ? null : _sendGift,
              child: Container(
                width: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _selectedGift == null || total > _balance ? const Color(0xFF514A57) : const Color(0xFF8A2BFF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: _sending ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(total > 0 ? 'إرسال · $total' : 'إرسال', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
