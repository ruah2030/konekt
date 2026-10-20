/// Petits utilitaires de lecture JSON typée (pas de génération de code).
typedef Json = Map<String, dynamic>;

extension JsonRead on Json {
  String str(String k) => this[k] as String;
  String? strOrNull(String k) => this[k] as String?;
  int integer(String k) => (this[k] as num).toInt();
  int? intOrNull(String k) => (this[k] as num?)?.toInt();
  bool boolean(String k, {bool fallback = false}) => this[k] as bool? ?? fallback;
  DateTime date(String k) => DateTime.parse(this[k] as String).toLocal();
  DateTime? dateOrNull(String k) => this[k] == null ? null : DateTime.parse(this[k] as String).toLocal();
  Json obj(String k) => Map<String, dynamic>.from(this[k] as Map);
  List<Json> list(String k) =>
      ((this[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  List<String> strings(String k) => ((this[k] as List?) ?? const []).cast<String>();
}
