import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class ExploreBannerWebView extends StatefulWidget {
  const ExploreBannerWebView({super.key, required this.url});
  final String url;

  @override
  State<ExploreBannerWebView> createState() => _ExploreBannerWebViewState();
}

class _ExploreBannerWebViewState extends State<ExploreBannerWebView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'happy-live-explore-webview-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return html.IFrameElement()
        ..src = widget.url
        ..title = 'صفحة البانر'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
