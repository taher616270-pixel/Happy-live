import 'package:flutter/material.dart';

class ExploreBannerWebView extends StatelessWidget {
  const ExploreBannerWebView({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'عرض صفحة الويب المضمنة غير متاح على هذا النظام.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    ),
  );
}
