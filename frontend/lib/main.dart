import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(const HappyLiveApp());

class HappyLiveApp extends StatelessWidget {
  const HappyLiveApp({super.key});

  static const _background = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _gold = Color(0xFFE8C477);
  static const _purple = Color(0xFF9B63D9);

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
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _gold,
          secondary: _purple,
          surface: _surface,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: _gold,
          centerTitle: true,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  static const _labels = ['الرئيسية', 'منشورات', 'ألعاب', 'رسائل', 'ملفي'];
  static const _icons = [
    Icons.home_rounded,
    Icons.public_rounded,
    Icons.sports_esports_rounded,
    Icons.chat_bubble_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HAPPY LIVE', style: TextStyle(
          fontWeight: FontWeight.w900, letterSpacing: 1.4,
        )),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0x55E8C477)),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF30203F), Color(0xFF17131F), Color(0xFF111018)],
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR SOCIAL UNIVERSE',
                          style: TextStyle(color: Color(0xFFE8C477), fontSize: 10, letterSpacing: 2)),
                        SizedBox(height: 12),
                        Text('عالمك يبدأ من هنا',
                          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                        SizedBox(height: 8),
                        Text('اكتشف مجتمعاتك، تابع أصدقاءك وكن جزءاً من اللحظة',
                          style: TextStyle(color: Color(0xFFD0C8D8), height: 1.6)),
                        SizedBox(height: 16),
                        Row(children: [
                          _Pill(label: 'مجتمعك'),
                          SizedBox(width: 8),
                          _Pill(label: 'تواصل مباشر'),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(_labels[_selected],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF17131F),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0x229B63D9)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icons[_selected], size: 42, color: const Color(0xFFE8C477)),
                          const SizedBox(height: 12),
                          Text(_selected == 2 ? 'قريباً' : 'يتم تجهيز هذا القسم',
                            style: const TextStyle(color: Color(0xFFD0C8D8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (value) => setState(() => _selected = value),
        destinations: List.generate(_labels.length, (index) =>
          NavigationDestination(icon: Icon(_icons[index]), label: _labels[index])),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x332D2438),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x449B63D9)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}
