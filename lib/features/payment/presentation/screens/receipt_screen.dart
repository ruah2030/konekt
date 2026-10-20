import 'package:flutter/material.dart';

// TODO(agent): écran à implémenter (stub temporaire).
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({required this.operationId, this.fromHistory = false, super.key});
  final String operationId;
  final bool fromHistory;

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('ReceiptScreen')));
}
