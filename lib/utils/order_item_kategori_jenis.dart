// Kategori & jenis item — selaras form order Jual (CS) dan buyback manual.
// Satu sumber kebenaran agar tidak drift antar layar.

const List<String> orderItemKategoriOptions = [
  'PERHIASAN',
  'AKSESORIES',
  'LOGAM MULIA',
];

const Map<String, List<String>> orderItemJenisByKategori = {
  'PERHIASAN': [
    'KALUNG',
    'GELANG',
    'ANTING',
    'CINCIN',
    'LIONTIN',
  ],
  'AKSESORIES': [
    'GELANG TALI',
    'PAKU EMAS',
    'KOTAK CINCIN',
    'LIONTIN MAINAN',
    'CINCIN AKRILIK',
    'GELANG AKRILIK',
  ],
  'LOGAM MULIA': [
    'ANTAM',
    'UBS',
    'GALERI24',
    'LOTUS ARCHI',
    'LAINNYA',
  ],
};

/// Daftar jenis untuk [kategori] yang dikenal; kosong jika kategori tidak valid.
List<String> orderItemJenisOptionsForKategori(String kategori) {
  return orderItemJenisByKategori[kategori.trim()] ?? const <String>[];
}

bool orderItemIsValidKategoriJenisPair(String kategori, String jenis) {
  final opts = orderItemJenisByKategori[kategori.trim()];
  if (opts == null) return false;
  return opts.contains(jenis.trim());
}
