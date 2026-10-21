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
import '../../../../core/utils/validators.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/payment_repository.dart';
import '../../domain/payment_models.dart';
import '../../domain/service_config.dart';
import '../providers/payment_flow.dart';

/// Formulaire générique d'un service, piloté par [ServiceConfig] : saisie, choix du portefeuille
/// ou de l'offre (lookup opérateur), validations locales puis devis.
class ServiceFormScreen extends ConsumerStatefulWidget {
  const ServiceFormScreen({required this.type, super.key});
  final ServiceType type;

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  late final ServiceConfig _config = serviceConfig(widget.type);
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _config.fields)
      if (!f.isChoice) f.key: TextEditingController(),
  };
  final _choices = <String, String>{};
  List<MobileProduct>? _products;
  bool _loadingProducts = false;
  Map<String, String> _fieldErrors = const {};
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

  List<WalletChannel> get _wallets {
    final op = _config.walletOperation;
    return op == null ? const [] : ref.read(walletChannelsProvider(op)).value ?? const [];
  }

  FormSelection get _selection => FormSelection(
    wallet: _wallets.where((w) => w.slug == _choices['wallet']).firstOrNull,
    product: _products?.where((p) => p.id == _choices['productId']).firstOrNull,
    productsLoaded: _products != null,
  );

  Map<String, String> get _values => {for (final e in _controllers.entries) e.key: e.value.text, ..._choices};

  void _changed(String key) {
    if (key == 'beneficiary' && _products != null) {
      // Nouveau numéro : les offres de l'ancienne ligne ne valent plus.
      _products = null;
      _choices.remove('productId');
    }
    if (_error != null || _fieldErrors.containsKey(key) || _products == null) {
      setState(() {
        _error = null;
        _fieldErrors = {..._fieldErrors}..remove(key);
      });
    }
  }

  void _select(String key, String id) => setState(() {
    _choices[key] = id;
    _error = null;
    _fieldErrors = {..._fieldErrors}..remove(key);
  });

  void _showError() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = _errorKey.currentContext;
    if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
  });

  Future<void> _loadProducts() async {
    final number = _controllers['beneficiary']!.text;
    if (!Validators.isMsisdn(number)) {
      setState(() => _fieldErrors = {'beneficiary': 'Numéro de téléphone invalide.'});
      return;
    }
    setState(() {
      _loadingProducts = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final products = await ref
          .read(paymentRepositoryProvider)
          .mobileProducts(toInternational(number), _config.productType!);
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _products = products;
        if (products.length == 1) _choices['productId'] = products.first.id;
        if (products.isEmpty) {
          _error = ApiFailure.local(ErrorCodes.notFound, 'Aucune offre disponible pour ce numéro.');
        }
      });
    } catch (e) {
      if (!mounted) return;
      final f = ApiFailure.from(e);
      setState(() {
        _loadingProducts = false;
        // Erreurs fournisseur rendues en 500 (guide Partie 5 §3.5) : message explicite.
        _error = (f.statusCode ?? 0) >= 500
            ? ApiFailure(
                code: f.code,
                message: 'Numéro introuvable ou service momentanément indisponible — vérifiez la saisie et réessayez.',
                ref: f.ref,
              )
            : f;
      });
      _showError();
    }
  }

  Future<void> _submit() async {
    if (_loading || _loadingProducts || _config.comingSoon) return;
    FocusScope.of(context).unfocus();
    if (_config.needsProducts && _products == null) return _loadProducts();
    final selection = _selection;
    final session = ref.read(cardSessionProvider);
    final errors = validateForm(_config, _values, selection, sessionCardId: session?.cardCustomerId);
    if (errors.isNotEmpty || session == null) {
      setState(() {
        _fieldErrors = errors;
        _error = session == null ? ApiFailure.local(ErrorCodes.unauthenticated, 'Reconnectez-vous.') : null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _fieldErrors = const {};
    });
    final request = buildRequest(_config, _values, selection, cardCustomerId: session.cardCustomerId);
    final failure = await ref.read(paymentFlowProvider.notifier).requestQuote(request);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = failure?.failure;
      _fieldErrors = failure == null ? const {} : _serverFieldErrors(failure);
    });
    if (failure == null) {
      unawaited(context.push(Routes.quote));
    } else {
      _showError();
    }
  }

  /// Erreurs par champ : `details` (`VALIDATION_FAILED`) et contrôles en échec du devis.
  Map<String, String> _serverFieldErrors(QuoteFailure failure) {
    final out = <String, String>{};
    for (final f in _config.fields) {
      for (final key in {f.key, ...f.errorKeys}) {
        final msgs = failure.failure.fieldErrors(key);
        if (msgs.isNotEmpty) out[f.key] = msgs.join(' ');
      }
      final check = failure.failedChecks.where((c) => f.checkKeys.contains(c.key)).firstOrNull;
      if (check != null && !out.containsKey(f.key)) out[f.key] = check.detail ?? check.label;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final debitsCard = widget.type != ServiceType.topup;
    final balance = debitsCard ? ref.watch(balanceProvider).value : null;
    final walletOp = _config.walletOperation;
    if (walletOp != null) ref.watch(walletChannelsProvider(walletOp));
    final selection = _selection;
    final lookupStep = _config.needsProducts && _products == null;
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
            if (_config.comingSoon) ...[
              const SizedBox(height: 32),
              const EmptyState(message: 'Bientôt disponible.', icon: Symbols.live_tv_rounded),
            ],
            for (final f in _config.fields)
              if (isFieldVisible(f, selection)) ...[
                const SizedBox(height: 22),
                if (f.isChoice)
                  _choiceSection(f)
                else
                  _FieldInput(
                    field: f,
                    controller: _controllers[f.key]!,
                    onChanged: (_) => _changed(f.key),
                    errorText: _fieldErrors[f.key],
                    hint: f.kind == FieldKind.amount && balance != null
                        ? 'Solde disponible : ${formatFcfa(balance)}'
                        : f.kind == FieldKind.amount && selection.product?.isRange == true
                        ? 'De ${formatFcfa(selection.product!.minPrice ?? 1)} à ${formatFcfa(selection.product!.maxPrice ?? 0)}'
                        : f.hint,
                  ),
              ],
            if (_loadingProducts)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null) ...[const SizedBox(height: 22), ErrorBlock(_error!, key: _errorKey)],
          ],
        ),
      ),
      bottomNavigationBar: _config.comingSoon
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      key: const Key('quote-submit'),
                      onPressed: _loading || _loadingProducts ? null : _submit,
                      child: _loading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: KColors.onPrimary),
                            )
                          : Text(lookupStep ? 'Voir les offres' : 'Voir le prix exact'),
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

  Widget _choiceSection(ServiceField f) {
    final t = Theme.of(context).textTheme;
    final error = _fieldErrors[f.key];
    Widget grid(List<ChoiceItem> items) =>
        _OptionGrid(items: items, selected: _choices[f.key], onSelect: (id) => _select(f.key, id));
    final Widget body = switch (f.source) {
      ChoiceSource.fixed => grid(f.items),
      ChoiceSource.products => grid([
        for (final p in _products ?? const <MobileProduct>[])
          ChoiceItem(
            id: p.id,
            label: p.name,
            sub: p.isRange ? 'Montant libre' : null,
            price: p.isRange ? null : p.price,
          ),
      ]),
      ChoiceSource.wallets =>
        ref
            .watch(walletChannelsProvider(_config.walletOperation!))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  ErrorView(error: e, onRetry: () => ref.invalidate(walletChannelsProvider(_config.walletOperation!))),
              data: (list) => grid([
                for (final w in list)
                  ChoiceItem(id: w.slug, label: w.label, sub: w.holderVerification ? 'Titulaire vérifié' : null),
              ]),
            ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            f.label,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
          ),
        ),
        const SizedBox(height: 8),
        body,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            key: Key('error-${f.key}'),
            style: t.labelMedium?.copyWith(color: KColors.error, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({required this.items, required this.selected, required this.onSelect});
  final List<ChoiceItem> items;
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

  Widget _tile(ChoiceItem o) {
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
  const _FieldInput({
    required this.field,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.errorText,
  });
  final ServiceField field;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? errorText;

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
            FieldKind.amount => const TextInputType.numberWithOptions(decimal: true),
            FieldKind.cardId || FieldKind.digits || FieldKind.accessCode => TextInputType.number,
            FieldKind.tel => TextInputType.phone,
            FieldKind.contact => TextInputType.emailAddress,
            FieldKind.text || FieldKind.choice => TextInputType.name,
          },
          inputFormatters: [
            if (field.kind == FieldKind.amount) FilteringTextInputFormatter.allow(RegExp(r'[\d\s,.]')),
            if (field.kind == FieldKind.digits || field.kind == FieldKind.cardId)
              FilteringTextInputFormatter.allow(RegExp(r'[\dOo\s]')),
            if (field.kind == FieldKind.accessCode) ...[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
          ],
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: KColors.primary),
          decoration: InputDecoration(hintText: field.placeholder, errorText: errorText, errorMaxLines: 3),
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
