import 'dart:convert';
import '../widgets/centered_notification.dart';
import 'package:flutter/material.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import 'package:happy_live/widgets/square_country_flag.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';

const _ink = Color(0xFF1E2233);
const _grey = Color(0xFF8E8CA0);
const _fieldBg = Color(0xFFF2F4F6);

const List<String> _countryEntries = [
  'SOUTH_ARABIA|South Arabia|الجنوب العربي',
  '🇰🇼|Kuwait|الكويت',
  '🇦🇪|United Arab Emirates|الإمارات العربية المتحدة',
  '🇶🇦|Qatar|قطر',
  '🇲🇦|Morocco|المغرب',
  '🇪🇬|Egypt|مصر',
  '🇸🇾|Syria|سوريا',
  '🇹🇷|Turkey|تركيا',
  '🇩🇿|Algeria|الجزائر',
  '🇧🇭|Bahrain|البحرين',
  '🇮🇶|Iraq|العراق',
  '🇯🇴|Jordan|الأردن',
  '🇱🇧|Lebanon|لبنان',
  '🇴🇲|Oman|عُمان',
  '🇵🇰|Pakistan|باكستان',
  '🇵🇸|Palestine|فلسطين',
  '🇸🇩|Sudan|السودان',
  '🇾🇪|Yemen|اليمن',
  '🇸🇦|Saudi Arabia|السعودية',
];

String _countryFlag(String name) {
  final value = name.trim();
  if (value == 'دولة الجنوب العربي' || value == 'الجنوب العربي' ||
      value == 'South Arabia') return 'SOUTH_ARABIA';
  for (final entry in _countryEntries) {
    final parts = entry.split('|');
    if (parts.length == 3 && (parts[1] == value || parts[2] == value)) {
      return parts[0];
    }
  }
  return '';
}

String countryFlagForProfileName(String name) => _countryFlag(name);

