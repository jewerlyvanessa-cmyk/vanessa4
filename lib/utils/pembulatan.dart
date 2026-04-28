/// Fungsi pembulatan sesuai ketentuan:
/// - Round UP ke kelipatan 5.000 terdekat (sesuai backend: CEIL(total/5000)*5000)
int pembulatan(int angka) {
  if (angka <= 0) return 0;
  return ((angka + 4999) ~/ 5000) * 5000;
}
