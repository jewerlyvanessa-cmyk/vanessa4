/// Fungsi pembulatan sesuai ketentuan:
/// - Jika ribuan di bawah 5000 dibulatkan ke 5000
/// - Jika ribuan di atas 5000 dibulatkan ke puluhan terdekat berikutnya
int pembulatan(int angka) {
  if (angka < 5000) {
    return 5000;
  }
  int ribuan = angka ~/ 1000 * 1000;
  if (ribuan == 5000) {
    return 5000;
  }
  if (ribuan < angka) {
    // Jika lebih dari 5000, bulatkan ke puluhan terdekat berikutnya
    int sisa = angka % 10000;
    if (sisa == 0) return angka;
    return angka - sisa + 10000;
  }
  return angka;
}