String _countryArabicName(String name) {
  final value = name.trim();
  if (value == 'دولة الجنوب العربي' || value == 'الجنوب العربي') {
    return 'الجنوب العربي';
  }
  for (final entry in _countryEntries) {
    final parts = entry.split('|');
    if (parts.length == 3 && (parts[1] == value || parts[2] == value)) {
      return parts[2];
    }
  }
  return value;
}

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
    this.countries = const [],
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
    if (mounted) showCenteredNotification(context, 
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _chooseAvatar() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 42, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD8D8DE),
                    borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 16),
                _avatarPickerOption(sheetContext, 'gif', 'GIF', Icons.gif_box_outlined),
                _avatarPickerOption(sheetContext, 'album', 'البوم الهاتف', Icons.photo_library_outlined),
                _avatarPickerOption(sheetContext, 'camera', 'التقاط الصور', Icons.camera_alt_outlined),
                const SizedBox(height: 4),
                SizedBox(width: double.infinity, child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                  child: const Text('الغاء', style: TextStyle(
                    color: Color(0xFF777482), fontSize: 16, fontWeight: FontWeight.w700)),
                )),
              ],
            ),
          ),
        ),
      ),
    );

    if (choice == null || choice == 'cancel') return;
    if (choice == 'gif') {
      await _pickAvatarGif();
    } else {
      await _pickAvatarImage(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Widget _avatarPickerOption(BuildContext sheetContext, String value, String title, IconData icon) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon, color: const Color(0xFFD99B25), size: 25),
        title: Text(title, style: const TextStyle(
          color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
        onTap: () => Navigator.pop(sheetContext, value),
      );

  // Force uploaded GIF avatars to repeat forever, even when the source GIF
  // was authored with a finite loop count or without a loop extension.
  List<int> _forceGifInfiniteLoop(List<int> source) {
    final bytes = List<int>.from(source);
    if (bytes.length < 13) return bytes;
    final signature = String.fromCharCodes(bytes.take(6));
    if (signature != 'GIF87a' && signature != 'GIF89a') return bytes;

    const marker = 'NETSCAPE2.0';
    final markerBytes = marker.codeUnits;
    for (var i = 0; i <= bytes.length - markerBytes.length - 9; i++) {
      var matches = true;
      for (var j = 0; j < markerBytes.length; j++) {
        if (bytes[i + j] != markerBytes[j]) {
          matches = false;
          break;
        }
      }
      if (matches && i + 14 < bytes.length &&
          bytes[i + 11] == 0x03 && bytes[i + 12] == 0x01) {
        // A loop count of zero means infinite repetition.
        bytes[i + 13] = 0;
        bytes[i + 14] = 0;
        return bytes;
      }
    }

    // Add the standard looping application extension after the global
    // color table (if present), before the first frame/extension block.
    final packed = bytes[10];
    var insertAt = 13;
    if ((packed & 0x80) != 0) {
      insertAt += 3 * (1 << ((packed & 0x07) + 1));
    }
    if (insertAt > bytes.length) return bytes;
    final loopExtension = <int>[
      0x21, 0xFF, 0x0B,
      ...markerBytes,
      0x03, 0x01, 0x00, 0x00, 0x00,
    ];
    bytes.insertAll(insertAt, loopExtension);
    return bytes;
  }

  Future<void> _pickAvatarGif() async {
    try {
      final selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gif'],
        withData: true,
      );
      if (selected == null || selected.files.isEmpty) return;
      final file = selected.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _message('تعذر قراءة ملف GIF من الجهاز');
        return;
      }
      final loopingGif = _forceGifInfiniteLoop(bytes);
      await _uploadAvatar(loopingGif, 'happy-avatar-${DateTime.now().millisecondsSinceEpoch}.gif');
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickAvatarImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
      );
      if (file == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        maxWidth: 1200,
        maxHeight: 1200,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'قص الصورة',
            toolbarColor: const Color(0xFF171321),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFFF0A62B),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'قص الصورة',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
            dragMode: WebDragMode.move,
            initialAspectRatio: 1,
            guides: true,
            center: true,
            cropBoxMovable: true,
            cropBoxResizable: false,
            movable: true,
            zoomable: true,
            zoomOnTouch: true,
            zoomOnWheel: true,
            rotatable: true,
          ),
        ],
      );
      if (cropped == null) return;
      await _uploadAvatar(await cropped.readAsBytes(),
        'happy-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg');
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _uploadAvatar(List<int> bytes, String fileName) async {
    if (mounted) setState(() => _uploading = true);
    try {
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
        'fileName': fileName,
        'publicKey': credentials['publicKey'].toString(),
        'signature': credentials['signature'].toString(),
        'token': credentials['token'].toString(),
        'expire': credentials['expire'].toString(),
        'folder': '/happy-live/avatars',
        'useUniqueFileName': 'true',
      });
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes, filename: fileName,
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
      _message(fileName.toLowerCase().endsWith('.gif')
          ? 'تم رفع صورة GIF المتحركة بنجاح'
          : 'تم رفع الصورة بنجاح');
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

  Future<String?> _pickCountry() async {
    return showModalBottomSheet<String>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(builder: (context, setSheetState) {
          final filtered = _countryEntries.where((entry) {
            final parts = entry.split('|');
            return parts.length == 3 && (parts[1].toLowerCase().contains(query.trim().toLowerCase()) || parts[2].contains(query.trim()));
          }).toList()
            ..sort((a, b) {
              if (a.startsWith('SOUTH_ARABIA|')) return -1;
              if (b.startsWith('SOUTH_ARABIA|')) return 1;
              return a.split('|')[1].compareTo(b.split('|')[1]);
            });
          return Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * .78,
                child: Column(children: [
                  const SizedBox(height: 14),
                  Container(width: 42, height: 4, decoration: BoxDecoration(
                    color: const Color(0xFFD8D8DE), borderRadius: BorderRadius.circular(8))),
                  const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Align(alignment: Alignment.centerRight, child: Text(
                      'اختر البلد', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: const TextStyle(color: Colors.black),
                      cursorColor: Colors.black,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن دولة',
                        hintStyle: const TextStyle(color: Colors.black),
                        prefixIcon: const Icon(Icons.search),
                        filled: true, fillColor: _fieldBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    )),
                  const SizedBox(height: 8),
                  Expanded(child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final parts = filtered[index].split('|');
                      final flag = parts[0], name = parts[2];
                      return ListTile(
                        leading: SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Center(
                                child: flag == 'SOUTH_ARABIA'
                                    ? SquareCountryFlag('SOUTH_ARABIA', size: 24)
                                    : SquareCountryFlag(flag, size: 24),
                              ),
                            ),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 15, color: _ink)),
                        onTap: () => Navigator.pop(sheetContext, parts[1]),
                      );
                    },
                  )),
                ]),
              ),
            ),
          );
        });
      },
    );
  }

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
                    final value = await _pickCountry();
                    if (value != null) setState(() => _country = value);
                  } : null, child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Align(alignment: Alignment.centerRight,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Center(
                            child: _countryFlag(_country) == 'SOUTH_ARABIA'
                                ? SquareCountryFlag('SOUTH_ARABIA', size: 24)
                                : SquareCountryFlag(_countryFlag(_country), size: 24),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_countryArabicName(_country), style: _valueStyle),
                      ])),
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
          HappyNetworkImage(_avatarUrl!, fit: BoxFit.cover,
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
