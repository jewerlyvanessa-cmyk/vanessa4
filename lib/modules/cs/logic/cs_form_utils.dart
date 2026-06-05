int? csToInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

double csParseMoney(String raw) {
  final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final v = double.tryParse(s);
  return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
}
