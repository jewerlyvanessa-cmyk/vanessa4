-- Tabel untuk menyimpan kondisi barang saat buyback
CREATE TABLE IF NOT EXISTS item_conditions (
  condition_id BIGSERIAL PRIMARY KEY,
  item_id BIGINT REFERENCES items(item_id) ON DELETE CASCADE,
  order_id BIGINT REFERENCES orders(order_id) ON DELETE CASCADE,

  -- Kondisi fisik barang
  kondisi_fisik TEXT CHECK(kondisi_fisik IN ('BAIK','RUSAK_RINGAN','RUSAK_BERAT','RUSAK_PARAH')),
  kerusakan TEXT[], -- Array untuk multiple kerusakan: ['LECET','KARAT','PATAH', dll]

  -- Data berat
  berat_awal NUMERIC(10,2), -- Berat sebelum penyesuaian (jika ada)
  berat_akhir NUMERIC(10,2), -- Berat akhir setelah penyesuaian
  penyesuaian_berat TEXT, -- Alasan penyesuaian: 'POTONG_0.3G', 'BERSIHKAN_KARAT', dll

  -- Penilaian keaslian dan sertifikat
  keaslian TEXT CHECK(keaslian IN ('ASLI','KW','TIDAK_DIKETAHUI')),
  sertifikat TEXT CHECK(sertifikat IN ('ADA','TIDAK_ADA','TIDAK_DIKETAHUI')),

  -- Penilaian nilai
  nilai_resale BIGINT, -- Estimasi nilai jual kembali
  harga_beli BIGINT, -- Harga yang dibayar saat buyback

  -- Catatan dan dokumentasi
  catatan_kondisi TEXT, -- Catatan detail kondisi barang
  foto_kondisi TEXT[], -- Array URL foto kondisi (multiple angles)

  -- Audit trail
  dinilai_oleh BIGINT REFERENCES users(user_id),
  tanggal_penilaian TIMESTAMP DEFAULT now(),
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Index untuk performa
CREATE INDEX IF NOT EXISTS idx_item_conditions_item_id ON item_conditions(item_id);
CREATE INDEX IF NOT EXISTS idx_item_conditions_order_id ON item_conditions(order_id);
CREATE INDEX IF NOT EXISTS idx_item_conditions_kondisi_fisik ON item_conditions(kondisi_fisik);

-- Trigger untuk update updated_at
CREATE OR REPLACE FUNCTION update_item_conditions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_item_conditions_updated_at
  BEFORE UPDATE ON item_conditions
  FOR EACH ROW
  EXECUTE FUNCTION update_item_conditions_updated_at();
