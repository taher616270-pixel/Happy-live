import 'package:flutter/material.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import 'explore_banner_webview.dart';

class ExploreBannerDestinationPage extends StatelessWidget {
  const ExploreBannerDestinationPage({super.key, required this.banner});
  final Map<String, dynamic> banner;

  @override
  Widget build(BuildContext context) {
    final type = (banner['destinationType'] ?? 'none').toString();
    final title = (banner['destinationTitle'] ?? banner['title'] ?? 'التفاصيل').toString();
    final description = (banner['description'] ?? '').toString();
    final url = (banner['destinationUrl'] ?? '').toString();
    final isWeb = (type == 'vip' || type == 'url') && url.startsWith('https://');
    final isRules = type == 'rules';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292929),
        elevation: 0,
      ),
      body: isWeb
          ? ExploreBannerWebView(url: url)
          : isRules
              ? ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Text(
                      description.isEmpty ? 'لم تتم إضافة نص القوانين لهذا البانر بعد.' : description,
                      style: const TextStyle(fontSize: 15, height: 1.9, color: Color(0xFF333333)),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if ((banner['imageUrl'] ?? '').toString().startsWith('https://'))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 16 / 7,
                          child: HappyNetworkImage((banner['imageUrl'] ?? '').toString()),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(
                      description.isEmpty ? 'سيتم إضافة تفاصيل هذا الحدث من لوحة الإدارة.' : description,
                      style: const TextStyle(fontSize: 15, height: 1.8, color: Color(0xFF444444)),
                    ),
                  ],
                ),
    );
  }
}
