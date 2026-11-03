import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  bool _isRegister = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _hasRegisteredOnThisDevice = false;

  static const _registeredDeviceKey = 'happy_live_registered_on_device';

  @override
  void initState() {
    super.initState();
    _loadDeviceRegistration();
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
    super.dispose();
  }

  void _showNotConnected() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('واجهة تسجيل الدخول جاهزة، وسيتم ربط الحسابات بالخادم في الخطوة التالية'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_isRegister && !_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى الموافقة على الشروط والأحكام')),
      );
      return;
    }
    _showNotConnected();
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
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: HappyLiveApp.gold,
                            checkColor: HappyLiveApp.background,
                            title: const Text(
                              'أوافق على الشروط والأحكام وسياسة الخصوصية',
                              style: TextStyle(color: HappyLiveApp.muted, fontSize: 12),
                            ),
                          ),
                        ] else ...[
                          Align(
                            alignment: Alignment.centerLeft,
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
                              onPressed: _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: const Color(0xFF171019),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: Text(
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
                                onPressed: _showNotConnected,
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
          child: const Center(
            child: Text(
              'H',
              style: TextStyle(
                fontSize: 54,
                height: 1,
                fontWeight: FontWeight.w900,
                color: HappyLiveApp.gold,
                shadows: [Shadow(color: HappyLiveApp.purple, blurRadius: 16)],
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
