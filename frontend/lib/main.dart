import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const HappyLiveApp());

class HappyLiveApp extends StatelessWidget {
  const HappyLiveApp({super.key});

  static const background = Color(0xFF09080D);
  static const surface = Color(0xFF17131F);
  static const gold = Color(0xFFE8C477);
  static const purple = Color(0xFF9B63D9);
  static const muted = Color(0xFFAAA2B5);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Live',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: [
        CountryLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: purple,
          surface: surface,
        ),
        useMaterial3: true,
        fontFamily: 'Tajawal',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LoginPage(),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _phoneCountryCodeInput = TextEditingController();
  String _phoneCountryName = 'جار تحديد الدولة...';
  String _phoneCountryCode = '';
  String _phoneCountryFlag = '🌐';
  bool _isSouthArabiaPhone = false;
  bool _isRegister = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _acceptedTerms = false;
  DateTime? _birthDate;
  bool _hasRegisteredOnThisDevice = false;
  bool _isSubmitting = false;
  bool _isRestoringSession = true;
  String? _sessionRestoreError;

  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  static const String _sessionTokenKey = 'happy_live_session_token';
  static const _registeredDeviceKey = 'happy_live_registered_on_device';

  @override
  void initState() {
    super.initState();
    _loadDeviceRegistration();
    _restoreSession();
    _detectPhoneCountryFromIp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(
          const AssetImage('web/assets/south-arabia-v2.png'),
          context,
        );
      }
    });
  }


  // Detect the visitor's country from public IP. Try two providers so one
  // provider outage or rate limit does not leave every visitor on the same country.
  Future<void> _detectPhoneCountryFromIp() async {
    // Temporary QA override: ?testRegion=aden or ?testRegion=sanaa
    final testRegion = Uri.base.queryParameters['testRegion']?.toLowerCase().trim();
    if (testRegion == 'aden') {
      if (!mounted) return;
      setState(() {
        _phoneCountryName = 'الجنوب العربي — عدن (اختبار)';
        _phoneCountryCode = '+969';
        _phoneCountryCodeInput.text = '+969';
        _phoneCountryFlag = '🇾🇪';
        _isSouthArabiaPhone = true;
      });
      return;
    }
    if (testRegion == 'sanaa' || testRegion == 'sana') {
      if (!mounted) return;
      setState(() {
        _phoneCountryName = 'اليمن — صنعاء (اختبار)';
        _phoneCountryCode = '+967';
        _phoneCountryCodeInput.text = '+967';
        _phoneCountryFlag = '🇾🇪';
        _isSouthArabiaPhone = false;
      });
      return;
    }

    // Do not stop at the first provider: it may know the country but omit
    // the governorate. Compare both providers before deciding Yemen's region.
    final results = <Map<String, dynamic>>[];
    final endpoints = <Uri>[
      Uri.https('ipwho.is', ''),
      Uri.https('ipapi.co', 'json/'),
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(endpoint).timeout(const Duration(seconds: 7));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['success'] == false || decoded['error'] == true) continue;
        final code = (decoded['country_code'] ?? decoded['countryCode'] ?? '')
            .toString().trim().toUpperCase();
        if (code.isNotEmpty) results.add(decoded);
      } catch (_) {
        // Continue to the next independent geolocation provider.
      }
    }

    if (results.isEmpty || !mounted) return;

    final isoCodes = results
        .map((item) => (item['country_code'] ?? item['countryCode'] ?? '')
            .toString().trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toList();
    final isoCode = isoCodes.first;

    if (isoCode == 'YE') {
      const southernRegionCodes = <String>{
        'YE-AD', 'YE-AB', 'YE-LA', 'YE-SH',
        'YE-HD', 'YE-MA', 'YE-SU', 'YE-DA',
        'AD', 'AB', 'LA', 'SH', 'HD', 'MA', 'SU', 'DA',
      };
      const southernRegionNames = <String>[
        'aden', 'عدن', 'abyan', 'أبين', 'ابين',
        'lahij', 'lahj', 'lahij governorate', 'لحج',
        'shabwah', 'شبوة',
        'hadramawt', 'hadramout', 'حضرموت',
        'al mahrah', 'al-mahrah', 'mahra', 'المهرة', 'المهره',
        'socotra', 'سقطرى',
        'al dhale', 'al dhalea', 'ad dale', 'aldhale', 'الضالع',
      ];

      var isSouthernYemen = false;
      for (final item in results.where((item) =>
          (item['country_code'] ?? item['countryCode'] ?? '')
              .toString().trim().toUpperCase() == 'YE')) {
        final region = (item['region'] ?? item['region_name'] ??
                item['regionName'] ?? '').toString().toLowerCase().trim();
        final regionCode = (item['region_code'] ?? item['regionCode'] ?? '')
            .toString().toUpperCase().trim();
        final city = (item['city'] ?? '').toString().toLowerCase().trim();
        final subdivision = '$region $city';
        final codeParts = regionCode.split('-');
        final shortRegionCode = codeParts.isNotEmpty ? codeParts.last : regionCode;

        if (southernRegionCodes.contains(regionCode) ||
            southernRegionCodes.contains(shortRegionCode) ||
            southernRegionNames.any((name) =>
                region.contains(name) || subdivision.contains(name))) {
          isSouthernYemen = true;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _phoneCountryName = isSouthernYemen ? 'الجنوب العربي' : 'اليمن';
        _phoneCountryCode = isSouthernYemen ? '+969' : '+967';
        _phoneCountryCodeInput.text = _phoneCountryCode;
        _phoneCountryFlag = '🇾🇪';
        _isSouthArabiaPhone = isSouthernYemen;
      });
      return;
    }

    final country = CountryService().getAll().cast<Country?>().firstWhere(
      (item) => item != null && item.countryCode.toUpperCase() == isoCode,
      orElse: () => null,
    );
    if (country == null || !mounted) return;

    final translatedName = country.getTranslatedName(context) ?? country.name;
    final callingCode = '+${country.phoneCode}';
    setState(() {
      _phoneCountryName = translatedName;
      _phoneCountryCode = callingCode;
      _phoneCountryCodeInput.text = callingCode;
      _phoneCountryFlag = country.flagEmoji;
      _isSouthArabiaPhone = false;
    });
  }

  void _syncPhoneCountryFromCode(String value, StateSetter refreshDialog) {
    // Accept +966, 966, 00966, and values pasted with spaces or punctuation.
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.isEmpty) return;

    if (digits == '969') {
      if (!_isSouthArabiaPhone || _phoneCountryCode != '+969') {
        refreshDialog(() {
          _phoneCountryName = 'الجنوب العربي';
          _phoneCountryCode = '+969';
          _phoneCountryFlag = '🇾🇪';
          _isSouthArabiaPhone = true;
        });
      }
      return;
    }

    final countries = CountryService().getAll();
    final country = countries.cast<Country?>().firstWhere(
      (item) => item != null &&
          item.phoneCode.replaceAll(RegExp(r'[^0-9]'), '') == digits,
      orElse: () => null,
    );
    if (country == null) return;

    final code = '+$digits';
    if (_phoneCountryCode == code && !_isSouthArabiaPhone) return;
    refreshDialog(() {
      _phoneCountryName = country.getTranslatedName(context) ?? country.name;
      _phoneCountryCode = code;
      _phoneCountryFlag = country.flagEmoji;
      _isSouthArabiaPhone = false;
    });
  }

  Future<void> _loadDeviceRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hasRegisteredOnThisDevice = prefs.getBool(_registeredDeviceKey) ?? false;
    });
  }

  // Call this only after the server confirms a successful account registration.
  Future<void> _rememberSuccessfulRegistrationOnThisDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_registeredDeviceKey, true);
    if (mounted) setState(() => _hasRegisteredOnThisDevice = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _phoneNumber.dispose();
    _phoneCountryCodeInput.dispose();
    super.dispose();
  }

  void _showNotConnected() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('طريقة تسجيل الدخول هذه غير مفعلة بعد'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPhoneCountryPicker() {
    _phoneNumber.clear();
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: HappyLiveApp.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFF51415F)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: StatefulBuilder(
                builder: (context, refreshDialog) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'الدخول برقم الهاتف',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: HappyLiveApp.gold,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر رمز الدولة ثم أدخل رقم هاتفك',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HappyLiveApp.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        String searchQuery = '';
                        showModalBottomSheet<void>(
                          context: dialogContext,
                          isScrollControlled: true,
                          backgroundColor: HappyLiveApp.surface,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (countryContext) => StatefulBuilder(
                            builder: (countryContext, refreshCountries) {
                              final countries = CountryService().getAll()
                                ..sort((a, b) => (a.getTranslatedName(countryContext) ?? a.name).compareTo(b.getTranslatedName(countryContext) ?? b.name));
                              final filteredCountries = countries.where((country) {
                                final translated = country.getTranslatedName(countryContext) ?? country.name;
                                final query = searchQuery.trim().toLowerCase();
                                return query.isEmpty || translated.toLowerCase().contains(query) || country.name.toLowerCase().contains(query) || country.phoneCode.contains(query);
                              }).toList();
                              return SafeArea(
                                child: SizedBox(
                                  height: MediaQuery.of(countryContext).size.height * 0.78,
                                  child: Column(children: [
                                    const SizedBox(height: 16),
                                    const Text('اختر الدولة', style: TextStyle(color: HappyLiveApp.gold, fontSize: 18, fontWeight: FontWeight.w900)),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                      child: TextField(
                                        autofocus: true,
                                        textDirection: TextDirection.rtl,
                                        onChanged: (value) => refreshCountries(() => searchQuery = value),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: 'ابحث عن اسم الدولة أو رمزها',
                                          hintStyle: const TextStyle(color: HappyLiveApp.muted),
                                          prefixIcon: const Icon(Icons.search, color: HappyLiveApp.gold),
                                          filled: true, fillColor: const Color(0xFF100D15),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF51415F))),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: filteredCountries.length + 1,
                                        itemBuilder: (countryContext, index) {
                                          if (index == 0) {
                                            final query = searchQuery.trim().toLowerCase();
                                            final matchesSouth = query.isEmpty || 'الجنوب العربي'.contains(query) || '969'.contains(query);
                                            if (!matchesSouth) return const SizedBox.shrink();
                                            return ListTile(
                                              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset('web/assets/south-arabia-v2.png', width: 31, height: 27, cacheWidth: 124, cacheHeight: 108, fit: BoxFit.cover)),
                                              title: const Text('الجنوب العربي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                              onTap: () {
                                                refreshDialog(() {
                                                  _phoneCountryName = 'الجنوب العربي';
                                                  _phoneCountryCode = '+969';
                                                  _phoneCountryCodeInput.text = '+969';
                                                  _phoneCountryFlag = '🇾🇪';
                                                  _isSouthArabiaPhone = true;
                                                });
                                                Navigator.pop(countryContext);
                                              },
                                            );
                                          }
                                          final country = filteredCountries[index - 1];
                                          final translatedName = country.getTranslatedName(countryContext) ?? country.name;
                                          return ListTile(
                                            leading: Text(country.flagEmoji, style: const TextStyle(fontSize: 24)),
                                            title: Text(translatedName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                            onTap: () {
                                              refreshDialog(() {
                                                _phoneCountryName = translatedName;
                                                _phoneCountryCode = '+' + country.phoneCode;
                                                _phoneCountryCodeInput.text = _phoneCountryCode;
                                                _phoneCountryFlag = country.flagEmoji;
                                                _isSouthArabiaPhone = false;
                                              });
                                              Navigator.pop(countryContext);
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFF100D15),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFF51415F)),
                        ),
                        child: Row(
                          children: [
                            _isSouthArabiaPhone
                                ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset('web/assets/south-arabia-v2.png', width: 31, height: 27, cacheWidth: 124, cacheHeight: 108, fit: BoxFit.cover))
                                : Text(_phoneCountryFlag, style: const TextStyle(fontSize: 23)),
                            const SizedBox(width: 11),
                            Expanded(child: Text(_phoneCountryName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: HappyLiveApp.gold),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 112,
                            child: TextField(
                              controller: _phoneCountryCodeInput,
                              keyboardType: TextInputType.number,
                              inputFormatters: [PhoneCodeInputFormatter()],
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              onChanged: (value) => _syncPhoneCountryFromCode(value, refreshDialog),
                              style: const TextStyle(color: HappyLiveApp.gold, fontSize: 16, fontWeight: FontWeight.w900),
                              decoration: InputDecoration(
                                hintText: '+966',
                                hintStyle: const TextStyle(color: HappyLiveApp.muted),
                                filled: true,
                                fillColor: const Color(0xFF100D15),

                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF51415F))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF51415F))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: HappyLiveApp.gold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: TextField(
                              controller: _phoneNumber,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(color: Colors.white, fontSize: 17, letterSpacing: 1),
                              decoration: InputDecoration(
                                hintText: 'رقم الهاتف',
                                hintStyle: const TextStyle(color: HappyLiveApp.muted, fontSize: 14),
                                filled: true,
                                fillColor: const Color(0xFF100D15),
                                prefixIcon: const Icon(Icons.phone_rounded, color: HappyLiveApp.gold, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF51415F))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF51415F))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: HappyLiveApp.gold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF51415F)),
                              minimumSize: const Size.fromHeight(47),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_phoneNumber.text.trim().isEmpty) {
                                _showValidationNotice('أدخل رقم الهاتف أولاً');
                                return;
                              }
                              Navigator.pop(dialogContext);
                              if (_isSouthArabiaPhone) {
                                _showValidationNotice('قريباً ستتم إضافة خدمة الاتصال برمز دولة الجنوب العربي');
                              } else {
                                _showValidationNotice('تم إدخال الرقم، وسيتم تفعيل تسجيل الدخول بالهاتف عند ربط خدمة التحقق');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HappyLiveApp.gold,
                              foregroundColor: const Color(0xFF17131F),
                              minimumSize: const Size.fromHeight(47),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('متابعة', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showValidationNotice(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: HappyLiveApp.gold, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF241B2D),
        elevation: 12,
        duration: const Duration(seconds: 4),
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HappyLiveApp.gold, width: 0.8),
        ),
      ),
    );
  }

  int? _calculatedAge(DateTime birthDate) {
    final today = DateTime.now();
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'اختر تاريخ ميلادك',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _restoreSession() async {
    if (mounted) {
      setState(() {
        _isRestoringSession = true;
        _sessionRestoreError = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_sessionTokenKey);
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _isRestoringSession = false);
        return;
      }

      final response = await http.get(
        Uri.parse('$_apiBase/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>? ?? {};
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SessionHomePage(
              name: (user['name'] ?? '').toString(),
              email: (user['email'] ?? '').toString(),
              userId: (user['id'] ?? '').toString(),
              accessToken: token,
            ),
          ),
        );
        return;
      }

      // Only discard a saved session when the server explicitly says that
      // the token is invalid or expired. Temporary server errors must not log
      // the user out on refresh.
      if (response.statusCode == 401 || response.statusCode == 403) {
        await prefs.remove(_sessionTokenKey);
        if (mounted) setState(() => _isRestoringSession = false);
        return;
      }

      if (mounted) {
        setState(() {
          _sessionRestoreError = 'تعذر التحقق من جلستك الآن. حاول مرة أخرى.';
          _isRestoringSession = false;
        });
      }
    } catch (_) {
      // Keep the saved token and show a retry state if the API is temporarily
      // unreachable, rather than displaying the login form.
      if (mounted) {
        setState(() {
          _sessionRestoreError = 'تعذر الاتصال بالخادم للتحقق من جلستك.';
          _isRestoringSession = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_isRegister && _birthDate == null) {
      _showValidationNotice('يرجى تحديد تاريخ ميلادك');
      return;
    }
    if (_isRegister && _calculatedAge(_birthDate!)! < 18) {
      _showValidationNotice('عذراً، يجب أن يكون عمرك 18 سنة أو أكثر لإنشاء حساب');
      return;
    }
    if (_isRegister && !_acceptedTerms) {
      _showValidationNotice('يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final isRegistering = _isRegister;
      final endpoint = isRegistering ? 'register' : 'login';
      final payload = <String, dynamic>{
        'email': _email.text.trim(),
        'password': _password.text,
      };
      if (isRegistering) {
        final date = _birthDate!;
        payload.addAll({
          'name': _name.text.trim(),
          'birthday': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'acceptedTerms': _acceptedTerms,
        });
      }

      final response = await http.post(
        Uri.parse('$_apiBase/auth/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 25));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode != 200 && response.statusCode != 201) {
        final message = (data['message'] ?? 'تعذر إكمال العملية، حاول مرة أخرى').toString();
        if (mounted) _showValidationNotice(message);
        return;
      }

      final token = (data['accessToken'] ?? '').toString();
      final user = data['user'] as Map<String, dynamic>? ?? {};
      if (token.isEmpty) {
        if (mounted) _showValidationNotice('استلم التطبيق ردًا غير مكتمل من الخادم');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionTokenKey, token);
      if (isRegistering) await _rememberSuccessfulRegistrationOnThisDevice();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionHomePage(
            name: (user['name'] ?? _name.text.trim()).toString(),
            email: (user['email'] ?? _email.text.trim()).toString(),
            userId: (user['id'] ?? '').toString(),
            accessToken: token,
          ),
        ),
      );
    } on http.ClientException {
      if (mounted) _showValidationNotice('تعذر الاتصال بالخادم، تحقق من الإنترنت');
    } catch (_) {
      if (mounted) _showValidationNotice('حدث خطأ أثناء الاتصال، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF81798C), fontSize: 14),
      prefixIcon: Icon(icon, color: HappyLiveApp.gold, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF15121B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFF30283A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: HappyLiveApp.gold, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE36B75)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE36B75)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (_isRestoringSession || _sessionRestoreError != null) {
      return Scaffold(
        backgroundColor: HappyLiveApp.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 28),
                  if (_isRestoringSession) ...[
                    const CircularProgressIndicator(color: HappyLiveApp.gold),
                    const SizedBox(height: 14),
                    const Text(
                      'جارٍ استعادة جلستك...',
                      style: TextStyle(color: HappyLiveApp.muted, fontSize: 13),
                    ),
                  ] else ...[
                    Text(
                      _sessionRestoreError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HappyLiveApp.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _restoreSession,
                      style: FilledButton.styleFrom(
                        backgroundColor: HappyLiveApp.gold,
                        foregroundColor: HappyLiveApp.background,
                      ),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HappyLiveApp.background,
      resizeToAvoidBottomInset: false,
      body: Container(
        color: HappyLiveApp.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
          const Positioned(
            top: -110,
            right: -90,
            child: _GlowOrb(color: Color(0x339B63D9), size: 280),
          ),
          const Positioned(
            bottom: -140,
            left: -100,
            child: _GlowOrb(color: Color(0x22E8C477), size: 300),
          ),
          SafeArea(
            bottom: false,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 28, 24, bottomInset + 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const _BrandHeader(),
                        const SizedBox(height: 34),
                        Text(
                          _isRegister
                              ? 'أنشئ حسابك'
                              : (_hasRegisteredOnThisDevice
                                  ? 'مرحباً بعودتك'
                                  : 'أهلاً بك في Happy Live'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _isRegister
                              ? 'انضم إلى مجتمع Happy Live وابدأ رحلتك'
                              : 'سجّل دخولك وتواصل مع عالمك',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: HappyLiveApp.muted,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 30),
                        if (_isRegister) ...[
                          const _FieldLabel('الاسم'),
                          TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              hint: 'اكتب اسمك',
                              icon: Icons.person_outline_rounded,
                            ),
                            validator: (value) => (value == null || value.trim().isEmpty)
                                ? 'اكتب اسمك'
                                : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                        const _FieldLabel('البريد الإلكتروني'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: _inputDecoration(
                            hint: 'example@email.com',
                            icon: Icons.mail_outline_rounded,
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
                              return 'أدخل بريدًا إلكترونيًا صحيحًا';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('كلمة المرور'),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          textInputAction: _isRegister
                              ? TextInputAction.next
                              : TextInputAction.done,
                          autofillHints: _isRegister
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          decoration: _inputDecoration(
                            hint: 'أدخل كلمة المرور',
                            icon: Icons.lock_outline_rounded,
                            suffix: IconButton(
                              onPressed: () => setState(() => _hidePassword = !_hidePassword),
                              icon: Icon(
                                _hidePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: HappyLiveApp.muted,
                                size: 20,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 8) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                            return null;
                          },
                        ),
                        if (_isRegister) ...[
                          const SizedBox(height: 18),
                          const _FieldLabel('تأكيد كلمة المرور'),
                          TextFormField(
                            controller: _confirmPassword,
                            obscureText: _hideConfirmPassword,
                            textInputAction: TextInputAction.done,
                            decoration: _inputDecoration(
                              hint: 'أعد كتابة كلمة المرور',
                              icon: Icons.lock_reset_rounded,
                              suffix: IconButton(
                                onPressed: () => setState(() => _hideConfirmPassword = !_hideConfirmPassword),
                                icon: Icon(
                                  _hideConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: HappyLiveApp.muted,
                                  size: 20,
                                ),
                              ),
                            ),
                            validator: (value) => value != _password.text
                                ? 'كلمتا المرور غير متطابقتين'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          const _FieldLabel('تاريخ الميلاد'),
                          InkWell(
                            onTap: _pickBirthDate,
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF15121B),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: const Color(0xFF30283A)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month_rounded,
                                      color: HappyLiveApp.gold, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _birthDate == null
                                          ? 'اختر تاريخ ميلادك'
                                          : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                                      style: TextStyle(
                                        color: _birthDate == null
                                            ? const Color(0xFF81798C)
                                            : Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.keyboard_arrow_down_rounded,
                                      color: HappyLiveApp.muted),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: HappyLiveApp.gold,
                            checkColor: HappyLiveApp.background,
                            title: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text('أوافق على ', style: TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
                                InkWell(
                                  onTap: () => _openLegalDocument('terms'),
                                  child: const Text('الشروط والأحكام', style: TextStyle(color: HappyLiveApp.gold, fontSize: 12, decoration: TextDecoration.underline)),
                                ),
                                const Text(' و', style: TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
                                InkWell(
                                  onTap: () => _openLegalDocument('privacy'),
                                  child: const Text('سياسة الخصوصية', style: TextStyle(color: HappyLiveApp.gold, fontSize: 12, decoration: TextDecoration.underline)),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _showResetDialog(context),
                              child: const Text(
                                'نسيت كلمة المرور؟',
                                style: TextStyle(color: HappyLiveApp.gold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              gradient: const LinearGradient(
                                colors: [HappyLiveApp.gold, Color(0xFFC99B4D)],
                              ),
                              boxShadow: const [
                                BoxShadow(color: Color(0x33E8C477), blurRadius: 18, offset: Offset(0, 7)),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: const Color(0xFF171019),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF171019)))
                                  : Text(
                                      _isRegister ? 'إنشاء حساب' : 'تسجيل الدخول',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Color(0xFF393141))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text('أو', style: TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
                            ),
                            Expanded(child: Divider(color: Color(0xFF393141))),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _showNotConnected,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF44394F)),
                              backgroundColor: const Color(0xFF15121B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              foregroundColor: Colors.white,
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('G', style: TextStyle(color: Color(0xFF4285F4), fontSize: 23, fontWeight: FontWeight.w900)),
                                SizedBox(width: 12),
                                Text('سجل الدخول باستخدام Google', style: TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _showNotConnected,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF44394F)),
                                backgroundColor: const Color(0xFF15121B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                foregroundColor: Colors.white,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_iphone_rounded, color: Colors.white, size: 21),
                                  SizedBox(width: 12),
                                  Text('سجل الدخول باستخدام Apple', style: TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Color(0xFF393141))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'طرق تسجيل دخول أخرى',
                                style: TextStyle(color: HappyLiveApp.muted, fontSize: 12),
                              ),
                            ),
                            Expanded(child: Divider(color: Color(0xFF393141))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showPhoneCountryPicker,
                                icon: const Icon(Icons.phone_iphone_rounded, color: HappyLiveApp.gold, size: 25),
                                label: const SizedBox.shrink(),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF44394F)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showNotConnected,
                                icon: const Icon(Icons.badge_outlined, color: HappyLiveApp.gold, size: 19),
                                label: const Text('ID', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.8, color: HappyLiveApp.gold)),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF44394F)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isRegister ? 'لديك حساب بالفعل؟' : 'ليس لديك حساب؟',
                              style: const TextStyle(color: HappyLiveApp.muted, fontSize: 13),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _isRegister = !_isRegister;
                                _formKey.currentState?.reset();
                              }),
                              child: Text(
                                _isRegister ? 'تسجيل الدخول' : 'إنشاء حساب جديد',
                                style: const TextStyle(color: HappyLiveApp.gold, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'HAPPY LIVE  •  عالمك يبدأ هنا',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF706779), fontSize: 10, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  void _openLegalDocument(String type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(type: type),
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    final emailController = TextEditingController(text: _email.text);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        backgroundColor: HappyLiveApp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFF51405F), width: 1),
        ),
        title: const Text(
          'استعادة كلمة المرور',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: HappyLiveApp.gold),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل بريدك الإلكتروني لاستعادة الوصول إلى حسابك',
                textAlign: TextAlign.center,
                style: TextStyle(color: HappyLiveApp.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'البريد الإلكتروني',
                  prefixIcon: const Icon(Icons.mail_outline_rounded, color: HappyLiveApp.gold),
                  filled: true,
                  fillColor: const Color(0xFF100E15),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF51405F)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF51405F)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: HappyLiveApp.gold, width: 1.3),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showNotConnected();
            },
            child: const Text('متابعة'),
          ),
        ],
      ),
    ).whenComplete(emailController.dispose);
  }
}

