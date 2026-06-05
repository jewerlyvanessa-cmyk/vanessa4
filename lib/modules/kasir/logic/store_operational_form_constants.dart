/// Kategori bawaan jika API kategori belum tersedia.
abstract final class StoreOperationalFormConstants {
  StoreOperationalFormConstants._();

  static const expenseCategories = <String>[
    'ATK & perlengkapan',
    'Listrik / utilitas',
    'Air',
    'Transport / kirim',
    'Konsumsi',
    'Maintenance & perbaikan',
    'Lainnya (pengeluaran)',
  ];

  static const incomeCategories = <String>[
    'Pendapatan lain (bukan order)',
    'Pengembalian / koreksi kas (+)',
    'Pendapatan jasa / komisi',
    'Lainnya (pemasukan)',
  ];
}
