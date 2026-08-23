import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/screen_chrome.dart';

class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
    this.url,
    this.embedded = false,
    this.onBack,
  });

  final String title;

  final String assetPath;

  final String? url;

  final bool embedded;
  final VoidCallback? onBack;

  static bool get supportsWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  String? _text;
  Object? _error;
  WebViewController? _webView;

  bool get _hasUrl => widget.url != null && widget.url!.isNotEmpty;

  @override
  void initState() {
    super.initState();

    if (_hasUrl && LegalDocumentScreen.supportsWebView) {
      _openWebView();
      return;
    }
    if (_hasUrl) {
      _openInBrowser();
    }
    _loadAsset();
  }

  void _openWebView() {
    setState(() {
      _webView = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (_) {
            // Страница не открылась — показываем копию из ресурсов.
            if (!mounted) return;
            setState(() => _webView = null);
            _loadAsset();
          },
        ))
        ..loadRequest(Uri.parse(widget.url!));
    });
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url!);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (err) {
      debugPrint('Не удалось открыть документ в браузере: $err');
    }
  }

  Future<void> _loadAsset() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      if (!mounted) return;
      setState(() => _text = text);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: widget.title,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: [
          if (_text != null && _webView == null)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: L.of(context).legalCopyText,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _text!));
                if (!mounted) return;
                showSuccess(context, L.of(context).legalTextCopied);
              },
            ),
        ],
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final webView = _webView;
    if (webView != null) return WebViewWidget(controller: webView);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            L.of(context).legalOpenFailed,
            style: context.texts.bodyMedium
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      );
    }

    final text = _text;
    if (text == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.readableWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _render(context, text),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _render(BuildContext context, String source) {
    final colors = context.colors;
    final texts = context.texts;
    final widgets = <Widget>[];

    for (final rawLine in source.split('\n')) {
      // Markdown отмечает перенос строки двумя пробелами в конце — на экране
      // они не нужны.
      final line = rawLine.trimRight();

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.sm));
        continue;
      }

      if (line.startsWith('---')) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Divider(color: colors.outlineVariant, height: 1),
        ));
        continue;
      }

      if (line.startsWith('### ')) {
        widgets.add(_heading(line.substring(4), texts.titleSmall));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(_heading(line.substring(3), texts.titleMedium));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(_heading(line.substring(2), texts.headlineSmall));
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm, top: 7),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: _paragraph(context, line.substring(2)),
              ),
            ],
          ),
        ));
        continue;
      }

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: _paragraph(context, line),
      ));
    }

    return widgets;
  }

  Widget _heading(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Text(text, style: style),
    );
  }

  /// Абзац с поддержкой **жирного**.
  Widget _paragraph(BuildContext context, String source) {
    final base = context.texts.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.55,
    );

    final spans = <TextSpan>[];
    final parts = source.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd
            ? base?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.onSurface,
              )
            : base,
      ));
    }

    return SelectableText.rich(TextSpan(children: spans, style: base));
  }
}