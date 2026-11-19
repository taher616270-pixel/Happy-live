import 'package:flutter/material.dart';
import 'package:happy_live/widgets/square_country_flag.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/posts_page.dart';
import 'pages/edit_profile_page.dart';
import 'widgets/dynamic_games_list.dart';
import 'pages/wallet_page.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'dart:async';
import 'widgets/custom_bottom_nav.dart';
import 'widgets/purple_tech_background.dart';
import 'services/session_token_store.dart';
import 'services/global_gift_events.dart';
import 'widgets/global_gift_banner.dart';
import 'cannon/cannon_config.dart';
import 'cannon/cannon_top_banner.dart';
import 'pages/room_page.dart';

Future<void> _openGlobalCannonRoom(BuildContext context, String targetRoomId) async {
  final id = targetRoomId.trim();
  final token = CannonConfig.authToken();
  if (id.isEmpty || token.isEmpty) return;
  try {
    final response = await http.get(
      Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/rooms/${Uri.encodeComponent(id)}/seats'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 12));
    final payload = jsonDecode(response.body);
    if (response.statusCode != 200 || payload is! Map || payload['room'] is! Map) return;
    final room = Map<String, dynamic>.from(payload['room'] as Map);
    room['id'] ??= id;
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => RoomPage(room: room, accessToken: token)),
    );
  } catch (_) {
    // Keep the banner non-blocking if the target room is temporarily unavailable.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Happy Live is a portrait-first social app on Android phones.
  // Keep the web experience and other platforms unchanged.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    // Android only: use the entire display and hide the status/navigation bars.
    // The bars can be temporarily revealed with a system swipe (immersive sticky).
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF09080D),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Color(0xFF09080D),
      ),
    );
  }

  runApp(const HappyLiveApp());
}

class HappyLiveApp extends StatelessWidget {
  const HappyLiveApp({super.key});

