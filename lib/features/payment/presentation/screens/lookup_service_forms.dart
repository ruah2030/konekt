part of 'service_form_screen.dart';

/// Erreur d'une consultation fournisseur. Abonné ou carte inconnus et fournisseur injoignable sortent
/// en 500 (guide Partie 5 §3.5, Partie 9 #12) : « Service partenaire indisponible » + conseil de saisie.
ApiFailure _lookupFailure(Object e, String hint) {
  final f = ApiFailure.from(e);
  if ((f.statusCode ?? 0) < 500 && f.code != ErrorCodes.internalError) return f;
  return ApiFailure(
    code: f.code,
    statusCode: f.statusCode,
    message: 'Service partenaire indisponible — $hint',
    ref: f.ref,
  );
}

/// Formulaire à consultation préalable du fournisseur (abonnement TV, facture d'électricité) :
/// saisie de l'identifiant → lookup → choix → devis (prix imposé) → parcours commun (PIN, suivi, reçu).
abstract class _LookupFormState<W extends ConsumerStatefulWidget> extends ConsumerState<W> {
  ServiceType get type;
  late final ServiceConfig config = serviceConfig(type);
  ServiceField get field => config.fields.first;
  final controller = TextEditingController();
  final _errorKey = GlobalKey();
  Map<String, String> fieldErrors = const {};
  ApiFailure? error;
  bool busy = false;

  /// Consultation faite pour l'identifiant saisi.
  bool get lookedUp;

  /// Consulte le fournisseur pour l'identifiant saisi.
  Future<void> lookup();

  /// Oublie la consultation (identifiant modifié).
  void resetLookup();

  /// Valeurs transmises à [buildRequest].
  Map<String, String> get values;

  /// Choix manquants propres au service (clé → message).
  Map<String, String> missingChoices() => const {};

  String get lookupLabel;
  List<Widget> sections();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void showError() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = _errorKey.currentContext;
    if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
  });

  void clearError(String key) => setState(() {
    error = null;
    fieldErrors = {...fieldErrors}..remove(key);
  });

  void _inputChanged() => setState(() {
    if (lookedUp) resetLookup();
    error = null;
    fieldErrors = {...fieldErrors}..remove(field.key);
  });

  /// Lance [run] (consultation) avec indicateur et erreur « Service partenaire indisponible ».
  Future<void> runLookup(Future<void> Function() run, String hint) async {
    final errors = validateForm(config, {field.key: controller.text}, const FormSelection());
    if (errors.isNotEmpty) {
      setState(() => fieldErrors = errors);
      return;
    }
    setState(() {
      busy = true;
      error = null;
      fieldErrors = const {};
    });
    try {
      await run();
      if (mounted) setState(() => busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = _lookupFailure(e, hint);
      });
      showError();
    }
  }

  Future<void> _submit() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    if (!lookedUp) return lookup();
    final session = ref.read(cardSessionProvider);
    final errors = {
      ...validateForm(config, values, const FormSelection(), sessionCardId: session?.cardCustomerId),
      ...missingChoices(),
    };
    if (errors.isNotEmpty || session == null) {
      setState(() {
        fieldErrors = errors;
        error = session == null ? ApiFailure.local(ErrorCodes.unauthenticated, 'Reconnectez-vous.') : null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      fieldErrors = const {};
    });
    final request = buildRequest(config, values, const FormSelection(), cardCustomerId: session.cardCustomerId);
    final failure = await ref.read(paymentFlowProvider.notifier).requestQuote(request);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = failure?.failure;
      fieldErrors = failure == null ? const {} : _quoteFieldErrors(failure);
    });
    if (failure == null) {
      unawaited(context.push(Routes.quote));
    } else {
      showError();
    }
  }

  /// Contrôles en échec du devis : sous le champ saisi ou sous la section du choix (`offer`, `duration`…).
  Map<String, String> _quoteFieldErrors(QuoteFailure failure) {
    final out = <String, String>{};
    final msgs = failure.failure.fieldErrors(field.key);
    if (msgs.isNotEmpty) out[field.key] = msgs.join(' ');
    for (final c in failure.failedChecks) {
      final key = field.checkKeys.contains(c.key) ? field.key : c.key;
      out.putIfAbsent(key, () => c.detail ?? c.label);
    }
    return out;
  }

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
    ),
  );

  Widget? sectionError(String key) {
    final e = fieldErrors[key];
    if (e == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        e,
        key: Key('error-$key'),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: KColors.error, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget checkTile({
    required Key key,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    String? subtitle,
    String? trailing,
  }) => Material(
    color: value ? KColors.primaryContainer : KColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: value ? KColors.primary : const Color(0xFFCBD5E1), width: value ? 2 : 1),
    ),
    child: CheckboxListTile(
      key: key,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.primary),
      ),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
      secondary: trailing == null
          ? null
          : Text(
              trailing,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: KColors.primary),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
        title: Text(config.title, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(config.intro, style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5)),
            ),
            const SizedBox(height: 22),
            _FieldInput(
              field: field,
              controller: controller,
              onChanged: (_) => _inputChanged(),
              errorText: fieldErrors[field.key],
              hint: lookedUp ? null : field.hint,
            ),
            ...sections(),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null) ...[const SizedBox(height: 22), ErrorBlock(error!, key: _errorKey)],
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
                onPressed: busy ? null : _submit,
                child: Text(lookedUp ? 'Voir le prix exact' : lookupLabel),
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
}

