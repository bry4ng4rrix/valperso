/// Petites fonctions de lecture du JSON renvoyé par l'API.
typedef Json = Map<String, dynamic>;

double toDouble(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

double? toDoubleOrNull(Object? value) => value == null ? null : toDouble(value);

int toInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? toDate(Object? value) => value is String ? DateTime.tryParse(value) : null;

String? toStringOrNull(Object? value) => value?.toString();

List<T> toList<T>(Object? value, T Function(Json json) parse) =>
    value is List ? value.whereType<Map>().map((item) => parse(Json.from(item))).toList() : <T>[];

T? toObject<T>(Object? value, T Function(Json json) parse) => value is Map ? parse(Json.from(value)) : null;