  static const background = Color(0xFF09080D);
  static const surface = Color(0xFF17131F);
  static const gold = Color(0xFFE8C477);
  static const purple = Color(0xFFD9A93C);
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
      builder: (context, child) => CannonGlobalBannerHost(
        accessToken: CannonConfig.authToken(),
        onOpenRoom: (roomId) => _openGlobalCannonRoom(context, roomId),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: PurpleTechBackground()),
            if (child != null) child,
            Positioned.fill(
              child: GiftBannerHost(stream: GlobalGiftEvents.instance.events),
            ),
          ],
        ),
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
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
  bool _hasRegisteredOnThisDevice = false;
  bool _isSubmitting = false;
  bool _isRestoringSession = true;
  String? _sessionRestoreError;

  static const String _apiBase = const String.fromEnvironment('HAPPY_LIVE_API_BASE', defaultValue: 'https://happy-live-api.taher616270.workers.dev/api/v1');
  static const String _googleClientId = '999298541545-5i0kn2d1emj2rohuvruj4o8ej49ho9kg.apps.googleusercontent.com';
  static const _registeredDeviceKey = 'happy_live_registered_on_device';
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _googleClientId : null,
    serverClientId: kIsWeb ? null : _googleClientId,
    scopes: const ['email', 'profile'],
  );

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

  Future<bool> _confirmGoogleTerms() async {
    var accepted = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          backgroundColor: const Color(0xFFFAF6EA),
          title: const Text(
            'تأكيد إنشاء الحساب',
            style: TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'إذا لم يكن لديك حساب في Happy Live، فسيتم إنشاء حساب جديد باستخدام بريد Google. يجب أن يكون عمرك 18 سنة أو أكثر.',
                style: TextStyle(color: Color(0xFF555568), height: 1.6),
                textAlign: TextAlign.center,
              ),
              CheckboxListTile(
                value: accepted,
                onChanged: (value) => refreshDialog(() => accepted = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFFC99B4D),
                title: const Text(
                  'أؤكد أن عمري 18 سنة أو أكثر وأوافق على الشروط وسياسة الخصوصية',
                  style: TextStyle(color: Color(0xFF1E2233), fontSize: 12, height: 1.4),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).push(
                      MaterialPageRoute<void>(builder: (_) => const LegalDocumentPage(type: 'terms')),
                    ),
                    child: const Text('الشروط والأحكام'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).push(
                      MaterialPageRoute<void>(builder: (_) => const LegalDocumentPage(type: 'privacy')),
                    ),
                    child: const Text('سياسة الخصوصية'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: accepted ? () => Navigator.pop(dialogContext, true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9A93C),
                foregroundColor: const Color(0xFF1E2233),
              ),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _signInWithGoogle() async {
    if (_isSubmitting) return;
    final acceptedTerms = await _confirmGoogleTerms();
    if (!acceptedTerms || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return;

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        _showValidationNotice('لم نستلم رمز التحقق من Google. حاول مرة أخرى.');
        return;
      }

      final response = await http.post(
        Uri.parse('$_apiBase/auth/google'),
        // Use a CORS-safelisted content type to avoid a browser OPTIONS preflight.
        // The Worker parses the JSON body directly and does not depend on this header.
        headers: {'Content-Type': 'text/plain;charset=UTF-8'},
        body: jsonEncode({'idToken': idToken, 'acceptedTerms': true}),
      ).timeout(const Duration(seconds: 25));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode != 200) {
        _showValidationNotice((data['message'] ?? 'تعذر تسجيل الدخول باستخدام Google').toString());
        return;
      }

      final token = (data['accessToken'] ?? '').toString();
      final user = data['user'] as Map<String, dynamic>? ?? {};
      if (token.isEmpty) {
        _showValidationNotice('استلم التطبيق ردًا غير مكتمل من الخادم');
        return;
      }

      await SessionTokenStore.write(token);
      await SessionTokenStore.writeUser(jsonEncode(user));
      await SessionTokenStore.writeTab(0);
      if (data['isNewUser'] == true) await _rememberSuccessfulRegistrationOnThisDevice();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionHomePage(
            name: (user['name'] ?? account.displayName ?? '').toString(),
            email: (user['email'] ?? account.email).toString(),
            userId: (user['happy_id'] ?? user['gabo_id'] ?? user['id'] ?? '').toString(),
            accessToken: token,
          ),
        ),
      );
    } on http.ClientException {
      if (mounted) _showValidationNotice('تعذر الاتصال بالخادم، تحقق من الإنترنت');
    } catch (_) {
      if (mounted) _showValidationNotice('تعذر إكمال تسجيل الدخول عبر Google. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
          backgroundColor: const Color(0xFF1E2233),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE4E4EC)),
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
                      style: TextStyle(color: const Color(0xFF8B899A), fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        String searchQuery = '';
                        showModalBottomSheet<void>(
                          context: dialogContext,
                          isScrollControlled: true,
                          backgroundColor: const Color(0xFF1E2233),
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
                                        style: const TextStyle(color: const Color(0xFF1E2233)),
                                        decoration: InputDecoration(
                                          hintText: 'ابحث عن اسم الدولة أو رمزها',
                                          hintStyle: const TextStyle(color: const Color(0xFF8B899A)),
                                          prefixIcon: const Icon(Icons.search, color: HappyLiveApp.gold),
                                          filled: true, fillColor: const Color(0xFFFAF6EA),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
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
                                              leading: SizedBox(width: 32, height: 32, child: Center(child: SizedBox(width: 24, height: 24, child: SquareCountryFlag('SOUTH_ARABIA', size: 24)))),
                                              title: const Text('الجنوب العربي', style: TextStyle(color: const Color(0xFF1E2233), fontWeight: FontWeight.w800)),
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
                                            leading: SizedBox(width: 32, height: 32, child: Center(child: SizedBox(width: 24, height: 24, child: Center(child: SquareCountryFlag(country.flagEmoji, size: 24))))),
                                            title: Text(translatedName, style: const TextStyle(color: const Color(0xFF1E2233), fontWeight: FontWeight.w700)),
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
                          color: const Color(0xFFFAF6EA),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFE4E4EC)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Center(
                                child: _isSouthArabiaPhone
                                    ? SquareCountryFlag('SOUTH_ARABIA', size: 24)
                                    : SquareCountryFlag(_phoneCountryFlag, size: 24),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(child: Text(_phoneCountryName, style: const TextStyle(color: const Color(0xFF1E2233), fontWeight: FontWeight.w700))),
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
                                hintStyle: const TextStyle(color: const Color(0xFF8B899A)),
                                filled: true,
                                fillColor: const Color(0xFFFAF6EA),

                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
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
                              style: const TextStyle(color: const Color(0xFF1E2233), fontSize: 17, letterSpacing: 1),
                              decoration: InputDecoration(
                                hintText: 'رقم الهاتف',
                                hintStyle: const TextStyle(color: const Color(0xFF8B899A), fontSize: 14),
                                filled: true,
                                fillColor: const Color(0xFFFAF6EA),
                                prefixIcon: const Icon(Icons.phone_rounded, color: HappyLiveApp.gold, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
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
                              foregroundColor: const Color(0xFF8B899A),
                              side: const BorderSide(color: Color(0xFFE4E4EC)),
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
                              foregroundColor: const Color(0xFFFFFFFF),
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
        backgroundColor: const Color(0xFF292B3A),
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

  Future<void> _restoreSession() async {
    if (mounted) {
      setState(() {
        _isRestoringSession = true;
        _sessionRestoreError = null;
      });
    }
    try {
      final token = await SessionTokenStore.read();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _isRestoringSession = false);
        return;
      }

      // Open the last screen immediately from the browser's local snapshot.
      // The server still validates the token before any protected operation.
      final cachedUserJson = await SessionTokenStore.readUser();
      if (cachedUserJson != null && cachedUserJson.isNotEmpty) {
        try {
          final user = jsonDecode(cachedUserJson) as Map<String, dynamic>;
          final selectedTab = (await SessionTokenStore.readTab()).clamp(0, 4).toInt();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => SessionHomePage(
                name: (user['name'] ?? '').toString(),
                email: (user['email'] ?? '').toString(),
                userId: (user['happy_id'] ?? user['gabo_id'] ?? user['id'] ?? '').toString(),
                accessToken: token,
                initialIndex: selectedTab,
              ),
            ),
          );
          return;
        } catch (_) {
          // A damaged local snapshot falls back to the server session check.
        }
      }

      // First restoration after this update, or missing cached profile:
      // verify once and save a local snapshot for future instant restores.
      final response = await http.get(
        Uri.parse('$_apiBase/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>? ?? {};
        await SessionTokenStore.writeUser(jsonEncode(user));
        final selectedTab = (await SessionTokenStore.readTab()).clamp(0, 4).toInt();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SessionHomePage(
              name: (user['name'] ?? '').toString(),
              email: (user['email'] ?? '').toString(),
              userId: (user['happy_id'] ?? user['gabo_id'] ?? user['id'] ?? '').toString(),
              accessToken: token,
              initialIndex: selectedTab,
            ),
          ),
        );
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await SessionTokenStore.clear();
        await SessionTokenStore.writeUser('');
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
        payload.addAll({
          'name': _name.text.trim(),
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

      await SessionTokenStore.write(token);
      await SessionTokenStore.writeUser(jsonEncode(user));
      await SessionTokenStore.writeTab(0);
      if (isRegistering) await _rememberSuccessfulRegistrationOnThisDevice();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionHomePage(
            name: (user['name'] ?? _name.text.trim()).toString(),
            email: (user['email'] ?? _email.text.trim()).toString(),
            userId: (user['happy_id'] ?? user['gabo_id'] ?? user['id'] ?? '').toString(),
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
      hintStyle: const TextStyle(color: Color(0xFF73798C), fontSize: 14),
      prefixIcon: Icon(icon, color: HappyLiveApp.gold, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFFAF6EA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFD5D9E3)),
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Container(
        color: const Color(0xFFF6F7FB),
        child: Stack(
          fit: StackFit.expand,
          children: [
          const Positioned(
            top: -110,
            right: -90,
            child: _GlowOrb(color: Color(0x22D9A93C), size: 280),
          ),
          const Positioned(
            bottom: -140,
            left: -100,
            child: _GlowOrb(color: Color(0x18D9A93C), size: 300),
          ),
          SafeArea(
            bottom: false,
            child: SizedBox.expand(
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
                            color: const Color(0xFF1E2233),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _isRegister
                              ? 'انضم إلى مجتمع Happy Live وابدأ رحلتك'
                              : 'سجّل دخولك وتواصل مع عالمك',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: const Color(0xFF62697D),
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
                                color: const Color(0xFF62697D),
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
                                  color: const Color(0xFF62697D),
                                  size: 20,
                                ),
                              ),
                            ),
                            validator: (value) => value != _password.text
                                ? 'كلمتا المرور غير متطابقتين'
                                : null,
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
                                const Text('أوافق على ', style: TextStyle(color: const Color(0xFF62697D), fontSize: 12)),
                                InkWell(
                                  onTap: () => _openLegalDocument('terms'),
                                  child: const Text('الشروط والأحكام', style: TextStyle(color: HappyLiveApp.gold, fontSize: 12, decoration: TextDecoration.underline)),
                                ),
                                const Text(' و', style: TextStyle(color: const Color(0xFF62697D), fontSize: 12)),
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
                                BoxShadow(color: Color(0x22D9A93C), blurRadius: 18, offset: Offset(0, 7)),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: const Color(0xFF1E2233),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF1E2233)))
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
                            Expanded(child: Divider(color: Color(0xFFD5D9E3))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text('أو', style: TextStyle(color: const Color(0xFF62697D), fontSize: 12)),
                            ),
                            Expanded(child: Divider(color: Color(0xFFD5D9E3))),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : _signInWithGoogle,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFD5D9E3)),
                              backgroundColor: const Color(0xFFFAF6EA),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              foregroundColor: const Color(0xFF1E2233),
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
                                side: const BorderSide(color: Color(0xFFD5D9E3)),
                                backgroundColor: const Color(0xFFFAF6EA),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                foregroundColor: const Color(0xFF1E2233),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_iphone_rounded, color: const Color(0xFF1E2233), size: 21),
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
                            Expanded(child: Divider(color: Color(0xFFD5D9E3))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'طرق تسجيل دخول أخرى',
                                style: TextStyle(color: const Color(0xFF62697D), fontSize: 12),
                              ),
                            ),
                            Expanded(child: Divider(color: Color(0xFFD5D9E3))),
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
                                  foregroundColor: const Color(0xFF1E2233),
                                  side: const BorderSide(color: Color(0xFFD5D9E3)),
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
                                  foregroundColor: const Color(0xFF1E2233),
                                  side: const BorderSide(color: Color(0xFFD5D9E3)),
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
                              style: const TextStyle(color: const Color(0xFF62697D), fontSize: 13),
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
                          style: TextStyle(color: Color(0xFF73798C), fontSize: 10, letterSpacing: 1.2),
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
        backgroundColor: const Color(0xFF1E2233),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFE4E4EC), width: 1),
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
                style: TextStyle(color: const Color(0xFF8B899A), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'البريد الإلكتروني',
                  prefixIcon: const Icon(Icons.mail_outline_rounded, color: HappyLiveApp.gold),
                  filled: true,
                  fillColor: const Color(0xFFFAF6EA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE4E4EC)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE4E4EC)),
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
  const SessionHomePage({super.key, required this.name, required this.email, required this.userId, required this.accessToken, this.initialIndex = 0});
  final String name;
  final String email;
  final String userId;
  final String accessToken;
  final int initialIndex;
  @override
  State<SessionHomePage> createState() => _SessionHomePageState();
}