/// Abonnement TV Canal+ (`tv-subscription`, prix imposé) : carte TV → abonnement en cours →
/// reconduction (sans `mainOffer`) ou changement de bouquet (`mainOffer` + `duration` [+ `optionsList`]).
class _TvSubscriptionForm extends ConsumerStatefulWidget {
  const _TvSubscriptionForm();

  @override
  ConsumerState<_TvSubscriptionForm> createState() => _TvSubscriptionFormState();
}

class _TvSubscriptionFormState extends _LookupFormState<_TvSubscriptionForm> {
  static const _hint = 'vérifiez le numéro de carte TV et réessayez.';

  TvCurrentOffer? _current;
  List<TvOffer>? _offers;
  bool _change = false;
  String? _offerCode;
  String? _duration;
  final _options = <String>{};

  @override
  ServiceType get type => ServiceType.tv;

  @override
  String get lookupLabel => 'Vérifier l’abonnement';

  @override
  bool get lookedUp => _current != null;

  TvOffer? get _offer => _offers?.where((o) => o.code == _offerCode).firstOrNull;

  @override
  void resetLookup() {
    _current = null;
    _offers = null;
    _change = false;
    _offerCode = null;
    _duration = null;
    _options.clear();
  }

  String get _numCard => compactCode(controller.text);

  @override
  Future<void> lookup() => runLookup(() async {
    final current = await ref.read(paymentRepositoryProvider).tvCurrent(_numCard);
    if (mounted) setState(() => _current = current);
  }, _hint);

  Future<void> _loadOffers() => runLookup(() async {
    final offers = await ref.read(paymentRepositoryProvider).tvOffers(_numCard);
    if (!mounted) return;
    setState(() {
      _offers = offers;
      if (offers.isEmpty) {
        error = ApiFailure.local(ErrorCodes.notFound, 'Aucun autre bouquet n’est proposé pour cette carte.');
      }
    });
  }, _hint);

  void _mode(String id) {
    setState(() {
      _change = id == 'change';
      error = null;
      fieldErrors = {...fieldErrors}..removeWhere((k, _) => k != field.key);
    });
    if (_change && _offers == null) _loadOffers();
  }

  void _pickOffer(String code) => setState(() {
    if (_offerCode != code) {
      _offerCode = code;
      _options.clear();
      final durations = _offer?.durations ?? const [];
      _duration = durations.length == 1 ? durations.first.code : null;
    }
    error = null;
    fieldErrors = {...fieldErrors}..remove('offer');
  });

  @override
  Map<String, String> get values {
    final offer = _change ? _offer : null;
    return {
      'numCard': controller.text,
      if (offer != null) ...{
        'mainOffer': offer.code,
        'duration': _duration ?? '',
        'optionsList': [
          for (final o in offer.options)
            if (_options.contains(o.code)) o.code,
        ].join(','),
      },
    };
  }

  @override
  Map<String, String> missingChoices() => {
    if (_change && _offers != null && _offer == null) 'offer': 'Choisissez un bouquet.',
  };

  /// Libellé du bouquet en cours (`mainOfferLabel` peut être un code : libellé des offres s'il est connu).
  String _currentLabel(TvCurrentOffer c) =>
      _offers?.where((o) => o.code == c.mainOfferLabel).firstOrNull?.label ?? c.mainOfferLabel;

