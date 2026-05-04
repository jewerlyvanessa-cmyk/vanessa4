# Dokumentasi Implementasi Service, Buyback, dan Custom Page

## 📋 Ringkas
Telah mengimplementasikan tiga halaman Customer Service yang komprehensif sesuai dengan alur bisnis yang telah didefinisikan di `blueprint.txt`.

---

## 1️⃣ SERVICE PAGE (`lib/modules/cs/pages/service_page.dart`)

### Alur Service
```
Pelanggan datang dengan barang untuk diperbaiki
    ↓
CS buat Order Service
    ↓
Pilih Customer (autocomplete dari database)
    ↓
Input Detail Item (nama, berat, material, kadar)
    ↓
Input Keterangan Service (keluhan/perbaikan yang diinginkan)
    ↓
Scan QR (opsional)
    ↓
UPLOAD FOTO WAJIB (dokumentasi kondisi awal)
    ↓
Submit → Status: on-service
    ↓
Kirim ke Workshop
```

### Fitur Utama
- ✅ **Customer Selection**: Autocomplete dari database dengan field phone & address read-only
- ✅ **Pilih dari Order Lama**: Opsional (UI ready, backend belum)
- ✅ **Detail Item**: Nama, Berat, Material, Kadar
- ✅ **Keterangan Service**: Field besar untuk deskripsi keluhan/perbaikan
- ✅ **QR Scan**: Opsional dengan mobile_scanner
- ✅ **Foto Upload**: WAJIB, dengan preview sebelum submit
- ✅ **Form Validation**: Semua field wajib tervalidasi
- ✅ **Status**: Otomatis `on-service` dan dikirim ke workshop

### Data yang Dikirim ke Backend
```dart
{
  'order_type': 'service',
  'status': 'on-service',
  'customer_id': customer.id,
  'nama_item': 'Gelang Emas',
  'material': 'Emas',
  'kadar': '22K',
  'berat': '10',
  'keterangan': 'Bengkok, perlu dibentuk ulang',
  'foto_new': 'url_dari_upload',
  'scanned_qr': 'optional',
  'user_id': userId,
  'branch_id': branchId,
}
```

---

## 2️⃣ BUYBACK PAGE (`lib/modules/cs/pages/buyback_page.dart`)

### Alur Buyback
```
Pelanggan datang dengan barang untuk dijual kembali
    ↓
CS buat Order Buyback
    ↓
Pilih Customer
    ↓
Input Detail Item (nama, berat, material, kadar, harga beli)
    ↓
Scan QR (opsional)
    ↓
UPLOAD FOTO WAJIB (dokumentasi kondisi barang)
    ↓
Submit → Status: buyback
    ↓
Barang masuk ke STOK READY untuk dijual ulang
```

### Fitur Utama
- ✅ **Customer Selection**: Sama seperti Service (autocomplete)
- ✅ **Detail Item**: Nama, Berat, Material, Kadar, **Harga Beli**
- ✅ **QR Scan**: Opsional
- ✅ **Foto Upload**: WAJIB untuk dokumentasi kondisi barang
- ✅ **Form Validation**: Semua field validasi
- ✅ **Status**: Otomatis `buyback` dan masuk ke stok

### Data yang Dikirim ke Backend
```dart
{
  'order_type': 'buyback',
  'status': 'buyback',
  'customer_id': customer.id,
  'nama_item': 'Cincin Emas',
  'material': 'Emas',
  'kadar': '70%',
  'berat': '5',
  'harga_beli': '2500000',
  'foto_new': 'url_dari_upload',
  'scanned_qr': 'optional',
  'user_id': userId,
  'branch_id': branchId,
}
```

---

## 3️⃣ CUSTOM PAGE (`lib/modules/cs/pages/custom_page.dart`)

### Alur Custom
```
Pelanggan pesan barang custom
    ↓
CS buat Order Custom
    ↓
Pilih Customer
    ↓
Input Spesifikasi Detail (nama, spesifikasi, material, kadar, berat target, estimasi waktu)
    ↓
UPLOAD FOTO WAJIB (referensi/desain)
    ↓
Scan QR: TIDAK ADA (barang belum ada)
    ↓
Submit → Status: production
    ↓
Barang dikirim ke Workshop untuk produksi
```

### Fitur Utama
- ✅ **Customer Selection**: Autocomplete seperti yang lain
- ✅ **Spesifikasi Detail**: Field besar untuk deskripsi lengkap
- ✅ **Detail Item**: Material, Kadar, Berat Target, Estimasi Waktu
- ✅ **Foto Upload**: WAJIB (referensi/desain barang)
- ✅ **QR Scan**: TIDAK ADA (barang custom belum ada)
- ✅ **Form Validation**: Semua validasi
- ✅ **Status**: Otomatis `production` untuk workshop

