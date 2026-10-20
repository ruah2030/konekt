import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';

/// Lien sous les cases (« Renvoyer un code », « Code secret oublié ? »…).
class CodeEntryLink {
  const CodeEntryLink({required this.label, required this.onTap, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final bool enabled;
}

/// Écran de saisie d'un code à 6 chiffres (OTP, vérification, PIN) avec pavé numérique interne.
/// La saisie est contrôlée par le parent ([value] / [onChanged]) ; [onCompleted] est appelé
/// automatiquement quand le 6ᵉ chiffre est saisi.
class CodeEntryView extends StatefulWidget {
  const CodeEntryView({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onCompleted,
    this.step,
    this.obscure = false,
    this.error,
    this.link,
    this.busy = false,
    this.onBack,
    this.length = 6,
    this.submitDelay = const Duration(milliseconds: 200),
    super.key,
  });

  final String title;
  final String subtitle;

  /// Pastille d'étape (« Étape 1 sur 3 »), masquée si nulle ou vide.
  final String? step;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final bool obscure;
  final ApiFailure? error;
  final CodeEntryLink? link;
  final bool busy;

  /// Bouton retour affiché si non nul.
  final VoidCallback? onBack;
  final int length;

  /// Laisse le temps de voir la dernière case remplie avant la validation.
  final Duration submitDelay;

  @override
  State<CodeEntryView> createState() => _CodeEntryViewState();
}

class _CodeEntryViewState extends State<CodeEntryView> {
  Timer? _submitTimer;

  @override
  void dispose() {
    _submitTimer?.cancel();
    super.dispose();
  }

  void _digit(String d) {
    if (widget.busy || widget.value.length >= widget.length || (_submitTimer?.isActive ?? false)) return;
    final next = widget.value + d;
    widget.onChanged(next);
    if (next.length == widget.length) {
      _submitTimer = Timer(widget.submitDelay, () {
        if (mounted) widget.onCompleted(next);
      });
    }
  }

  void _delete() {
    if (widget.busy || widget.value.isEmpty || (_submitTimer?.isActive ?? false)) return;
    widget.onChanged(widget.value.substring(0, widget.value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final step = widget.step;
    final link = widget.link;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  SizedBox(
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
                      child: Row(
                        children: [
                          if (widget.onBack != null)
                            IconButton(
                              key: const Key('code-back'),
                              tooltip: 'Retour',
                              onPressed: widget.onBack,
                              icon: const Icon(Symbols.arrow_back_rounded),
                            ),
                          const Spacer(),
                          if (step != null && step.isNotEmpty)
                            Container(
                              key: const Key('code-step'),
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: KColors.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                step,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KColors.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: KColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Symbols.shield_lock_rounded, size: 30, fill: 1, color: Color(0xFFB87A0E)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.title,
                          key: const Key('code-title'),
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(
                            fontSize: 24,
                            height: 1.25,
                            letterSpacing: -0.36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 310),
                          child: Text(
                            widget.subtitle,
                            key: const Key('code-subtitle'),
                            textAlign: TextAlign.center,
                            style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  PinDots(
                    value: widget.value,
                    length: widget.length,
                    obscure: widget.obscure,
                    hasError: widget.error != null && widget.value.isEmpty,
                  ),
                  Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    alignment: Alignment.topCenter,
                    child: widget.busy
                        ? const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                          )
                        : widget.error != null
                        ? ErrorBlock(widget.error!)
                        : null,
                  ),
                  if (link != null)
                    TextButton(
                      key: const Key('code-link'),
                      onPressed: link.enabled && !widget.busy ? link.onTap : null,
                      style: TextButton.styleFrom(disabledForegroundColor: KColors.outline),
                      child: Text(link.label),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: NumericKeypad(onDigit: _digit, onDelete: _delete, enabled: !widget.busy),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
