import 'json.dart';

enum PromoPlacement { home, receipt, history }

enum PromoTheme { navy, gold, mint }

class PromoAction {
  const PromoAction({required this.type, required this.target});
  factory PromoAction.fromJson(Json j) => PromoAction(type: j.str('type'), target: j.str('target'));

  /// `url` (lien externe) ou `service` (ouvre un service de l'app, ex. `data`).
  final String type;
  final String target;
  bool get isService => type == 'service';
}

/// Publicité pilotée depuis le back-office (`GET /v1/promotions`).
class Promotion {
  const Promotion({
    required this.id,
    required this.placement,
    required this.priority,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.cta,
    required this.action,
    required this.theme,
  });

  factory Promotion.fromJson(Json j) => Promotion(
    id: j.str('id'),
    placement: PromoPlacement.values.byName(j.str('placement')),
    priority: j.integer('priority'),
    eyebrow: j.str('eyebrow'),
    title: j.str('title'),
    body: j.strOrNull('body') ?? '',
    cta: j.str('cta'),
    action: PromoAction.fromJson(j.obj('action')),
    theme: PromoTheme.values.asNameMap()[j.str('theme')] ?? PromoTheme.navy,
  );

  final String id;
  final PromoPlacement placement;
  final int priority;
  final String eyebrow;
  final String title;
  final String body;
  final String cta;
  final PromoAction action;
  final PromoTheme theme;
}