class _SessionHomePageState extends State<SessionHomePage> {
  static const String _apiBase = const String.fromEnvironment('HAPPY_LIVE_API_BASE', defaultValue: 'https://happy-live-api.taher616270.workers.dev/api/v1');
  late String _profileName = widget.name.trim().isEmpty ? 'عضو Happy Live' : widget.name.trim();
  late String _profilePublicId = widget.userId;
  String _profileBio = '';
  String _profileBirthDate = '2000-01-01';
  String _profileGender = 'ذكر';
  String _profileCountry = '';
  String? _profileAvatarUrl;
  int _walletBalance = 0;
  bool _isRefreshingProfile = false;
  String get _name => _profileName;
  String get _initial => _name.characters.first.toUpperCase();

  @override
  void initState() {
    super.initState();
    CannonConfig.setAuthToken(widget.accessToken);
    GlobalGiftEvents.instance.connect(widget.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
      _refreshWalletBalance();
    });
  }

  @override
  void dispose() {
    GlobalGiftEvents.instance.disconnect();
    super.dispose();
  }

  Future<void> _refreshProfile() async {
    if (_isRefreshingProfile) return;
    _isRefreshingProfile = true;
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/auth/me'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final user = payload['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final latestName = (user['name'] ?? user['display_name'] ?? '').toString().trim();
      final latestId = (user['happy_id'] ?? user['gabo_id'] ?? '').toString().trim();
      await SessionTokenStore.writeUser(jsonEncode(user));
      if (!mounted) return;
      setState(() {
        if (latestName.isNotEmpty) _profileName = latestName;
        if (RegExp(r'^\\d{8}$').hasMatch(latestId)) _profilePublicId = latestId;
        _profileBio = (user['bio'] ?? '').toString();
        _profileBirthDate = (user['birthday'] ?? '2000-01-01').toString();
        _profileGender = (user['gender'] ?? 'male') == 'female' ? 'أنثى' : 'ذكر';
        _profileCountry = (user['country_name'] ?? '').toString();
        final avatar = (user['avatar_url'] ?? user['avatar_key'] ?? '').toString().trim();
        _profileAvatarUrl = avatar.isEmpty ? null : avatar;
      });
    } catch (_) {
      // Keep the cached profile visible if the network is temporarily unavailable.
    } finally {
      _isRefreshingProfile = false;
    }
  }

  Future<void> _refreshWalletBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/wallet'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['ok'] != true) return;
      final balance = (payload['balance'] as num?)?.toInt() ?? 0;
      if (mounted && balance != _walletBalance) {
        setState(() => _walletBalance = balance);
      }
    } catch (_) {
      // Keep the last known balance when the wallet endpoint is temporarily unavailable.
    }
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => EditProfilePage(
      apiBase: _apiBase, accessToken: widget.accessToken,
      name: _profileName, bio: _profileBio, avatarUrl: _profileAvatarUrl ?? '',
      birthDate: _profileBirthDate, gender: _profileGender, country: _profileCountry,
      onSave: _saveEditedProfile,
    )));
  }

  Future<void> _saveEditedProfile(EditProfileData data) async {
    try {
      final genderValue = data.gender == 'أنثى' ? 'female' : 'male';
      final response = await http.patch(Uri.parse('$_apiBase/profile'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': data.name, 'bio': data.bio, 'avatarUrl': data.avatarUrl,
          'birthday': data.birthDate, 'gender': genderValue, 'countryName': data.country})).timeout(const Duration(seconds: 20));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['ok'] != true) throw Exception((payload['message'] ?? payload['error'] ?? 'تعذر حفظ التعديلات').toString());
      final user = payload['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _profileName = (user['name'] ?? data.name).toString();
        _profileBio = (user['bio'] ?? data.bio).toString();
        _profileBirthDate = (user['birthday'] ?? data.birthDate).toString();
        _profileGender = (user['gender'] ?? genderValue) == 'female' ? 'أنثى' : 'ذكر';
        _profileCountry = (user['country_name'] ?? data.country).toString();
        final avatar = (user['avatar_url'] ?? data.avatarUrl ?? '').toString().trim();
        _profileAvatarUrl = avatar.isEmpty ? null : avatar;
      });
      await SessionTokenStore.writeUser(jsonEncode({'name': _profileName, 'happy_id': _profilePublicId,
        'bio': _profileBio, 'birthday': _profileBirthDate, 'gender': genderValue,
        'country_name': _profileCountry, 'avatar_url': _profileAvatarUrl}));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الملف الشخصي بنجاح'), behavior: SnackBarBehavior.floating));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), behavior: SnackBarBehavior.floating));
    }
  }
  void _soon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature قيد التجهيز وستتوفر قريباً'), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openWallet() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WalletPage(apiBase: _apiBase, accessToken: widget.accessToken),
    ));
    if (mounted) await _refreshWalletBalance();
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
    await SessionTokenStore.clear();
    await SessionTokenStore.writeUser('');
    await SessionTokenStore.writeTab(0);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginPage()), (route) => false);
  }

  late int _currentIndex = widget.initialIndex.clamp(0, 4).toInt();

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
    SessionTokenStore.writeTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HappyCreateTab(onSoon: _soon, accessToken: widget.accessToken, onGameClosed: _refreshWalletBalance),
      HappyHomeTab(
        name: _name,
        accessToken: widget.accessToken,
        onDiscover: () => setState(() => _currentIndex = 2),
        onSoon: _soon,
      ),
      HappyPostsPage(
        accessToken: widget.accessToken,
        name: _name,
      ),
      _HappyMessagesTab(apiBase: _apiBase, accessToken: widget.accessToken),
      HappyProfilePage(
        name: _name,
        email: widget.email,
        userId: _profilePublicId,
        initial: _initial,
        photoUrl: _profileAvatarUrl,
        bio: _profileBio,
        onEdit: _openEditProfile,
        onLogout: _logout,
        onSoon: _soon,
        onWallet: _openWallet,
        balance: _walletBalance,
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        // Keep the full screen painted while Scaffold resizes its body for
        // the keyboard. This prevents the root dark background showing below
        // the page whenever the search field gains or loses focus.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7EBCB),
              Color(0xFFFAF6EA),
              Color(0xFFF6F7FB),
            ],
            stops: [0.0, 0.3, 0.55],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: IndexedStack(
              index: _currentIndex,
              children: pages,
            ),
          ),
          bottomNavigationBar: CustomBottomNav(
            currentIndex: _currentIndex,
            onTap: _selectTab,
          ),
        ),
      ),
    );
  }
}