### Data yang Dikirim ke Backend
```dart
{
  'order_type': 'custom',
  'status': 'production',
  'customer_id': customer.id,
  'nama_item': 'Cincin Pernikahan Custom',
  'spesifikasi': 'Ukuran 18, batu mulia ruby, warna emas kuning',
  'material': 'Emas',
  'kadar': '22K',
  'berat_target': '8',
  'estimasi_waktu': '2 minggu',
  'foto_new': 'url_dari_upload',
  'user_id': userId,
  'branch_id': branchId,
}
```

---

## 🔄 Fitur Umum Ketiga Page

| Fitur | Service | Buyback | Custom |
|-------|---------|---------|--------|
| **Customer Autocomplete** | ✅ | ✅ | ✅ |
| **Detail Item** | ✅ | ✅ | ✅ |
| **QR Scan** | ✅ Opsional | ✅ Opsional | ❌ |
| **Foto Upload** | ✅ WAJIB | ✅ WAJIB | ✅ WAJIB |
| **Form Validation** | ✅ | ✅ | ✅ |
| **Image Compression** | ✅ | ✅ | ✅ |
| **Loading State** | ✅ | ✅ | ✅ |
| **Error Handling** | ✅ | ✅ | ✅ |
| **Navigator ke Faktur** | ✅ | ✅ | ✅ |

---

## 🛠️ Teknologi yang Digunakan

- **Flutter**: UI Framework
- **Riverpod**: State Management untuk customer list
- **mobile_scanner**: QR Code scanning (Service & Buyback)
- **image_picker**: Camera untuk ambil foto
- **flutter_image_compress**: Kompresi foto sebelum upload
- **http**: API communication dengan backend

---

## 📡 Backend API yang Dibutuhkan

### 1. POST `/orders` - Submit Order
Menerima data order (service/buyback/custom) dan membuat order baru.

**Request Body**:
```json
{
  "order_type": "service|buyback|custom",
  "status": "on-service|buyback|production",
  "customer_id": 123,
  "nama_item": "Gelang Emas",
  "material": "Emas",
  "kadar": "22K",
  "berat": "10",
  "foto_new": "url",
  "user_id": 1,
  "branch_id": 1,
  ...
}
```

**Response**:
```json
{
  "order_id": 456,
  "status": "success"
}
```

### 2. GET `/api/customers` - Ambil Daftar Customer
Untuk autocomplete di ketiga form.

**Response**:
```json
[
  {
    "customer_id": 1,
    "name": "Andi Wijaya",
    "phone": "08123456789",
    "address": "Jl. Merdeka No. 10"
  }
]
```

### 3. POST `/upload` - Upload Foto
Endpoint untuk upload file foto ke server.

**Request**: Form data dengan file
**Response**:
```json
{
  "url": "http://localhost:4000/uploads/foto123.jpg",
  "path": "/uploads/foto123.jpg"
}
```

---

## ✅ Checklist Implementasi

- ✅ Service Page lengkap dengan alur bisnis
- ✅ Buyback Page lengkap dengan alur bisnis
- ✅ Custom Page lengkap dengan alur bisnis
- ✅ Form validation untuk semua field wajib
- ✅ Customer autocomplete terintegrasi
- ✅ Foto upload dengan compression
- ✅ QR scan untuk Service & Buyback (opsional)
- ✅ Status otomatis sesuai order type
- ✅ Error handling untuk semua aksi
- ✅ Navigation ke Faktur Page setelah submit
- ✅ UI konsisten dengan jual_page.dart

---

## 🚀 Next Steps (TODO)

1. **Backend API**: Pastikan endpoint `/orders`, `/api/customers`, dan `/upload` sudah berfungsi dengan benar
2. **Order History**: Implementasi "Pilih dari Order Lama" untuk Service & Buyback
3. **Payment Integration**: Tambah field untuk pembayaran DP/Pelunasan
4. **Receipt Generator**: Integrate dengan PDF generator untuk nota resmi
5. **Database**: Pastikan struktur tabel sesuai dengan `blueprint.txt`
6. **Workshop Integration**: Status update ketika barang dikirim ke workshop
7. **Testing**: Unit test & integration test untuk ketiga halaman

---

## 📝 Catatan Penting

- Semua halaman sudah di-test lint dan tidak ada error
- Image compression 800x800px, quality 90 untuk optimasi
- Customer data di-fetch dari Riverpod provider (state management)
- Base URL otomatis sesuai platform (Android: 10.0.2.2, iOS: localhost)
- Semua field wajib tervalidasi sebelum submit
- Foto WAJIB untuk ketiga tipe order (Service, Buyback, Custom)

---

**Dibuat**: 4 Januari 2026  
**Status**: ✅ Ready untuk integration dengan backend
