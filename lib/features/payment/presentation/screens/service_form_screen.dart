import 'package:flutter/material.dart';

import '../../../../core/domain/service_type.dart';

// TODO(agent): écran à implémenter (stub temporaire).
class ServiceFormScreen extends StatelessWidget {
  const ServiceFormScreen({required this.type, super.key});
  final ServiceType type;

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('ServiceFormScreen')));
}