class SessionHomePage extends StatefulWidget {
  const SessionHomePage({super.key, required this.name, required this.email, required this.userId, required this.accessToken});
  final String name;
  final String email;
  final String userId;
  final String accessToken;
  @override
  State<SessionHomePage> createState() => _SessionHomePageState();
}

class _SessionHomePageState extends State<SessionHomePage> {
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  static const String _sessionTokenKey = 'happy_live_session_token';
  int _tab = 0;
  String get _name => widget.name.trim().isEmpty ? 'عضو Happy Live' : widget.name.trim();
  String get _initial => _name.characters.first.toUpperCase();

  void _soon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature قيد التجهيز وستتوفر قريباً'), behavior: SnackBarBehavior.floating));
  }

  void _openMySidePanel() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _HappyMySpacePage()),
    );
  }

  Future<void> _logout() async {
    try {
      await http.post(Uri.parse('$_apiBase/auth/logout'),
        headers: {'Authorization': 'Bearer ' + widget.accessToken}).timeout(const Duration(seconds: 10));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginPage()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HappyCreateTab(onSoon: _soon),
      HappyHomeTab(name: _name, accessToken: widget.accessToken, onDiscover: () => setState(() => _tab = 2), onSoon: _soon),
      _HappyPlaceholderTab(title: 'اكتشف', subtitle: 'اعثر على مجتمعات واهتمامات جديدة', icon: Icons.explore_outlined, onSoon: _soon),
      const _HappyPlaceholderTab(title: 'الرسائل', subtitle: 'محادثاتك الخاصة في مكان واحد', icon: Icons.forum_outlined),
      HappyProfilePage(name: _name, email: widget.email, userId: widget.userId, initial: _initial, onLogout: _logout, onSoon: _soon),
    ];
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      backgroundColor: HappyLiveApp.background,
      body: SafeArea(child: Column(children: [
        Expanded(child: IndexedStack(index: _tab, children: pages)),
      ])),
      bottomNavigationBar: _HappyLiveBottomNav(
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
      ),
    ));
  }
}