class _HappyMessagesTab extends StatefulWidget {
  const _HappyMessagesTab({required this.apiBase, required this.accessToken});
  final String apiBase;
  final String accessToken;

  @override
  State<_HappyMessagesTab> createState() => _HappyMessagesTabState();
}

class _HappyMessagesTabState extends State<_HappyMessagesTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  Timer? _conversationsRefreshTimer;
  bool _isLoadingConversations = false;
  bool _loading = true;
  bool _searching = false;
  String? _error;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _groups = [];

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.accessToken}',
    'Content-Type': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _loadConversations();
    // Keep the inbox current while it is visible, without requiring a manual refresh.
    _conversationsRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted && _search.text.trim().length < 2) {
          _loadConversations(silent: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _conversationsRefreshTimer?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${widget.apiBase}$path');
    late http.Response response;
    if (method == 'POST') {
      response = await http.post(uri, headers: _headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
    } else {
      response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر الاتصال بخدمة الرسائل').toString());
    }
    return data;
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (_isLoadingConversations) return;
    _isLoadingConversations = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _request('/messages/conversations');
      final rows = (data['conversations'] as List? ?? const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      // Legacy direct chats may contain more than one conversation for the
      // same pair of users. Keep the most recently active one in the inbox;
      // retain group conversations independently and do not delete history.
      rows.sort((a, b) {
        DateTime activity(Map<String, dynamic> item) {
          final value = item['lastMessageAt'] ?? item['updatedAt'];
          return DateTime.tryParse((value ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
        }
        return activity(b).compareTo(activity(a));
      });
      final seen = <String>{};
      final uniqueRows = <Map<String, dynamic>>[];
      for (final row in rows) {
        final kind = (row['kind'] ?? 'direct').toString();
        final conversationId = (row['id'] ?? '').toString();
        final otherUserId = (row['otherUserId'] ?? '').toString();
        final key = kind == 'direct' && otherUserId.isNotEmpty
            ? 'direct:$otherUserId'
            : '$kind:$conversationId';
        if (seen.add(key)) uniqueRows.add(row);
      }
      if (mounted) setState(() { _conversations = uniqueRows; _loading = false; _error = null; });
    } catch (e) {
      if (mounted && !silent) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    } finally {
      _isLoadingConversations = false;
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() { _searching = false; _users = []; _groups = []; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchPeople(q));
  }

  Future<void> _searchPeople(String q) async {
    if (mounted) setState(() => _searching = true);
    try {
      final data = await _request('/messages/search?q=${Uri.encodeQueryComponent(q)}');
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _users = (data['users'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _groups = (data['groups'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _searching = false;
      });
    } catch (e) {
      if (mounted) setState(() { _searching = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _startDirect(Map<String, dynamic> user) async {
    try {
      final data = await _request('/messages/conversations', method: 'POST', body: {'recipientId': user['userId']});
      final id = (data['conversationId'] ?? '').toString();
      if (id.isEmpty || !mounted) return;
      _openConversation({'id': id, 'kind': 'direct', 'displayName': user['name'], 'avatarUrl': user['avatarUrl'], 'otherUserId': user['userId']});
      await _loadConversations();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _openConversation(Map<String, dynamic> item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _HappyConversationPage(
        apiBase: widget.apiBase,
        accessToken: widget.accessToken,
        conversation: item,
      ),
    )).then((_) => _loadConversations(silent: true));
  }

  Widget _avatar(String? url, {double size = 48}) {
    final value = (url ?? '').trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFFFF2D3),
      backgroundImage: value.isNotEmpty ? NetworkImage(value) : null,
      child: value.isEmpty ? const Icon(Icons.person_rounded, color: Color(0xFFD0A044)) : null,
    );
  }

  Widget _personTile(Map<String, dynamic> user) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    leading: _avatar(user['avatarUrl']?.toString()),
    title: Text((user['name'] ?? 'مستخدم').toString(), style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w800)),
    subtitle: Text('ID: ${user['userCode'] ?? '—'}', style: const TextStyle(color: Color(0xFF9291A0), fontSize: 11)),
    trailing: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFD9A93C)),
    onTap: () => _startDirect(user),
  );

  @override
  Widget build(BuildContext context) {
    final hasQuery = _search.text.trim().length >= 2;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
          stops: [0.0, 0.3, 0.55],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الرسائل', style: TextStyle(color: Color(0xFF1E2233), fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              const Text('محادثاتك الخاصة ومجموعاتك في مكان واحد', style: TextStyle(color: Color(0xFF9A98AD), fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textDirection: TextDirection.rtl,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Color(0xFF1E2233), fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'ابحث عن أصدقاء أو مجموعات الدردشة',
                  hintStyle: const TextStyle(color: Color(0xFF777789), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9A98AD)),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFD9A93C), width: 1.3)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                children: [
                  if (_error != null && !_loading)
                    Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
                  if (hasQuery) ...[
                    if (_searching) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(color: Color(0xFFD9A93C)))),
                    if (!_searching && _users.isEmpty && _groups.isEmpty)
                      const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد نتائج مطابقة', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9291A0)))),
                    if (_users.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.fromLTRB(6, 8, 6, 6), child: Text('الأشخاص', style: TextStyle(color: Color(0xFF8D6B2A), fontWeight: FontWeight.w900))),
                      ..._users.map(_personTile),
                    ],
                    if (_groups.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.fromLTRB(6, 14, 6, 6), child: Text('مجموعات أنت عضو فيها', style: TextStyle(color: Color(0xFF8D6B2A), fontWeight: FontWeight.w900))),
                      ..._groups.map((group) => ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFFFF2D3), child: Icon(Icons.groups_rounded, color: Color(0xFFD0A044))),
                        title: Text((group['title'] ?? 'مجموعة').toString(), style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w800)),
                        subtitle: Text('${group['memberCount'] ?? 0} أعضاء', style: const TextStyle(color: Color(0xFF9291A0), fontSize: 11)),
                        onTap: () => _openConversation({'id': group['conversationId'], 'kind': 'group', 'displayName': group['title']}),
                      )),
                    ],
                  ] else ...[
                    const Padding(padding: EdgeInsets.fromLTRB(6, 8, 6, 8), child: Text('محادثاتك', style: TextStyle(color: Color(0xFF8D6B2A), fontWeight: FontWeight.w900))),
                    if (_loading) const Padding(padding: EdgeInsets.all(25), child: Center(child: CircularProgressIndicator(color: Color(0xFFD9A93C)))),
                    if (!_loading && _conversations.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE4E4EC))),
                        child: const Column(children: [
                          Icon(Icons.forum_outlined, color: Color(0xFFD9A93C), size: 34),
                          SizedBox(height: 12),
                          Text('لا توجد محادثات بعد', style: TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w900)),
                          SizedBox(height: 6),
                          Text('ابحث عن صديق وابدأ محادثتك الأولى.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9A98AD), fontSize: 12)),
                        ]),
                      ),
                    ..._conversations.map((item) {
                      final group = item['kind'] == 'group';
                      final title = (item['displayName'] ?? (group ? item['title'] : 'محادثة')).toString();
                      return Card(
                        elevation: 0, color: Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFECE7DB))),
                        child: ListTile(
                          leading: group
                            ? const CircleAvatar(backgroundColor: Color(0xFFFFF2D3), child: Icon(Icons.groups_rounded, color: Color(0xFFD0A044)))
                            : _avatar(item['avatarUrl']?.toString()),
                          title: Text(title, style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w800)),
                          subtitle: Text((item['lastMessage'] ?? 'ابدأ المحادثة').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9291A0), fontSize: 11)),
                          trailing: (item['unreadCount'] as num? ?? 0) > 0
                            ? CircleAvatar(radius: 12, backgroundColor: const Color(0xFFD9A93C), child: Text('${item['unreadCount']}', style: const TextStyle(color: Colors.white, fontSize: 10)))
                            : const Icon(Icons.chevron_left_rounded, color: Color(0xFFC5A45D)),
                          onTap: () => _openConversation({...item, 'displayName': title}),
                        ),
                      );
                    }),
                  ],
                ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HappyConversationPage extends StatefulWidget {
  const _HappyConversationPage({required this.apiBase, required this.accessToken, required this.conversation});
  final String apiBase;
  final String accessToken;
  final Map<String, dynamic> conversation;

  @override
  State<_HappyConversationPage> createState() => _HappyConversationPageState();
}

