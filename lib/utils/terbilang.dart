// Fungsi terbilang: mengubah angka menjadi teks dalam bahasa Indonesia
String terbilang(int angka) {
  List<String> satuan = [
    '', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan', 'sepuluh', 'sebelas'
  ];
  if (angka < 12) {
    return satuan[angka];
  } else if (angka < 20) {
    return '${terbilang(angka - 10)} belas';
  } else if (angka < 100) {
    return '${terbilang(angka ~/ 10)} puluh ${terbilang(angka % 10)}'.trim();
  } else if (angka < 200) {
    return 'seratus ${terbilang(angka - 100)}'.trim();
  } else if (angka < 1000) {
    return '${terbilang(angka ~/ 100)} ratus ${terbilang(angka % 100)}'.trim();
  } else if (angka < 2000) {
    return 'seribu ${terbilang(angka - 1000)}'.trim();
  } else if (angka < 1000000) {
    return '${terbilang(angka ~/ 1000)} ribu ${terbilang(angka % 1000)}'.trim();
  } else if (angka < 1000000000) {
    return '${terbilang(angka ~/ 1000000)} juta ${terbilang(angka % 1000000)}'.trim();
  } else {
    return angka.toString();
  }
}