class _HappyMySpacePage extends StatefulWidget {
  const _HappyMySpacePage();

  @override
  State<_HappyMySpacePage> createState() => _HappyMySpacePageState();
}

class _HappyMySpacePageState extends State<_HappyMySpacePage> {
  String _countryName = 'جارٍ تحديد الدولة...';

  @override
  void initState() {
    super.initState();
    _loadCountry();
  }

  Future<void> _loadCountry() async {
    try {
      final response = await http
          .get(Uri.https('ipwho.is', ''))
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) throw Exception('Country lookup failed');
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['success'] == false) {
        throw Exception('Country lookup failed');
      }
      final country = (data['country'] ?? '').toString().trim();
      if (mounted && country.isNotEmpty) {
        setState(() => _countryName = country);
      }
    } catch (_) {
      if (mounted) setState(() => _countryName = 'دولتي');
    }
  }

  Widget _roomButton({
    required IconData icon,
    required String label,
    bool isCountry = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: HappyLiveApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x665F4775)),
      ),
      child: ListTile(
        leading: Icon(icon, color: HappyLiveApp.gold),
        title: Text(label, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w800,
        )),
        trailing: const Icon(Icons.chevron_left_rounded, color: HappyLiveApp.muted),
        onTap: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: HappyLiveApp.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF17121F),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('غرفتي', style: TextStyle(
            color: HappyLiveApp.gold, fontWeight: FontWeight.w900,
          )),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _roomButton(icon: Icons.meeting_room_outlined, label: 'غرفتي'),
              _roomButton(icon: Icons.explore_outlined, label: 'استكشف'),
              _roomButton(
                icon: Icons.public_rounded,
                label: _countryName,
                isCountry: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HappyEmptyState extends StatelessWidget {
  const _HappyEmptyState({required this.icon, required this.title, required this.message});
  final IconData icon; final String title, message;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(20, 25, 20, 25),
    decoration: BoxDecoration(color: HappyLiveApp.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF30263A))),
    child: Column(children: [Icon(icon, color: HappyLiveApp.purple, size: 34), const SizedBox(height: 10),
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      const SizedBox(height: 6), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: HappyLiveApp.muted, fontSize: 11, height: 1.7))]));
}

