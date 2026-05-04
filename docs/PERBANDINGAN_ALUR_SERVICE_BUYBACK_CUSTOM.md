# 🔄 PERBANDINGAN ALUR SERVICE, BUYBACK, DAN CUSTOM

## 1️⃣ ALUR SERVICE 🔧

### Timeline
```
Pelanggan Datang
    ↓
CS Buat Order Service
    ↓ (STATUS: draft)
Pilih Customer
    ↓
Input Detail Barang
    ├─ Nama Barang
    ├─ Berat
    ├─ Material
    └─ Kadar Kemurnian
    ↓
Input Keterangan Service
    ├─ Keluhan (rusak, bengkok, dll)
    └─ Perbaikan yang diinginkan
    ↓
Scan QR (opsional)
    ↓
UPLOAD FOTO BARANG (WAJIB)
    ├─ Dokumentasi kondisi awal
    └─ Preview sebelum upload
    ↓
SUBMIT ORDER
    ↓ (STATUS: on-service)
Generate Nota/Faktur
    ↓
Barang dikirim ke Workshop
    ↓ (STATUS: sent-to-workshop)
Tukang: Assign, Input Progres, Foto
    ↓ (STATUS: in-workshop)
Tukang: Selesai
    ↓ (STATUS: done-workshop)
Barang siap diambil
    ↓ (STATUS: ready-for-pickup)
Pelanggan Ambil
    ↓ (STATUS: completed)
SELESAI ✅
```

### Data Service Order
```json
{
  "order_type": "service",
  "status": "on-service",
  "customer_id": 123,
  "customer_name": "Andi Wijaya",
  "customer_phone": "08123456789",
  "customer_address": "Jl. Merdeka No. 10",
  "nama_item": "Gelang Emas",
  "material": "Emas",
  "kadar": "22K",
  "berat": "10",
  "keterangan_service": "Bengkok, perlu dibentuk ulang",
  "foto_url": "http://...",
  "scanned_qr": "ABC123XYZ",
  "created_at": "2026-01-04 15:30:00"
}
```

### Database Update
```sql
-- Table: orders
INSERT INTO orders (
  order_type, status, customer_id, item_id, 
  name, weight, material, purity, photo_url, 
  scanned_qr, branch_id, user_id, created_at
) VALUES (
  'service', 'on-service', 123, NULL,
  'Gelang Emas', 10, 'Emas', '22K', 'url',
  'ABC123', 1, 1, NOW()
);

-- Table: items
UPDATE items SET 
  status = 'on-service',
  updated_at = NOW()
WHERE item_id = 456;

-- Table: stock_history
INSERT INTO stock_history (
  item_id, old_status, new_status, changed_by, timestamp
) VALUES (456, 'ready', 'on-service', 1, NOW());
```

---

## 2️⃣ ALUR BUYBACK 💰

### Timeline
```
Pelanggan Datang dengan Barang Bekas
    ↓
CS Buat Order Buyback
    ↓ (STATUS: draft)
Pilih Customer
    ↓
Input Detail Barang
    ├─ Nama Barang
    ├─ Berat
    ├─ Material
    ├─ Kadar Kemurnian
    └─ HARGA BELI
    ↓
Scan QR (opsional)
    ├─ Jika barang dari order lama pelanggan
    └─ Dokumentasi barang yang dibeli
    ↓
UPLOAD FOTO BARANG (WAJIB)
    ├─ Dokumentasi kondisi barang
    └─ Bukti kepemilikan
    ↓
SUBMIT ORDER
    ↓ (STATUS: buyback)
Generate Nota/Faktur
    ↓
Hitung Total Pembayaran
    ├─ Harga Beli
    └─ Diskon (jika ada)
    ↓
Proses Pembayaran
    ├─ DP (Down Payment) atau
    └─ Pelunasan Penuh
    ↓
Barang Masuk ke STOK READY
    ↓ (STATUS: ready - untuk dijual kembali)
Admin: Input ke Inventory
    ↓
SELESAI ✅
```

### Data Buyback Order
```json
{
  "order_type": "buyback",
  "status": "buyback",
  "customer_id": 123,
  "customer_name": "Andi Wijaya",
  "customer_phone": "08123456789",
  "customer_address": "Jl. Merdeka No. 10",
  "nama_item": "Cincin Emas Bekas",
  "material": "Emas",
  "kadar": "70%",
  "berat": "5",
  "harga_beli": "2500000",
  "foto_url": "http://...",
  "scanned_qr": "XYZ789ABC",
  "created_at": "2026-01-04 16:00:00"
}
```

