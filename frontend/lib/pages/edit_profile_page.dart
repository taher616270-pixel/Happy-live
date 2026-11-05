import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.apiBase, required this.accessToken, required this.name, required this.bio, this.avatarUrl});
  final String apiBase, accessToken, name, bio;
  final String? avatarUrl;
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const gold = Color(0xFFE8C477);
  static const purple = Color(0xFF9B63D9);
  late final _name = TextEditingController(text: widget.name);
  late final _bio = TextEditingController(text: widget.bio);
  final _picker = ImagePicker();
  String? _avatarUrl;
  bool _saving = false, _uploading = false;

  @override
  void initState() { super.initState(); _avatarUrl = widget.avatarUrl; }
  @override
  void dispose() { _name.dispose(); _bio.dispose(); super.dispose(); }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value), behavior: SnackBarBehavior.floating));
  }

  Future<void> _chooseImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1200);
      if (file == null) return;
      setState(() => _uploading = true);
      final auth = await http.get(Uri.parse('${widget.apiBase}/imagekit/auth'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'}).timeout(const Duration(seconds: 20));
      if (auth.statusCode != 200) {
        final data = jsonDecode(auth.body);
        throw Exception(data['error'] == 'imagekit_not_configured' ? 'رفع الصور غير مفعّل في الخادم بعد' : 'تعذر تجهيز رفع الصورة');
      }
      final credentials = jsonDecode(auth.body) as Map<String, dynamic>;
      final request = http.MultipartRequest('POST', Uri.parse('https://upload.imagekit.io/api/v1/files'));
      request.fields.addAll({
        'fileName': 'happy-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg',
        'publicKey': credentials['publicKey'].toString(),
        'signature': credentials['signature'].toString(),
        'token': credentials['token'].toString(),
        'expire': credentials['expire'].toString(),
        'folder': '/happy-live/avatars',
        'useUniqueFileName': 'true',
      });
      request.files.add(http.MultipartFile.fromBytes('file', await file.readAsBytes(), filename: 'avatar.jpg'));
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('تعذر رفع الصورة، حاول مرة أخرى');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final url = (result['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('لم يرجع خادم الصور رابط الصورة');
      if (mounted) setState(() => _avatarUrl = url);
      _message('تم رفع الصورة بنجاح');
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim(), bio = _bio.text.trim();
    if (name.length < 2 || name.length > 50) return _message('الاسم يجب أن يكون بين حرفين و50 حرفًا');
    if (bio.length > 160) return _message('النبذة يجب ألا تتجاوز 160 حرفًا');
    if (_uploading) return _message('انتظر حتى يكتمل رفع الصورة');
    setState(() => _saving = true);
    try {
      final response = await http.patch(Uri.parse('${widget.apiBase}/profile'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'bio': bio, 'avatarUrl': _avatarUrl})).timeout(const Duration(seconds: 20));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['ok'] != true) {
        throw Exception((payload['message'] ?? payload['error'] ?? 'تعذر حفظ التعديلات').toString());
      }
      final user = payload['user'] as Map<String, dynamic>? ?? {};
      if (mounted) Navigator.of(context).pop({
        'name': user['name'] ?? name, 'bio': user['bio'] ?? bio,
        'avatar_url': user['avatar_url'] ?? _avatarUrl,
      });
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _avatarUrl;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0910),
        appBar: AppBar(backgroundColor: const Color(0xFF15111D), foregroundColor: Colors.white,
          title: const Text('تعديل الملف الشخصي', style: TextStyle(fontWeight: FontWeight.w900)), centerTitle: true),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(child: InkWell(onTap: _uploading ? null : _chooseImage, borderRadius: BorderRadius.circular(64),
              child: Stack(alignment: Alignment.center, children: [
                CircleAvatar(radius: 58, backgroundColor: const Color(0xFF292032),
                  backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
                  child: url == null || url.isEmpty ? const Icon(Icons.person, size: 54, color: Colors.white70) : null),
                if (_uploading) const SizedBox(width: 116, height: 116, child: CircularProgressIndicator(color: gold, strokeWidth: 3)),
                Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(color: purple, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20))),
              ]))),
            const SizedBox(height: 10),
            const Text('اضغط على الصورة لتغييرها', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 28),
            _label('الاسم الظاهر'),
            _field(_name, 'اكتب اسمك', 50),
            const SizedBox(height: 18),
            _label('النبذة الشخصية'),
            _field(_bio, 'اكتب نبذة قصيرة عنك', 160, lines: 4),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1A1521), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x554F3D62))),
              child: const Row(children: [Icon(Icons.lock_outline_rounded, color: gold, size: 19), SizedBox(width: 9),
                Expanded(child: Text('رقم ID الخاص بك ثابت ولا يمكن تغييره', style: TextStyle(color: Colors.white70, fontSize: 13)))])),
            const SizedBox(height: 28),
            SizedBox(height: 52, child: FilledButton(
              onPressed: _saving || _uploading ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('حفظ التعديلات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)))),
          ]),
        ))),
      ),
    );
  }

  Widget _label(String value) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(value, style: const TextStyle(color: gold, fontWeight: FontWeight.w800)));
  Widget _field(TextEditingController c, String hint, int maxLength, {int lines = 1}) => TextField(
    controller: c, maxLength: maxLength, maxLines: lines, textDirection: TextDirection.rtl,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white38),
      filled: true, fillColor: const Color(0xFF17131F), counterStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x664F3D62))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: purple, width: 1.5))));
}