class _HappyPlaceholderTab extends StatelessWidget {
  const _HappyPlaceholderTab({required this.title, required this.subtitle, required this.icon, this.onSoon});
  final String title, subtitle; final IconData icon; final ValueChanged<String>? onSoon;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
    Text(title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
    const SizedBox(height: 22),
    _HappyEmptyState(icon: icon, title: title == 'الرسائل' ? 'لا توجد محادثات بعد' : 'هذه المساحة قيد التجهيز',
      message: title == 'الرسائل' ? 'ستظهر محادثاتك هنا عند تفعيل نظام الرسائل الخاصة.' : 'نعمل على تجهيز هذه المساحة لتكون جاهزة للاستخدام.'),
    if (onSoon != null) ...[const SizedBox(height: 15), OutlinedButton(onPressed: () => onSoon!(title), child: const Text('معرفة المزيد'))],
  ]);
}

class _HappyCreateTab extends StatelessWidget {
  const _HappyCreateTab({required this.onSoon}); final ValueChanged<String> onSoon;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
    const Text('إنشاء', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5), const Text('شارك لحظاتك مع مجتمع Happy Live', style: TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
    const SizedBox(height: 22),
    _HappyCreateAction(icon: Icons.post_add_rounded, title: 'منشور جديد', subtitle: 'شارك فكرة أو صورة مع المجتمع', onTap: () => onSoon('إنشاء المنشورات')),
    const SizedBox(height: 11),
    _HappyCreateAction(icon: Icons.auto_awesome_motion_rounded, title: 'قصة جديدة', subtitle: 'شارك لحظة قصيرة مع أصدقائك', onTap: () => onSoon('القصص')),
    const SizedBox(height: 11),
    _HappyCreateAction(icon: Icons.mic_rounded, title: 'بدء بث مباشر', subtitle: 'تواصل صوتياً مع الآخرين', onTap: () => onSoon('البث المباشر')),
  ]);
}

