/// Label tile & judul sheet pengelompokan menu dashboard (toko / warehouse / workshop).
abstract final class ModuleMenuGroupLabels {
  ModuleMenuGroupLabels._();

  static const toko = 'TOKO';
  static const warehouse = 'WAREHOUSE';
  static const workshop = 'WORKSHOP';
  static const gudang = 'GUDANG';

  /// Transfer ke cabang sejenis (label tile per modul admin).
  static const antarToko = 'ANTAR TOKO';
  static const antarWorkshop = 'ANTAR WORKSHOP';
  static const antarWarehouse = 'ANTAR WAREHOUSE';

  static const sheetToko = 'Toko (etalase)';
  static const sheetWarehouse = 'Warehouse (gudang)';
  static const sheetWorkshop = 'Workshop';
  static const sheetGudang = 'Gudang';
  static const sheetAntarToko = 'Antar toko';
  static const sheetAntarWorkshop = 'Antar workshop';
  static const sheetAntarWarehouse = 'Antar warehouse';
}
