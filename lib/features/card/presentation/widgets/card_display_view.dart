import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/network/fake/handlers/card_handlers.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/presentation/providers/auth_controller.dart';

/// Charge `displayUrl` (page VGS de l'API, guide §14.3) TELLE QUELLE, une seule fois.
///
/// En mode faux backend, l'adresse pointe vers un hôte fictif : on affiche alors un panneau de
/// démonstration équivalent à la page VGS.
class CardDisplayView extends StatelessWidget {
  const CardDisplayView({required this.displayUrl, super.key});
  final Uri displayUrl;

  @override
  Widget build(BuildContext context) =>
      isFakeCardDisplayUrl(displayUrl) ? const DemoCardDisplayPanel() : _SecureWebView(displayUrl: displayUrl);
}

/// WebView à usage unique : JavaScript activé, aucun rechargement, détruite avec le widget.
class _SecureWebView extends StatefulWidget {
  const _SecureWebView({required this.displayUrl});
  final Uri displayUrl;

  @override
  State<_SecureWebView> createState() => _SecureWebViewState();
}

class _SecureWebViewState extends State<_SecureWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ),
      );
    // Chargée une seule fois : un second chargement afficherait « Ce lien a déjà servi ».
    unawaited(_controller.loadRequest(widget.displayUrl));
  }

  @override
  void dispose() {
    // Efface la page affichée (les données resteraient sinon dans la vue native en cours de destruction).
    unawaited(_controller.loadHtmlString('<html></html>').catchError((Object _) {}));
    unawaited(_controller.clearCache().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: _failed
        ? const Center(
            child: Text(
              "L'affichage n'a pas pu être chargé.",
              key: Key('display-webview-error'),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          )
        : Stack(
            children: [
              WebViewWidget(key: const Key('display-webview'), controller: _controller),
              if (_loading) const Center(child: CircularProgressIndicator(color: KColors.secondary)),
            ],
          ),
  );
}

/// Imitation de la page VGS (numéro `#### #### #### ####`, expiration, CVV, boutons de copie),
/// utilisée uniquement avec le faux backend.
class DemoCardDisplayPanel extends ConsumerWidget {
  const DemoCardDisplayPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last4 = ref.watch(cardSessionProvider)?.last4 ?? '0000';
    final pan = '4532 1180 7741 ${last4.padLeft(4, '0')}';
    return Container(
      key: const Key('display-demo'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DemoField(label: 'Numéro de carte', value: pan, valueKey: const Key('display-pan')),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                child: _DemoField(label: 'Expiration', value: '04/27', valueKey: Key('display-expiry')),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _DemoField(label: 'CVV', value: '318', valueKey: Key('display-cvv')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Démonstration : données fictives.', style: TextStyle(fontSize: 11, color: Color(0xFFB8BCE8))),
        ],
      ),
    );
  }
}

class _DemoField extends StatelessWidget {
  const _DemoField({required this.label, required this.value, required this.valueKey});
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB8BCE8), fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                key: valueKey,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copier',
            visualDensity: VisualDensity.compact,
            color: const Color(0xFFB8BCE8),
            icon: const Icon(Symbols.content_copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
              if (context.mounted) showToast(context, 'Copié.');
            },
          ),
        ],
      ),
    ],
  );
}
