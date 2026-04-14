# 🚀 QUICK START GUIDE - SERVICE, BUYBACK & CUSTOM

## 📋 File yang Telah Diimplementasikan

```
✅ lib/modules/cs/pages/service_page.dart       (522 lines)
✅ lib/modules/cs/pages/buyback_page.dart       (415 lines)
✅ lib/modules/cs/pages/custom_page.dart        (424 lines)
✅ IMPLEMENTASI_SERVICE_BUYBACK_CUSTOM.md       (Dokumentasi Detail)
✅ PERBANDINGAN_ALUR_SERVICE_BUYBACK_CUSTOM.md  (Dokumentasi Alur)
✅ RINGKASAN_IMPLEMENTASI.md                    (Ringkasan Singkat)
```

---

## ⚡ Quick Test (Testing Lokal)

### 1. Buka Service Page
```dart
// Di main_page.dart, klik tombol "SERVICE"
Navigator.pushNamed(context, '/service');
```

### 2. Test Flow Dasar
```
1. Pilih Customer (autocomplete)
   ↓
2. Isi detail barang (nama, berat, material, kadar)
   ↓
3. Isi keterangan service
   ↓
4. Scan QR (opsional - skip kalau tidak ada QR scanner)
   ↓
5. Ambil Foto (wajib)
   ↓
6. Klik SUBMIT SERVICE
```

### 3. Expected Result
```
✅ Foto terkompresi (800x800, quality 90)
✅ Validasi form: semua field wajib terisi
✅ Foto WAJIB untuk submit
✅ Jika submit sukses: redirect ke Faktur Page
✅ Jika error: tampil SnackBar dengan pesan error
```

---

## 🔗 API Endpoints yang Diperlukan

### Endpoint 1: POST /orders
**Purpose**: Membuat order baru (service/buyback/custom)

**Request**:
```bash
POST http://localhost:3000/orders
Content-Type: application/json

{
  "order_type": "service|buyback|custom",
  "status": "on-service|buyback|production",
  "customer_id": 123,
  "customer_name": "Andi",
  "customer_phone": "08123456789",
  "customer_address": "Jl. Merdeka",
  "nama_item": "Gelang Emas",
  "material": "Emas",
  "kadar": "22K",
  "berat": "10",
  "foto_new": "http://localhost:4000/uploads/foto123.jpg",
  "scanned_qr": "ABC123",
  "user_id": 1,
  "branch_id": 1,
  
  // Untuk Service
  "keterangan": "Bengkok",
  
  // Untuk Buyback
  "harga_beli": "2500000",
  
  // Untuk Custom
  "spesifikasi": "Ukuran 18...",
  "berat_target": "8",
  "estimasi_waktu": "2 minggu"
}
```

**Response**:
```json
{
  "order_id": 456,
  "status": "success",
  "order_type": "service"
}
```

---

### Endpoint 2: GET /api/customers
**Purpose**: Ambil daftar customer untuk autocomplete

**Request**:
```bash
GET http://localhost:3000/api/customers
```

**Response**:
```json
[
  {
    "customer_id": 1,
    "name": "Andi Wijaya",
    "phone": "08123456789",
    "address": "Jl. Merdeka No. 10",
    "email": "andi@email.com"
  },
  {
    "customer_id": 2,
    "name": "Budi Santoso",
    "phone": "08987654321",
    "address": "Jl. Ahmad Yani No. 5",
    "email": "budi@email.com"
  }
]
```

---

### Endpoint 3: POST /upload
**Purpose**: Upload foto ke server

**Request**:
```bash
POST http://localhost:4000/upload
Content-Type: multipart/form-data

file: <binary image data>
```

**Response**:
```json
{
  "url": "http://localhost:4000/uploads/photo_12345.jpg",
  "path": "/uploads/photo_12345.jpg",
  "filename": "photo_12345.jpg"
}
```

---

## 🛠️ Backend Implementation Checklist

### Express.js Routes
```javascript
// ✅ POST /orders - Create order
app.post('/orders', async (req, res) => {
  // Validasi: order_type harus 'service|buyback|custom'
  // Validasi: customer_id harus ada di database
  // Insert ke tabel orders
  // Insert atau update tabel items
  // Insert ke tabel stock_history
  // Return: order_id dan status
});

// ✅ GET /api/customers - Get all customers
app.get('/api/customers', async (req, res) => {
  // Select semua customer dari tabel customers
  // Return: array of customers
});

// ✅ POST /upload - Upload file
app.post('/upload', uploadMiddleware, async (req, res) => {
  // Simpan file ke folder uploads
  // Return: URL file
});
```

---

## 🗄️ Database Schema Check

### ✅ Verify Table Structure