### Database Update
```sql
-- Table: orders
INSERT INTO orders (
  order_type, status, customer_id, item_id,
  name, weight, material, purity, photo_url,
  scanned_qr, branch_id, user_id, created_at
) VALUES (
  'buyback', 'buyback', 123, NULL,
  'Cincin Emas Bekas', 5, 'Emas', '70%', 'url',
  'XYZ789', 1, 1, NOW()
);

-- Table: items (NEW ITEM)
INSERT INTO items (
  name, weight, material, purity, status, 
  branch_id, photo_url, created_at
) VALUES (
  'Cincin Emas Bekas (Buyback)', 5, 'Emas', '70%',
  'ready', 1, 'url', NOW()
);

-- Table: stock_history
INSERT INTO stock_history (
  item_id, old_status, new_status, changed_by, timestamp
) VALUES (789, NULL, 'ready', 1, NOW());

-- Table: payments
INSERT INTO payments (
  order_id, amount, type, status, created_at
) VALUES (456, 2500000, 'buyback', 'pending', NOW());
```

---

## 3️⃣ ALUR CUSTOM ⚙️

### Timeline
```
Pelanggan Pesan Barang Custom
    ↓
CS Buat Order Custom
    ↓ (STATUS: draft)
Pilih Customer
    ↓
Input Spesifikasi Detail
    ├─ Nama Barang yang Dipesan
    ├─ Spesifikasi Detail (ukuran, bahan, warna, dll)
    ├─ Material
    ├─ Kadar Kemurnian
    ├─ Berat Target
    └─ Estimasi Waktu Pengerjaan
    ↓
UPLOAD FOTO DESAIN/REFERENSI (WAJIB)
    ├─ Referensi desain dari pelanggan
    └─ Atau foto dari internet/catalog
    ↓
SUBMIT ORDER
    ↓ (STATUS: production)
Generate Nota/Faktur
    ↓
Hitung Estimasi Biaya
    ├─ Biaya Material
    ├─ Biaya Pengerjaan
    └─ Total Harga
    ↓
Proses Pembayaran
    ├─ DP (Down Payment) - minimal 50%
    └─ Pelunasan saat barang selesai
    ↓
Barang Dikirim ke Workshop
    ↓ (STATUS: sent-to-workshop)
Workshop: Assign ke Tukang
    ↓ (STATUS: in-workshop)
Tukang: 
    ├─ Input Stok Bahan Digunakan
    ├─ Update Progres
    ├─ Upload Foto Proses
    └─ Foto Hasil Jadi
    ↓ (STATUS: done-workshop)
Admin: Review & Approval
    ↓
Barang Siap Diambil
    ↓ (STATUS: ready-for-pickup)
Pelanggan Ambil Barang Custom
    ↓
Proses Pembayaran Pelunasan
    ↓ (STATUS: completed)
SELESAI ✅
```

### Data Custom Order
```json
{
  "order_type": "custom",
  "status": "production",
  "customer_id": 123,
  "customer_name": "Andi Wijaya",
  "customer_phone": "08123456789",
  "customer_address": "Jl. Merdeka No. 10",
  "nama_item": "Cincin Pernikahan Custom",
  "spesifikasi": "Ukuran 18, batu mulia ruby merah, warna emas kuning, design vintage",
  "material": "Emas",
  "kadar": "22K",
  "berat_target": "8",
  "estimasi_waktu": "2 minggu",
  "foto_url": "http://...",
  "created_at": "2026-01-04 14:30:00"
}
```

### Database Update
```sql
-- Table: orders
INSERT INTO orders (
  order_type, status, customer_id, item_id,
  name, weight, material, purity, photo_url,
  branch_id, user_id, created_at
) VALUES (
  'custom', 'production', 123, NULL,
  'Cincin Pernikahan Custom', 8, 'Emas', '22K', 'url',
  1, 1, NOW()
);

-- Table: items (DRAFT - akan diupdate saat selesai)
INSERT INTO items (
  name, weight, material, purity, status,
  branch_id, photo_url, created_at
) VALUES (
  'Cincin Pernikahan Custom (Draft)', 8, 'Emas', '22K',
  'production', 1, 'url', NOW()
);

-- Table: stock_history
INSERT INTO stock_history (
  item_id, old_status, new_status, changed_by, timestamp
) VALUES (999, NULL, 'production', 1, NOW());

-- Table: payments
INSERT INTO payments (
  order_id, amount, type, status, created_at
) VALUES (
  457, 4000000, 'dp', 'pending', NOW()
);
```

---

## 📊 TABEL PERBANDINGAN LENGKAP

| Aspek | **SERVICE** | **BUYBACK** | **CUSTOM** |
|-------|-----------|-----------|----------|
| **Tujuan** | Perbaikan/Perawatan | Pembelian Barang Bekas | Pemesanan Barang Baru |
| **Sumber Item** | Dari Pelanggan | Dari Pelanggan | Pesanan Pelanggan |
| **Manual Input** | Ya | Ya | Ya (WAJIB) |
| **Foto** | WAJIB | WAJIB | WAJIB (referensi) |
| **QR Code** | Opsional | Opsional | TIDAK |
| **Field Khusus** | Keterangan Service | Harga Beli | Spesifikasi, Est. Waktu |
| **Status Awal** | on-service | buyback | production |
| **Tujuan Akhir** | Kembali ke Pelanggan | Masuk Stok (Jual Ulang) | Kembali ke Pelanggan |
| **Melibatkan Workshop** | Ya | Tidak | Ya |
| **Melibatkan Pembayaran** | Ya | Ya | Ya |
| **Lead Time** | Bervariasi | Instan | 1-4 minggu |
| **Item Status Akhir** | ready-for-pickup | ready (stok) | ready-for-pickup |

