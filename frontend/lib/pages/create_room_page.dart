import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'room_page.dart';

class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({super.key, required this.accessToken});
  final String accessToken;

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _gold = Color(0xFFE8C477);
  static const _purple = Color(0xFF9B63D9);
  static const _muted = Color(0xFFAAA2B5);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  late final AnimationController _backgroundMotion;
  XFile? _roomImage;
  Uint8List? _roomImageBytes;
  final ImagePicker _imagePicker = ImagePicker();
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';

  @override
  void initState() {
    super.initState();
    _backgroundMotion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundMotion.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickRoomImage() async {
    if (_isSubmitting) return;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (image == null || !mounted) return;

      // Open a square crop editor matching the room image preview.
      // The selected image is not applied until the user confirms the crop.
      final cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1200,
        maxHeight: 1200,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'قص صورة الغرفة',
            toolbarColor: const Color(0xFF17121F),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _gold,
            dimmedLayerColor: const Color(0xCC09080D),
            cropFrameColor: _gold,
            cropGridColor: _gold,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'قص صورة الغرفة',
            doneButtonTitle: 'اعتماد',
            cancelButtonTitle: 'إلغاء',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.page,
          ),
        ],
      );

      // Cancel keeps the previously approved room image unchanged.
      if (cropped == null || !mounted) return;
      final bytes = await cropped.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حجم الصورة بعد القص يجب ألا يتجاوز 5 ميجابايت')),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _roomImage = XFile(cropped.path, name: 'happy-room.jpg');
        _roomImageBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الصورة أو قصها، حاول مرة أخرى')),
      );
    }
  }

  Future<String> _uploadRoomImage() async {
    final image = _roomImage;
    final bytes = _roomImageBytes;
    if (image == null || bytes == null) return '';

    final authResponse = await http.get(
      Uri.parse('$_apiBase/imagekit/auth'),
      headers: {'Authorization': 'Bearer ${widget.accessToken}'},
    ).timeout(const Duration(seconds: 15));
    if (authResponse.statusCode != 200) {
      throw Exception('image_auth_failed');
    }
    final auth = jsonDecode(authResponse.body) as Map<String, dynamic>;
    final upload = http.MultipartRequest(
      'POST',
      Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
    );
    upload.fields.addAll({
      'fileName': 'happy-room-${DateTime.now().millisecondsSinceEpoch}-${image.name}',
      'publicKey': auth['publicKey'].toString(),
      'token': auth['token'].toString(),
      'expire': auth['expire'].toString(),
      'signature': auth['signature'].toString(),
      'useUniqueFileName': 'true',
      'folder': '/happy-live/rooms',
    });
    upload.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: image.name.isEmpty ? 'room.jpg' : image.name,
    ));
    final streamed = await upload.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('image_upload_failed');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final imageUrl = result['url']?.toString() ?? '';
    if (!imageUrl.startsWith('https://')) throw Exception('invalid_image_url');
    return imageUrl;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final imageUrl = await _uploadRoomImage();
      final response = await http.post(
        Uri.parse('$_apiBase/rooms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.accessToken}',
        },
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isPrivate': false,
          'imageUrl': imageUrl,
        }),
      ).timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (response.statusCode == 201 && data['ok'] == true) {
        if (!mounted) return;
        final room = Map<String, dynamic>.from(data['room'] as Map);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => RoomPage(room: room, accessToken: widget.accessToken),
          ),
        );
        return;
      }

      final message = (data['message'] ?? data['error'] ?? '').toString();
      final friendlyMessage = response.statusCode == 401
          ? 'انتهت جلسة الدخول، سجّل الدخول مرة أخرى'
          : response.statusCode == 503
              ? 'الخادم أو قاعدة البيانات غير متاحين حاليًا'
              : message == 'room_name_required'
                  ? 'اكتب اسم الغرفة'
                  : message == 'invalid_room_name'
                      ? 'اسم الغرفة يجب ألا يتجاوز 20 حرفًا'
                      : message == 'invalid_description'
                          ? 'الوصف يجب ألا يتجاوز 120 حرفًا'
                          : 'تعذر إنشاء الغرفة، حاول مرة أخرى';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyMessage), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر رفع الصورة أو الاتصال بالخادم، تحقق من الإنترنت وحاول مجددًا'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    prefixIcon: Icon(icon, color: _gold),
    filled: true,
    fillColor: const Color(0xFF100E15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0x665F4775)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0x665F4775)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: _gold, width: 1.2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: const Color(0xFF17121F),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'إنشاء غرفة حفلة',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w900),
          ),
        ),
        body: AnimatedBuilder(
          animation: _backgroundMotion,
          builder: (context, child) {
            final t = _backgroundMotion.value;
            final begin = Alignment.lerp(Alignment.topLeft, Alignment.bottomRight, t)!;
            final end = Alignment.lerp(Alignment.bottomRight, Alignment.topLeft, t)!;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: const [
                    Color(0xFF09080D),
                    Color(0xFF100B18),
                    Color(0xFF160D22),
                    Color(0xFF0B0911),
                  ],
                  stops: const [0.0, 0.38, 0.72, 1.0],
                ),
              ),
              child: child,
            );
          },
          child: SafeArea(
            bottom: false,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x665F4775)),
                  ),
                  child: const Column(
                      children: [
                        Icon(Icons.groups_rounded, color: _gold, size: 42),
                        SizedBox(height: 10),
                        Text(
                          'أنشئ غرفتك واجمع أصدقاءك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'أدخل تفاصيل الغرفة قبل إنشائها',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: _pickRoomImage,
                    child: Container(
                      width: 142,
                      height: 142,
                      decoration: BoxDecoration(
                        color: const Color(0xFF100E15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _gold, width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x339B63D9),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _roomImageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_roomImageBytes!, fit: BoxFit.cover),
                                Positioned(
                                  left: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: const BoxDecoration(
                                      color: Color(0xA6000000),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit_rounded, color: _gold, size: 17),
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, color: _gold, size: 38),
                                SizedBox(height: 9),
                                Text('إضافة صورة الغرفة', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                SizedBox(height: 4),
                                Text('اضغط لاختيار صورة', style: TextStyle(color: _muted, fontSize: 10)),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _nameController,
                  maxLength: 20,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('اسم الغرفة', Icons.meeting_room_outlined),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'اكتب اسم الغرفة'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 120,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('إعلان الغرفة (اختياري)', Icons.edit_note_rounded),
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 26),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add_rounded),
                    label: Text(_isSubmitting ? 'جارٍ إنشاء الغرفة...' : 'إنشاء الغرفة', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
