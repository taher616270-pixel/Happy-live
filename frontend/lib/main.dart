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
  DateTime? _birthDate;
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

  void _submit() {
    // Validate the registration fields first, then age and legal consent.
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
                fontSize: 66,
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