---

## 🔄 STATUS PROGRESSION

### SERVICE
```
draft → on-service → sent-to-workshop → in-workshop 
→ done-workshop → ready-for-pickup → completed
```

### BUYBACK
```
draft → buyback → ready (stok untuk dijual kembali)
```

### CUSTOM
```
draft → production → sent-to-workshop → in-workshop
→ done-workshop → ready-for-pickup → completed
```

---

## 💾 IMPLEMENTASI DATABASE

### Orders Table
```sql
CREATE TABLE orders (
  order_id BIGSERIAL PRIMARY KEY,
  order_type TEXT CHECK(order_type IN ('jual','buyback','service','custom')),
  customer_id BIGINT REFERENCES customers(customer_id),
  item_id BIGINT REFERENCES items(item_id) NULL,
  source_order_item_id BIGINT NULL,
  name TEXT,
  weight NUMERIC(10,2),
  material TEXT,
  purity TEXT,
  photo_url TEXT,
  scanned_qr TEXT,
  status TEXT CHECK(status IN (
    'draft','on-service','buyback','production',
    'sent-to-workshop','in-workshop','done-workshop',
    'ready-for-pickup','completed'
  )),
  branch_id BIGINT REFERENCES branches(branch_id),
  user_id BIGINT REFERENCES users(user_id),
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);
```

### Items Table
```sql
CREATE TABLE items (
  item_id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  weight NUMERIC(10,2),
  material TEXT,
  purity TEXT,
  status TEXT CHECK(status IN (
    'ready','reserved','sold','buyback','on-service',
    'on-custom','sent-to-workshop','in-workshop',
    'done-workshop','ready-for-pickup','transfer','production','lost'
  )),
  branch_id BIGINT REFERENCES branches(branch_id),
  photo_url TEXT,
  source TEXT,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);
```

---

## 📈 FLOW DIAGRAM (ASCII)

```
┌─────────────────────────────────────────────────────────────┐
│                    CUSTOMER DATANG                          │
└────────┬────────────────────┬─────────────────────┬─────────┘
         │                    │                     │
         ▼                    ▼                     ▼
    ┌────────┐            ┌────────┐          ┌──────────┐
    │SERVICE │            │BUYBACK │          │  CUSTOM  │
    └────────┘            └────────┘          └──────────┘
         │                    │                     │
    Perbaikan            Beli Barang         Pesan Custom
    Barang Lama          Barang Bekas      Barang Baru
         │                    │                     │
         ▼                    ▼                     ▼
    ┌─────────────┐      ┌──────────┐         ┌──────────┐
    │   on-       │      │ buyback  │         │production│
    │  service    │      │ (stok)   │         │(workshop)│
    └─────────────┘      └──────────┘         └──────────┘
         │                    │                     │
         ▼                    ▼                     ▼
    Workshop ──────────────────┐           Workshop
    Perbaikan      Stok Jual    │           Produksi
         │                      │                │
         ▼                      ▼                ▼
    ready-for-                 ready      ready-for-
    pickup (ambil)          (dijual)       pickup (ambil)
         │                      │                │
         ▼                      ▼                ▼
    ┌──────────┐            ┌──────────┐   ┌──────────┐
    │Pelanggan │            │Pembeli   │   │Pelanggan │
    │Ambil     │            │Baru Beli │   │Ambil     │
    │Barang    │            │Barang    │   │Barang    │
    └──────────┘            └──────────┘   └──────────┘
```

---

## ✅ CHECKLIST IMPLEMENTASI

### Service Page
- [x] Customer autocomplete
- [x] Item detail input
- [x] Keterangan service
- [x] QR scan opsional
- [x] Foto upload wajib
- [x] Form validation
- [x] API integration

### Buyback Page
- [x] Customer autocomplete
- [x] Item detail input
- [x] Harga beli field
- [x] QR scan opsional
- [x] Foto upload wajib
- [x] Form validation
- [x] API integration

### Custom Page
- [x] Customer autocomplete
- [x] Spesifikasi detail
- [x] Berat target
- [x] Estimasi waktu
- [x] Foto upload wajib (referensi)
- [x] QR scan hidden
- [x] Form validation
- [x] API integration

---

**Dibuat**: 4 Januari 2026  
**Status**: ✅ DOKUMENTASI LENGKAP
