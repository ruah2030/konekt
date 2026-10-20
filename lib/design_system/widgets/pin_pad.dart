import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// 6 cases de code. [obscure] affiche « ● » (PIN) au lieu des chiffres (OTP).
class PinDots extends StatelessWidget {
  const PinDots({required this.value, this.length = 6, this.obscure = false, this.hasError = false, super.key});
  final String value;
  final int length;
  final bool obscure;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < value.length;
        final current = i == value.length;
        final border = hasError
            ? KColors.error
            : current
            ? KColors.primary
            : filled
            ? const Color(0xFFC7C9E6)
            : KColors.outlineVariant;
        return Container(
          key: Key('pin-dot-$i'),
          width: 46,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: KColors.fieldFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            filled ? (obscure ? '●' : value[i]) : '',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: KColors.primary),
          ),
        );
      }),
    );
  }
}

/// Pavé numérique interne (pas de clavier système pour PIN/OTP).
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({required this.onDigit, required this.onDelete, this.enabled = true, super.key});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final k in keys)
          if (k.isEmpty)
            const SizedBox.shrink()
          else
            InkWell(
              key: Key('key-$k'),
              borderRadius: BorderRadius.circular(18),
              onTap: !enabled
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      k == 'del' ? onDelete() : onDigit(k);
                    },
              child: Center(
                child: k == 'del'
                    ? const Icon(Symbols.backspace_rounded, color: KColors.primary)
                    : Text(
                        k,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: KColors.primary),
                      ),
              ),
            ),
      ],
    );
  }
}