  @override
  List<Widget> sections() {
    final current = _current;
    if (current == null) return const [];
    final offer = _offer;
    return [
      const SizedBox(height: 16),
      InfoRowsCard([
        InfoRow('Bouquet en cours', _currentLabel(current), key: const Key('tv-current-offer')),
        InfoRow('Prix de reconduction', formatFcfa(current.amount), key: const Key('tv-current-amount')),
      ]),
      sectionLabel('Que souhaitez-vous faire ?'),
      _OptionGrid(
        items: [
          ChoiceItem(id: 'renew', label: 'Reconduire', sub: _currentLabel(current)),
          const ChoiceItem(id: 'change', label: 'Changer de bouquet', sub: 'Bouquet, durée, options'),
        ],
        selected: _change ? 'change' : 'renew',
        onSelect: _mode,
      ),
      if (_change && _offers != null && _offers!.isNotEmpty) ...[
        sectionLabel('Bouquet'),
        _OptionGrid(
          items: [
            for (final o in _offers!)
              ChoiceItem(id: o.code, label: o.label, sub: 'Par mois, prix indicatif', price: o.amount),
          ],
          selected: _offerCode,
          onSelect: _pickOffer,
        ),
        ?sectionError('offer'),
        if (offer != null && offer.durations.isNotEmpty) ...[
          sectionLabel('Durée'),
          _OptionGrid(
            items: [for (final d in offer.durations) ChoiceItem(id: d.code, label: d.label)],
            selected: _duration,
            onSelect: (id) => setState(() {
              _duration = id;
              fieldErrors = {...fieldErrors}..remove('duration');
            }),
          ),
          ?sectionError('duration'),
        ],
        if (offer != null && offer.options.isNotEmpty) ...[
          sectionLabel('Options (facultatif)'),
          for (final o in offer.options) ...[
            checkTile(
              key: Key('tv-option-${o.code}'),
              value: _options.contains(o.code),
              onChanged: (v) => setState(() => v ? _options.add(o.code) : _options.remove(o.code)),
              title: o.label,
              trailing: o.amount == null ? null : '+ ${formatFcfa(o.amount!)}',
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
      if (!_change) ?sectionError('offer'),
    ];
  }
}

/// Facture d'électricité SBEE (`electricity-postpaid`, prix imposé) : référence client → factures
/// impayées → sélection (toutes par défaut : `invoiceReferences` omis) → devis.
class _ElectricityBillForm extends ConsumerStatefulWidget {
  const _ElectricityBillForm();

  @override
  ConsumerState<_ElectricityBillForm> createState() => _ElectricityBillFormState();
}

class _ElectricityBillFormState extends _LookupFormState<_ElectricityBillForm> {
  ElectricityAccount? _account;
  final _selected = <String>{};

  @override
  ServiceType get type => ServiceType.elecBill;

  @override
  String get lookupLabel => 'Voir mes factures';

  @override
  bool get lookedUp => _account != null;

  @override
  void resetLookup() {
    _account = null;
    _selected.clear();
  }

  @override
  Future<void> lookup() => runLookup(() async {
    final account = await ref.read(paymentRepositoryProvider).electricityInvoices(controller.text.trim());
    if (!mounted) return;
    setState(() {
      _account = account;
      _selected
        ..clear()
        ..addAll(account.invoices.map((i) => i.reference));
    });
  }, 'vérifiez la référence client et réessayez.');

  List<ElectricityInvoice> get _invoices => _account?.invoices ?? const [];

  bool get _all => _invoices.isNotEmpty && _invoices.every((i) => _selected.contains(i.reference));

  @override
  Map<String, String> get values => {
    'customerReference': controller.text,
    // Toutes les factures : `invoiceReferences` omis (le fournisseur règle toutes les impayées).
    'invoiceReferences': _all
        ? ''
        : [
            for (final i in _invoices)
              if (_selected.contains(i.reference)) i.reference,
          ].join(','),
  };

  @override
  Map<String, String> missingChoices() => {
    if (_invoices.isEmpty)
      'invoices': 'Aucune facture à régler pour cette référence.'
    else if (_selected.isEmpty)
      'invoices': 'Choisissez au moins une facture.',
  };

  void _toggle(String reference, bool on) => setState(() {
    on ? _selected.add(reference) : _selected.remove(reference);
    error = null;
    fieldErrors = {...fieldErrors}..remove('invoices');
  });

  @override
  List<Widget> sections() {
    final account = _account;
    if (account == null) return const [];
    final total = _invoices.where((i) => _selected.contains(i.reference)).fold<num>(0, (t, i) => t + i.amount);
    return [
      const SizedBox(height: 16),
      InfoRowsCard([
        InfoRow('Abonné', account.name, key: const Key('bill-holder')),
        if (account.reference.isNotEmpty) InfoRow('Référence client', account.reference),
      ]),
      if (_invoices.isEmpty)
        const EmptyState(message: 'Aucune facture impayée pour cette référence.', icon: Symbols.task_alt_rounded)
      else ...[
        Row(
          children: [
            Expanded(child: sectionLabel('Factures impayées')),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextButton(
                key: const Key('invoices-all'),
                onPressed: () => setState(() {
                  _all ? _selected.clear() : _selected.addAll(_invoices.map((i) => i.reference));
                  fieldErrors = {...fieldErrors}..remove('invoices');
                }),
                child: Text(_all ? 'Tout désélectionner' : 'Tout sélectionner'),
              ),
            ),
          ],
        ),
        for (final i in _invoices) ...[
          checkTile(
            key: Key('invoice-${i.reference}'),
            value: _selected.contains(i.reference),
            onChanged: (v) => _toggle(i.reference, v),
            title: 'Facture ${i.period}',
            subtitle: i.reference,
            trailing: formatFcfa(i.amount),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Total des factures choisies',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
              ),
              Text(
                formatFcfa(total),
                key: const Key('bill-total'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KColors.primary),
              ),
            ],
          ),
        ),
      ],
      ?sectionError('invoices'),
    ];
  }
}