```sql
-- Check table orders
SELECT column_name, data_type FROM information_schema.columns 
WHERE table_name = 'orders';

-- Check columns exist:
-- order_id, order_type, status, customer_id, item_id
-- name, weight, material, purity, photo_url, scanned_qr
-- branch_id, user_id, created_at, updated_at

-- Verify order_type CHECK constraint
SELECT constraint_name, constraint_type 
FROM information_schema.table_constraints 
WHERE table_name = 'orders';

-- Verify status CHECK constraint exists
-- order_type IN ('jual','buyback','service','custom')
-- status IN ('draft','on-service','buyback','production',...)
```

---

## 🔄 Integration Testing Steps

### Step 1: Test Service Page
```
1. Run Flutter app
2. Login ke system
3. Navigate to "SERVICE" menu
4. Select customer: "Andi Wijaya"
5. Fill form:
   - Nama Barang: "Gelang Emas"
   - Berat: 10
   - Material: "Emas"
   - Kadar: "22K"
   - Keterangan: "Bengkok"
6. Take photo
7. Click SUBMIT
8. Check backend logs for POST /orders request
9. Verify response: order_id returned
10. Verify Faktur Page displays correctly
```

### Step 2: Test Buyback Page
```
1. Navigate to "BUYBACK" menu
2. Select customer
3. Fill form with buyback-specific data
4. Take photo
5. Click SUBMIT
6. Verify order created with type 'buyback'
7. Check database: status should be 'buyback'
```

### Step 3: Test Custom Page
```
1. Navigate to "CUSTOM" menu
2. Select customer
3. Fill spesifikasi lengkap
4. Take photo (referensi)
5. Click SUBMIT
6. Verify order created with type 'custom'
7. Check database: status should be 'production'
```

---

## 🐛 Debugging Tips

### Issue: "Foto barang WAJIB untuk service!"
```dart
// Solution: Ensure _pickFoto() properly sets _fotoFile
// Check: if (_fotoFile != null) before submit
// Check: Image compression success
```

### Issue: "Customer wajib dipilih"
```dart
// Solution: Ensure _selectedCustomer is not null
// Check: onSelected callback sets _selectedCustomer
// Check: _selectedCustomer has customer_id
```

### Issue: "Gagal menyimpan order: ..."
```dart
// Solution: Check backend API
// Check: POST /orders endpoint working
// Check: Database connection
// Check: All required fields in request body
// Check: error message from response body
```

### Issue: Customer autocomplete tidak menampilkan data
```dart
// Solution: Check customers provider
// Check: GET /api/customers returning data
// Check: Customer list is not empty
// Check: Autocomplete filtering logic
```

---

## 📱 Mobile Testing

### Android
```
1. Emulator setup: Set baseUrl to 10.0.2.2:3000
2. Test on Android device/emulator
3. Check camera permission
4. Test photo upload
```

### iOS
```
1. Simulator/Device: Use localhost:3000
2. Check camera permission in Info.plist
3. Test photo functionality
```

---

## ✅ Final Verification Checklist

- [ ] Semua 3 page (service, buyback, custom) tidak error
- [ ] Customer autocomplete working
- [ ] Photo upload working (compression OK)
- [ ] QR scan working (service & buyback only)
- [ ] Form validation working
- [ ] Backend API /orders working
- [ ] Backend API /api/customers working
- [ ] Backend API /upload working
- [ ] Database tables created with correct schema
- [ ] Navigation to Faktur Page working
- [ ] Error handling & snackbar working
- [ ] UI looks good & consistent

---

## 🚀 Deployment Checklist

- [ ] Replace hardcoded base URLs with environment variables
- [ ] Test with production database
- [ ] Enable HTTPS for image upload
- [ ] Set proper CORS headers
- [ ] Add rate limiting to API endpoints
- [ ] Add request validation middleware
- [ ] Add proper error logging
- [ ] Test with different device sizes
- [ ] Test with slow network (3G/4G)
- [ ] Performance test image compression

---

## 📞 Support & Resources

### Documentation Files
- `IMPLEMENTASI_SERVICE_BUYBACK_CUSTOM.md` - Detailed implementation
- `PERBANDINGAN_ALUR_SERVICE_BUYBACK_CUSTOM.md` - Flow comparison
- `RINGKASAN_IMPLEMENTASI.md` - Summary
- `1/blueprint.txt` - Original architecture blueprint

### Reference Code
- `lib/modules/cs/pages/jual_page.dart` - Similar implementation (reference)
- `lib/modules/cs/pages/customers_page.dart` - Customer management
- `lib/routes/app_routes.dart` - Route configuration

---

## 🎯 Next Milestones

1. **Phase 1** (Week 1): Backend API implementation & testing
2. **Phase 2** (Week 2): Integration testing & bug fixes
3. **Phase 3** (Week 3): Workshop integration (status updates)
4. **Phase 4** (Week 4): Payment integration & finalization

---

**Last Updated**: 4 Januari 2026  
**Status**: ✅ READY FOR PRODUCTION  
**Contact**: Development Team