class _HappyCreateAction extends StatelessWidget {
  const _HappyCreateAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title, subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17),
    child: Container(padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: HappyLiveApp.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF30263A))),
      child: Row(children: [
        Container(width: 45, height: 45, decoration: BoxDecoration(color: const Color(0xFF352541), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: HappyLiveApp.gold)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: HappyLiveApp.muted, fontSize: 11)),
        ])),
        const Icon(Icons.chevron_left_rounded, color: HappyLiveApp.muted),
      ])));
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF3B2450), Color(0xFF17121F)],
            ),
            border: Border.all(color: const Color(0x99E8C477), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x449B63D9), blurRadius: 28, spreadRadius: 2),
            ],
          ),
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, 10),
              child: const Text(
                'H',
                style: TextStyle(
                  fontSize: 66,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: HappyLiveApp.gold,
                  shadows: [Shadow(color: HappyLiveApp.purple, blurRadius: 16)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'HAPPY LIVE',
          style: TextStyle(
            color: HappyLiveApp.gold,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'عالمك الاجتماعي في مكان واحد',
          style: TextStyle(color: HappyLiveApp.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(label, style: const TextStyle(color: Color(0xFFE9E3EF), fontSize: 13, fontWeight: FontWeight.w700)),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const Text(
    'G',
    style: TextStyle(color: Color(0xFF4285F4), fontSize: 21, fontWeight: FontWeight.w900),
  );
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 30)],
      ),
    ),
  );
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.type});

  final String type;

  bool get isPrivacy => type == 'privacy';

  static const _terms = <(String, String)>[
    ('1. الأهلية والعمر', 'خدمة Happy Live مخصصة للأشخاص الذين تبلغ أعمارهم 18 سنة أو أكثر. بإنشاء الحساب، تقر وتؤكد أنك بلغت هذا العمر، وتتعهد بتقديم معلومات صحيحة. لا يسمح للقاصرين بإنشاء حساب أو استخدام الخدمة.'),
    ('2. الحساب وأمانه', 'أنت مسؤول عن سرية بيانات الدخول وعن جميع الأنشطة التي تتم عبر حسابك. يجب عدم مشاركة كلمة المرور أو رموز التحقق، وإبلاغ فريق الدعم عند الاشتباه في استخدام غير مصرح به. يحق لنا طلب التحقق من المعلومات أو تعليق الحساب عند وجود مؤشرات معقولة على إساءة الاستخدام.'),
    ('3. السلوك والمحتوى', 'تتعهد بعدم نشر أو إرسال محتوى غير قانوني أو تهديدي أو تشهيري أو مضلل أو ينتهك حقوق الآخرين، أو يتضمن استغلالًا أو تحرشًا أو كراهية أو احتيالًا أو انتهاكًا للخصوصية أو حقوق الملكية الفكرية. كما يمنع انتحال الشخصيات أو استخدام الخدمة للإزعاج أو الإضرار بالآخرين.'),
    ('4. المحتوى الذي تنشره', 'تحتفظ بملكية المحتوى الذي تنشئه، وتمنح Happy Live ترخيصًا محدودًا وغير حصري لاستضافته وعرضه ومعالجته بالقدر اللازم لتشغيل الخدمة وتقديم ميزاتها. أنت مسؤول عن امتلاك الحقوق والأذونات اللازمة لأي محتوى تنشره.'),
    ('5. الإشراف والإبلاغ', 'يمكنك الإبلاغ عن المحتوى أو الحسابات المخالفة. ويجوز لنا مراجعة البلاغات واتخاذ إجراءات مناسبة، مثل إزالة المحتوى أو تقييد بعض الميزات أو تعليق الحساب أو إغلاقه، مع مراعاة الأنظمة المعمول بها. لا نضمن اكتشاف كل مخالفة أو منعها فورًا.'),
    ('6. الاستخدامات المحظورة', 'يمنع استخدام الخدمة لنشر البرمجيات الضارة أو الاحتيال أو التهديد أو المضايقة أو جمع بيانات الآخرين دون إذن أو محاولة اختراق الخدمة أو تعطيلها أو التحايل على أنظمتها أو بيع الحسابات أو إساءة استخدام ميزات البث والتواصل.'),
    ('7. توفر الخدمة والتعديلات', 'قد تتغير الميزات أو تتوقف مؤقتًا لأسباب تقنية أو أمنية أو تشغيلية. ونسعى إلى تحسين الخدمة، لكننا لا نضمن عملها دون انقطاع أو خلوها من الأخطاء. قد نحدّث هذه الشروط عند تطوير الخدمة أو عند الحاجة النظامية.'),
    ('8. الإيقاف وإنهاء الحساب', 'يجوز تقييد الحساب أو تعليقه أو إنهاؤه عند مخالفة هذه الشروط أو الإضرار بالمستخدمين أو بالخدمة أو عند وجود التزام نظامي. ويمكنك التوقف عن استخدام الخدمة وطلب حذف حسابك عبر قنوات الدعم المتاحة عند إطلاقها.'),
    ('9. حدود المسؤولية', 'إلى الحد الذي تسمح به الأنظمة، لا تتحمل Happy Live مسؤولية الأضرار الناتجة عن تصرفات المستخدمين أو المحتوى الذي ينشرونه أو انقطاع خارج عن السيطرة المعقولة. ولا يحد ذلك من أي حقوق أو مسؤوليات لا يجوز استبعادها بموجب النظام.'),
    ('10. القانون والتواصل', 'تخضع هذه الشروط للأنظمة المعمول بها في المملكة العربية السعودية، وتختص الجهات القضائية المختصة بالنظر في النزاعات وفقًا لتلك الأنظمة. عند إطلاق قنوات الدعم الرسمية، سيتم نشر بيانات التواصل داخل التطبيق أو على موقعه.'),
  ];

  static const _privacy = <(String, String)>[
    ('1. نطاق السياسة', 'توضح هذه السياسة كيفية تعامل Happy Live مع المعلومات عند إنشاء الحساب واستخدام ميزات التطبيق. قد تتغير التفاصيل مع إضافة ميزات جديدة أو ربط مزودي خدمات، وسنحدّث هذه الصفحة عند حدوث تغييرات جوهرية.'),
    ('2. المعلومات التي قد نجمعها', 'قد تشمل المعلومات التي تقدمها مباشرة: الاسم والبريد الإلكتروني وتاريخ الميلاد وصورة الملف الشخصي والنبذة والبلد ومعلومات الحساب. وقد تشمل المعلومات التي تنشأ أثناء الاستخدام: المنشورات والتعليقات والرسائل والبلاغات والتفاعلات وسجلات الأمان والدعم.'),
    ('3. معلومات تقنية', 'قد تُعالج معلومات تقنية لازمة لتشغيل الخدمة وحمايتها، مثل نوع الجهاز والمتصفح وعنوان الشبكة وسجلات الأعطال ووقت الدخول ومعلومات الأداء. ويقتصر ذلك على ما يلزم للأغراض الموضحة في هذه السياسة وبما تسمح به الأنظمة.'),
    ('4. كيف نستخدم المعلومات', 'نستخدم المعلومات لإنشاء الحساب وإدارته، وتشغيل ميزات التواصل والمحتوى، وتخصيص التجربة، وتقديم الدعم، والتحقق من الأمان، واكتشاف الاحتيال والإساءة، وتحسين الأداء، والامتثال للمتطلبات النظامية.'),
    ('5. ما يراه الآخرون', 'قد تكون بعض معلومات الملف الشخصي والمنشورات والتعليقات والتفاعلات مرئية للمستخدمين الآخرين بحسب إعدادات وميزات التطبيق. الرسائل الخاصة مخصصة لأطراف المحادثة، لكن لا ينبغي اعتبار أي وسيلة اتصال رقمية ضمانًا مطلقًا للسرية؛ فقد نحتاج إلى معالجة بيانات محدودة لأسباب أمنية أو نظامية.'),
    ('6. مشاركة المعلومات', 'لا نبيع المعلومات الشخصية. وقد تتم مشاركة الحد الأدنى اللازم مع مزودي الاستضافة والتشغيل والتخزين والأمان أو مزودي الخدمات الذين يساعدون في تشغيل Happy Live، أو مع الجهات المختصة عندما يوجب النظام ذلك، أو لحماية حقوق وسلامة المستخدمين والخدمة.'),
    ('7. التخزين والحماية', 'نتخذ تدابير إدارية وتقنية معقولة لحماية المعلومات من الوصول أو الاستخدام أو التغيير غير المصرح به. لا توجد وسيلة نقل أو تخزين آمنة بصورة مطلقة، لذلك لا يمكن ضمان الأمان الكامل. تختلف مدة الاحتفاظ بحسب نوع البيانات والغرض منها والمتطلبات النظامية.'),
    ('8. ملفات تعريف الارتباط والتقنيات المشابهة', 'قد يستخدم إصدار الويب التخزين المحلي أو تقنيات مشابهة لحفظ تفضيلات أساسية وحالة الاستخدام وتحسين الأداء. يمكنك إدارة بيانات الموقع من إعدادات المتصفح، وقد يؤثر حذفها في بعض الوظائف.'),
    ('9. حقوقك وطلباتك', 'يمكنك طلب الوصول إلى معلوماتك أو تصحيحها أو تحديثها أو حذف حسابك، أو تقديم اعتراض أو شكوى، وفق الحقوق والإجراءات التي تقررها الأنظمة المعمول بها. سنوفر قناة تواصل مخصصة لهذه الطلبات عند إطلاق الخدمة رسميًا.'),
    ('10. خصوصية من هم دون 18 عامًا', 'Happy Live غير موجه للقاصرين ولا يسمح باستخدامه لمن هم دون 18 عامًا. إذا علمنا أن حسابًا يعود إلى شخص دون هذا العمر، فقد نتخذ إجراءات لتعطيله وحذف المعلومات المرتبطة به وفق المتطلبات النظامية.'),
    ('11. التغييرات والتواصل', 'قد نحدّث سياسة الخصوصية عند تغير طريقة عمل التطبيق أو المتطلبات النظامية. سنعرض تاريخ آخر تحديث وننبه المستخدمين إلى التغييرات الجوهرية عبر التطبيق متى كان ذلك مناسبًا.'),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = isPrivacy ? _privacy : _terms;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: HappyLiveApp.background,
        appBar: AppBar(
          backgroundColor: HappyLiveApp.background,
          foregroundColor: HappyLiveApp.gold,
          title: Text(isPrivacy ? 'سياسة الخصوصية' : 'الشروط والأحكام'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: HappyLiveApp.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x66513E65)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.verified_user_outlined, color: HappyLiveApp.gold, size: 30),
                    const SizedBox(height: 10),
                    Text(
                      isPrivacy ? 'خصوصيتك مهمة لنا' : 'مرحبًا بك في Happy Live',
                      style: const TextStyle(color: HappyLiveApp.gold, fontSize: 19, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      isPrivacy
                          ? 'اقرأ كيف نتعامل مع معلوماتك عند استخدام التطبيق.'
                          : 'باستخدامك للتطبيق، فإنك توافق على الالتزام بهذه الشروط.',
                      style: const TextStyle(color: HappyLiveApp.muted, fontSize: 13, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ...sections.map((section) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.$1, style: const TextStyle(color: HappyLiveApp.gold, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    Text(section.$2, style: const TextStyle(color: Color(0xFFE2DCE8), fontSize: 14, height: 1.85)),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              const Text(
                'هذه صياغة أولية عامة، ويجب مراجعتها قانونيًا قبل الإطلاق الرسمي، خصوصًا بعد تحديد مزودي الخدمة وآليات جمع البيانات الفعلية.',
                style: TextStyle(color: HappyLiveApp.muted, fontSize: 12, height: 1.7),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the calling-code field to a '+' prefix and at most three digits.
class PhoneCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 3 ? digits.substring(0, 3) : digits;
    if (limitedDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final formatted = '+$limitedDigits';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _HappyLiveBottomNav extends StatefulWidget {
  const _HappyLiveBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<_HappyLiveBottomNav> createState() => _HappyLiveBottomNavState();
}

class _HappyLiveBottomNavState extends State<_HappyLiveBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Page indexes are unchanged; all five navigation items stay mounted.
  static const items = <(int, IconData, String)>[
    (4, Icons.person_outline, 'الخاص بي'),
    (3, Icons.chat_bubble_outline_rounded, 'الرسائل'),
    (2, Icons.article_outlined, 'المنشورات'),
    (1, Icons.bed_outlined, 'غرفة'),
    (0, Icons.wifi_tethering_outlined, 'Happy Live'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0912),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF191326),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF302344),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _buildItem(
                    index: item.$1,
                    icon: item.$2,
                    label: item.$3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = widget.currentIndex == index;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0x2E8B5CF6) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            icon,
            size: 23,
            color: active
                ? const Color(0xFFB58AFF)
                : const Color(0xFFA49AAF),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? Colors.white : const Color(0xFFA49AAF),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Keep the same CustomPaint/child structure for active and inactive tabs.
    // Only the painter changes, so selecting a tab cannot remove neighboring items.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(index),
      child: CustomPaint(
        foregroundPainter: active
            ? ActiveBorderPainter(animation: _ctrl)
            : null,
        child: content,
      ),
    );
  }
}

class ActiveBorderPainter extends CustomPainter {
  ActiveBorderPainter({required this.animation})
      : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      const Radius.circular(18),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF8B5CF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
    );

    final metrics = (Path()..addRRect(rrect)).computeMetrics();
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final progress = animation.value.clamp(0.0, 1.0).toDouble();
      final tangent = metric.getTangentForOffset(metric.length * progress);

      if (tangent != null) {
        final position = tangent.position;
        canvas.drawCircle(
          position,
          12,
          Paint()
            ..shader = const RadialGradient(
              colors: [
                Color(0xF2B58AFF),
                Color(0x738B5CF6),
                Color(0x008B5CF6),
              ],
              stops: [0.0, 0.45, 1.0],
            ).createShader(
              Rect.fromCircle(center: position, radius: 12),
            ),
        );
        canvas.drawCircle(
          position,
          2.5,
          Paint()..color = Colors.white,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ActiveBorderPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