class _HappyConversationPageState extends State<_HappyConversationPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _currentUserId = '';
  List<Map<String, dynamic>> _messages = [];

  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.accessToken}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _loadMessages(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final id = Uri.encodeComponent((widget.conversation['id'] ?? '').toString());
      final response = await http.get(Uri.parse('${widget.apiBase}/messages/conversations/$id/messages?limit=100'), headers: _headers).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['ok'] != true) throw Exception((data['message'] ?? data['error'] ?? 'تعذر تحميل الرسائل').toString());
      final rows = (data['messages'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() { _messages = rows; _currentUserId = (data['currentUserId'] ?? '').toString(); _loading = false; _error = null; });
      await http.patch(Uri.parse('${widget.apiBase}/messages/conversations/$id/read'), headers: _headers).timeout(const Duration(seconds: 10));
      if (!silent && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    } catch (e) {
      if (mounted && !silent) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  String _chatTimestamp(Map<String, dynamic> message) {
    final raw = message['createdAt'] ?? message['created_at'] ?? message['timestamp'] ?? message['sentAt'];
    if (raw == null) return '';
    DateTime? date;
    if (raw is num) {
      final value = raw.toInt();
      final milliseconds = value.abs() < 1000000000000 ? value * 1000 : value;
      date = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toLocal();
    } else {
      date = DateTime.tryParse(raw.toString())?.toLocal();
    }
    if (date == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final id = Uri.encodeComponent((widget.conversation['id'] ?? '').toString());
      final response = await http.post(Uri.parse('${widget.apiBase}/messages/conversations/$id/messages'), headers: _headers, body: jsonEncode({'text': text})).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201 || data['ok'] != true) throw Exception((data['message'] ?? data['error'] ?? 'تعذر إرسال الرسالة').toString());
      final sent = data['message'] is Map
          ? Map<String, dynamic>.from(data['message'] as Map)
          : <String, dynamic>{
              'senderId': _currentUserId,
              'senderName': 'أنا',
              'text': text,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            };
      _input.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(sent);
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.conversation['displayName'] ?? widget.conversation['title'] ?? 'المحادثة').toString();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5EC),
        appBar: AppBar(
          backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2233), elevation: 0.5,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        body: Column(children: [
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD9A93C)))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length + (_error == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (_error != null && index == 0) return Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
                  final message = _messages[index - (_error == null ? 0 : 1)];
                  final messageIndex = index - (_error == null ? 0 : 1);
                  final mine = message['senderId'] == _currentUserId;
                  final timestamp = _chatTimestamp(message);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (messageIndex > 0 && timestamp.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Text(
                              timestamp,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF9A98AD), fontSize: 10, fontWeight: FontWeight.w400),
                            ),
                          ),
                        ),
                      Align(
                        alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine ? const Color(0xFFFFE8B1) : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: const Color(0xFFECE3D1)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (widget.conversation['kind'] == 'group')
                              Text((message['senderName'] ?? 'مستخدم').toString(), style: const TextStyle(color: Color(0xFFB0832E), fontSize: 10, fontWeight: FontWeight.w900)),
                            Text((message['text'] ?? '').toString(), style: const TextStyle(color: Color(0xFF1E2233), fontSize: 14, height: 1.5)),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              )),
          SafeArea(top: false, child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            color: Colors.white,
            child: Row(children: [
              Expanded(child: TextField(
                controller: _input, minLines: 1, maxLines: 4, textDirection: TextDirection.rtl,
                style: const TextStyle(color: Color(0xFF1E2233), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالتك...',
                  filled: true, fillColor: const Color(0xFFF7F5EF),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              )),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD9A93C))) : const Icon(Icons.send_rounded, color: Color(0xFFD9A93C)),
              ),
            ]),
          )),
        ]),
      ),
    );
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
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
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
  Widget build(BuildContext context) {
    // The messages tab follows the same light palette as the home page.
    if (title == 'الرسائل') {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7EBCB),
              Color(0xFFFAF6EA),
              Color(0xFFF6F7FB),
            ],
            stops: [0.0, 0.3, 0.55],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            const Text(
              'الرسائل',
              style: TextStyle(
                color: Color(0xFF1E2233),
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'محادثاتك الخاصة في مكان واحد',
              style: TextStyle(color: Color(0xFF9A98AD), fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Color(0xFF1E2233),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'ابحث عن أصدقاء أو مجموعات الدردشة',
                hintStyle: const TextStyle(
                  color: Color(0xFF777789),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9A98AD),
                  size: 22,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Color(0xFFE4E4EC)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(
                    color: Color(0xFFD9A93C),
                    width: 1.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4E4EC)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D1E2233),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF6EA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.forum_outlined,
                      color: Color(0xFFD9A93C),
                      size: 31,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'لا توجد محادثات بعد',
                    style: TextStyle(
                      color: Color(0xFF1E2233),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'ستظهر محادثاتك هنا عند تفعيل نظام الرسائل الخاصة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF9A98AD),
                      fontSize: 12,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return PurpleTechBackground(
      child: SizedBox.expand(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: HappyLiveApp.muted, fontSize: 12)),
            const SizedBox(height: 22),
            _HappyEmptyState(
              icon: icon,
              title: 'هذه المساحة قيد التجهيز',
              message: 'نعمل على تجهيز هذه المساحة لتكون جاهزة للاستخدام.',
            ),
            if (onSoon != null) ...[
              const SizedBox(height: 15),
              OutlinedButton(
                onPressed: () => onSoon!(title),
                child: const Text('معرفة المزيد'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HappyCreateTab extends StatelessWidget {
  const _HappyCreateTab({required this.onSoon, required this.accessToken, required this.onGameClosed});
  final ValueChanged<String> onSoon;
  final String accessToken;
  final Future<void> Function() onGameClosed;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF7EBCB),
          Color(0xFFFAF6EA),
          Color(0xFFF6F7FB),
        ],
        stops: [0.0, 0.48, 1.0],
      ),
    ),
    child: ListView(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 19),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF8E8), Color(0xFFFFFFFF)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEAD9AD)),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0C9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD9A93C), size: 23),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'مساحتك للإبداع',
                    style: TextStyle(color: Color(0xFF9A762D), fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Text(
              'إنشاء',
              style: TextStyle(color: Color(0xFF1E2233), fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'شارك لحظاتك مع مجتمع Happy Live',
              style: TextStyle(color: Color(0xFF77778A), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 23),
      const Padding(
        padding: EdgeInsets.only(right: 3, bottom: 12),
        child: Text(
          'الألعاب',
          style: TextStyle(color: Color(0xFF1E2233), fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
      if (kIsWeb) DynamicGamesList(onGameClosed: onGameClosed),
      const SizedBox(height: 23),
      const Padding(
        padding: EdgeInsets.only(right: 3, bottom: 12),
        child: Text(
          'ابدأ بمشاركة جديدة',
          style: TextStyle(color: Color(0xFF1E2233), fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
      _HappyCreateAction(
        icon: Icons.post_add_rounded,
        title: 'منشور جديد',
        subtitle: 'شارك فكرة أو صورة مع المجتمع',
        onTap: () => onSoon('إنشاء المنشورات'),
      ),
      const SizedBox(height: 12),
      _HappyCreateAction(
        icon: Icons.auto_awesome_motion_rounded,
        title: 'قصة جديدة',
        subtitle: 'شارك لحظة قصيرة مع أصدقائك',
        onTap: () => onSoon('القصص'),
      ),
      const SizedBox(height: 12),
      _HappyCreateAction(
        icon: Icons.mic_rounded,
        title: 'بدء بث مباشر',
        subtitle: 'تواصل صوتياً مع الآخرين',
        onTap: () => onSoon('البث المباشر'),
      ),
    ],
    ),
  );
}

class _HappyCreateAction extends StatelessWidget {
  const _HappyCreateAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9E5D9)),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFFFFF2D3), Color(0xFFFFF9EC)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFF0DFB5)),
              ),
              child: Icon(icon, color: const Color(0xFFD1A13A), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF8B899A), fontSize: 11, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFFC5A45D), size: 23),
          ],
        ),
      ),
    ),
  );
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
              colors: [Color(0xFFFFF9EC), Color(0xFFFFF2D3)],
            ),
            border: Border.all(color: const Color(0xFFD9A93C), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x22D9A93C), blurRadius: 24, spreadRadius: 1),
            ],
          ),
          child: Center(
            child: Image.asset(
              'assets/images/app_icon2.png.PNG',
              width: 88,
              height: 88,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: HappyLiveApp.gold,
                size: 42,
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
    child: Text(label, style: const TextStyle(color: Color(0xFF30364A), fontSize: 13, fontWeight: FontWeight.w700)),
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
        backgroundColor: Colors.transparent,
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
