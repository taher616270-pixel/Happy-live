import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const _ink = Color(0xFF1E2233);
const _grey = Color(0xFF8E8CA0);
const _fieldBg = Color(0xFFF2F4F6);

class EditProfileData {
  final String name, bio, birthDate, gender, country;
  final String? avatarUrl;
  const EditProfileData({
    required this.name,
    required this.bio,
    required this.birthDate,
    required this.gender,
    required this.country,
    this.avatarUrl,
  });
}

class EditProfilePage extends StatefulWidget {
  final String apiBase, accessToken;
  final String avatarUrl, name, bio, birthDate, gender, country;
  final bool canChangeGender, canChangeCountry;
  final List<String> genders, countries;
  final VoidCallback? onAvatarTap, onBack;
  final Future<void> Function(EditProfileData)? onSave;

  const EditProfilePage({
    super.key,
    required this.apiBase,
    required this.accessToken,
    required this.avatarUrl,
    required this.name,
    this.bio = '',
    this.birthDate = '2000-01-01',
    this.gender = 'ذكر',
    this.country = 'Saudi Arabia',
    this.canChangeGender = true,
    this.canChangeCountry = true,
    this.genders = const ['ذكر', 'أنثى'],
    this.countries = const [
      'Saudi Arabia', 'Kuwait', 'United Arab Emirates', 'Qatar',
      'Bahrain', 'Oman', 'Iraq', 'Yemen', 'Egypt', 'Jordan',
    ],
    this.onAvatarTap,
    this.onBack,
    this.onSave,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _bio = TextEditingController(text: widget.bio);
  late String _birth = widget.birthDate;
  late String _gender = widget.gender;
  late String _country = widget.country;
  String? _avatarUrl;
  bool _uploading = false, _saving = false;
  final _picker = ImagePicker();

  bool get _dirty => _name.text.trim() != widget.name ||
      _bio.text.trim() != widget.bio || _birth != widget.birthDate ||
      _gender != widget.gender || _country != widget.country ||
      (_avatarUrl ?? '') != widget.avatarUrl;
  bool get _canSave => _dirty && _name.text.trim().isNotEmpty && !_saving && !_uploading;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.avatarUrl;
    _name.addListener(_refresh);
    _bio.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _chooseAvatar() async {
    if (widget.onAvatarTap != null) {
      widget.onAvatarTap!();
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 88, maxWidth: 1200,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final auth = await http.get(
        Uri.parse('${widget.apiBase}/imagekit/auth'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 20));
      if (auth.statusCode != 200) {
        final body = jsonDecode(auth.body);
        throw Exception(body['error'] == 'imagekit_not_configured'
            ? 'رفع الصور غير مفعّل في الخادم بعد'
            : 'تعذر تجهيز رفع الصورة');
      }
      final credentials = jsonDecode(auth.body) as Map<String, dynamic>;
      final request = http.MultipartRequest(
        'POST', Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
      );
      request.fields.addAll({
        'fileName': 'happy-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg',
        'publicKey': credentials['publicKey'].toString(),
        'signature': credentials['signature'].toString(),
        'token': credentials['token'].toString(),
        'expire': credentials['expire'].toString(),
        'folder': '/happy-live/avatars',
        'useUniqueFileName': 'true',
      });
      request.files.add(http.MultipartFile.fromBytes(
        'file', await file.readAsBytes(), filename: 'avatar.jpg',
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('تعذر رفع الصورة، حاول مرة أخرى');
      }
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

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_birth) ?? DateTime(2000, 1, 1);
    final d = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(1940), lastDate: DateTime.now(),
    );
    if (d != null) {
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      setState(() => _birth = '${d.year}-$m-$day');
    }
  }

  Future<String?> _pick(List<String> items) => showModalBottomSheet<String>(
    context: context, backgroundColor: Colors.white, isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .6),
          child: ListView(shrinkWrap: true, children: [
            for (final item in items)
              ListTile(title: Text(item), onTap: () => Navigator.pop(context, item)),
          ]),
        ),
      ),
    ),
  );

  Future<void> _confirm() async {
    if (!_canSave) return;
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 30) {
      _message('الاسم يجب أن يكون بين حرفين و30 حرفًا');
      return;
    }
    if (_bio.text.trim().length > 100) {
      _message('النبذة يجب ألا تتجاوز 100 حرف');
      return;
    }
    final callback = widget.onSave;
    if (callback == null) return;
    setState(() => _saving = true);
    try {
      await callback(EditProfileData(
        name: name, bio: _bio.text.trim(), birthDate: _birth,
        gender: _gender, country: _country, avatarUrl: _avatarUrl,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFFFAEDC8), Colors.white], stops: [0, .35],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              _appBar(),
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: _avatar()),
                  const SizedBox(height: 34),
                  _label('الاسم المستعار'),
                  _box(child: TextField(
                    controller: _name, maxLength: 30,
                    style: const TextStyle(color: _ink, fontSize: 15),
                    decoration: _inputDeco(''),
                  )),
                  const SizedBox(height: 26),
                  _label('النبذة الشخصية'),
                  _box(child: TextField(
                    controller: _bio, maxLength: 100, maxLines: 2,
                    style: const TextStyle(color: _ink, fontSize: 15),
                    decoration: _inputDeco('أدخل توقيعك للتعرف على المزيد من الأصدقاء'),
                  )),
                  const SizedBox(height: 26),
                  _label('العمر'),
                  _box(onTap: _pickDate, chevron: true, child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(alignment: Alignment.centerRight,
                      child: Text(_birth, style: _valueStyle)),
                  )),
                  const SizedBox(height: 26),
                  _label('الجنس', note: '(يمكنك تغيير الجنس مرة واحدة فقط)'),
                  _box(chevron: widget.canChangeGender, onTap: widget.canChangeGender ? () async {
                    final value = await _pick(widget.genders);
                    if (value != null) setState(() => _gender = value);
                  } : null, child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_gender, style: _valueStyle),
                  )),
                  const SizedBox(height: 26),
                  _label('البلد', note: '(يمكنك تغيير الدولة مرة واحدة فقط)'),
                  _box(chevron: widget.canChangeCountry, onTap: widget.canChangeCountry ? () async {
                    final value = await _pick(widget.countries);
                    if (value != null) setState(() => _country = value);
                  } : null, child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(alignment: Alignment.centerRight,
                      child: Text(_country, style: _valueStyle)),
                  )),
                ]),
              )),
              _confirmButton(),
            ]),
          ),
        ),
      ),
    );
  }

  static const _valueStyle = TextStyle(
    color: Color(0xFF4A4A5C), fontSize: 15, fontWeight: FontWeight.w600,
  );

  Widget _appBar() => SizedBox(height: 52, child: Stack(
    alignment: Alignment.center,
    children: [
      const Text('تعديل الملف الشخصي', style: TextStyle(
        color: _ink, fontSize: 18, fontWeight: FontWeight.w800,
      )),
      PositionedDirectional(start: 16, child: GestureDetector(
        onTap: widget.onBack ?? () => Navigator.maybePop(context),
        child: const Icon(Icons.arrow_forward, size: 26, color: Color(0xFF7A7770)),
      )),
    ],
  ));

  Widget _avatar() => GestureDetector(
    onTap: _uploading ? null : _chooseAvatar,
    child: ClipOval(child: SizedBox(width: 80, height: 80,
      child: Stack(fit: StackFit.expand, children: [
        if ((_avatarUrl ?? '').isNotEmpty)
          Image.network(_avatarUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarFallback())
        else _avatarFallback(),
        if (_uploading) const ColoredBox(
          color: Color(0x66000000),
          child: Center(child: CircularProgressIndicator(color: Color(0xFFF0A62B))),
        ),
        const Align(alignment: Alignment.bottomCenter,
          child: Icon(Icons.camera_alt, size: 19, color: Colors.white)),
      ]),
    )),
  );

  Widget _avatarFallback() => Container(
    color: const Color(0xFFE4E4EC),
    child: const Icon(Icons.person, color: Colors.white, size: 36),
  );

  Widget _label(String title, {String? note}) => Padding(
    padding: const EdgeInsets.only(bottom: 10, right: 2),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: title, style: const TextStyle(
        color: _ink, fontSize: 16, fontWeight: FontWeight.w800,
      )),
      if (note != null) TextSpan(text: ' $note', style: const TextStyle(
        color: _grey, fontSize: 14, fontWeight: FontWeight.w400,
      )),
    ])),
  );

  Widget _box({required Widget child, VoidCallback? onTap, bool chevron = false}) =>
    GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Center(child: child)),
          if (chevron) const Icon(Icons.chevron_left, size: 22, color: _grey),
        ]),
      ),
    );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    isCollapsed: true, border: InputBorder.none, counterText: '',
    hintText: hint, hintStyle: const TextStyle(color: Color(0xFFC3C6CF), fontSize: 14),
  );

  Widget _confirmButton() {
    final enabled = _canSave;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      child: GestureDetector(
        onTap: enabled ? () => _confirm() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200), height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF0A62B) : const Color(0xFFE9E7EF),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(_saving ? 'جارٍ الحفظ...' : 'تأكيد', style: TextStyle(
            color: enabled ? Colors.white : const Color(0xFFB7B3C4),
            fontSize: 17, fontWeight: FontWeight.w800,
          )),
        ),
      ),
    );
  }
}
