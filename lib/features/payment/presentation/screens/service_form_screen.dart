import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/payment_repository.dart';
import '../../domain/service_config.dart';
import '../providers/payment_flow.dart';

/// Formulaire générique d'un service, piloté par [ServiceConfig].
class ServiceFormScreen extends ConsumerStatefulWidget {
  const ServiceFormScreen({required this.type, super.key});
  final ServiceType type;

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  late final ServiceConfig _config = serviceConfig(widget.type);
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _config.fields) f.key: TextEditingController(),
  };
  String? _option;
  ApiFailure? _error;
  bool _loading = false;
  final _errorKey = GlobalKey();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final form = {for (final e in _controllers.entries) e.key: e.value.text};
    final failure = await ref.read(paymentFlowProvider.notifier).requestQuote(widget.type, form, _option);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = failure;
    });
    if (failure == null) {
      unawaited(context.push(Routes.quote));
    } else {
      // Rend l'erreur visible (elle est sous les champs).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _errorKey.currentContext;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final balance = ref.watch(balanceProvider).value;
    final option = _config.option;
    return Scaffold(
      backgroundColor: KColors.surface,
      appBar: AppBar(
        backgroundColor: KColors.surface,
        leading: IconButton(
          key: const Key('service-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: Text(_config.title, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_config.intro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_config.intro, style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5)),
              ),
            if (option != null) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  option.label,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                ),
              ),
              const SizedBox(height: 8),
              if (option.loadedFromApi)
                _apiOptions()
              else
                _OptionGrid(items: option.items, selected: _option, onSelect: _select),
            ],
            for (final f in _config.fields) ...[
              const SizedBox(height: 22),
              _FieldInput(
                field: f,
                controller: _controllers[f.key]!,
                onChanged: (_) => _changed(),
                hint: f.isAmount && widget.type != ServiceType.topup && balance != null
                    ? 'Solde disponible : ${formatFcfa(balance)}'
                    : null,
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 22), ErrorBlock(_error!, key: _errorKey)],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                key: const Key('quote-submit'),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: KColors.onPrimary),
                      )
                    : const Text('Voir le prix exact'),
              ),
              const SizedBox(height: 10),
              Text(
                "Rien n'est débité à cette étape.",
                style: t.labelMedium?.copyWith(color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(String id) => setState(() {
    _option = id;
    _error = null;
  });

  Widget _apiOptions() {
    final plans = ref.watch(dataPlansProvider);
    return plans.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dataPlansProvider)),
      data: (list) => _OptionGrid(
        items: [for (final p in list) ServiceOptionItem(id: p.id, label: p.label, sub: p.validity, price: p.price)],
        selected: _option,
        onSelect: _select,
      ),
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({required this.items, required this.selected, required this.onSelect});
  final List<ServiceOptionItem> items;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _tile(items[i])),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < items.length ? _tile(items[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _tile(ServiceOptionItem o) {
    final sel = o.id == selected;
    return Material(
      color: sel ? KColors.primaryContainer : KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sel ? KColors.primary : const Color(0xFFCBD5E1), width: sel ? 2 : 1),
      ),
      child: InkWell(
        key: Key('option-${o.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(o.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sel ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
                  size: 20,
                  color: KColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.primary),
                      ),
                      if (o.sub != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.sub!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: KColors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (o.price != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          formatFcfa(o.price!),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: KColors.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.field, required this.controller, required this.onChanged, this.hint});
  final ServiceField field;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key('field-${field.key}'),
          controller: controller,
          onChanged: onChanged,
          keyboardType: switch (field.kind) {
            FieldKind.numeric => TextInputType.number,
            FieldKind.tel => TextInputType.phone,
            FieldKind.text => TextInputType.emailAddress,
          },
          inputFormatters: [if (field.kind == FieldKind.numeric) FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))],
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: KColors.primary),
          decoration: InputDecoration(hintText: field.placeholder),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            key: Key('hint-${field.key}'),
            style: t.labelMedium?.copyWith(color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
}
