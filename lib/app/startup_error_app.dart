import 'package:flutter/material.dart';

/// Écran affiché si le démarrage échoue : l'erreur est visible (pour le support) et on peut réessayer.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, required this.onRetry, super.key});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF140A72),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Konekt n’a pas pu démarrer',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$error',
                  key: const Key('startup-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFC9CCF0), fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF140A72),
                  ),
                  onPressed: onRetry,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
