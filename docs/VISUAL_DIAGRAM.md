# 📊 VISUAL DIAGRAM - SERVICE, BUYBACK & CUSTOM

## 🎨 APLIKASI FLOW ARCHITECTURE

```
┌────────────────────────────────────────────────────────────────┐
│                      VANESSA3 APP                               │
│              (Customer Service Module)                          │
└────────────────────────────────────────────────────────────────┘

                           ┌─────────────┐
                           │  Main Page  │
                           │   (CS Menu) │
                           └──────┬──────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                    ▼             ▼             ▼
            ┌──────────────┐ ┌──────────┐ ┌──────────┐
            │ Jual Page    │ │Buyback   │ │ Custom   │
            │  (Existing)  │ │ Page ✅   │ │Page ✅   │
            └──────────────┘ └──────────┘ └──────────┘
                    │             │             │
                    ▼             ▼             ▼
            ┌──────────────┐ ┌──────────┐ ┌──────────┐
            │ Order Type:  │ │Order Type│ │Order Type│
            │    'jual'    │ │'buyback' │ │'custom'  │
            └──────────────┘ └──────────┘ └──────────┘
                    │             │             │
                    └─────────────┼─────────────┘
                                  │
                         ┌────────▼────────┐
                         │ POST /orders    │
                         │  (Backend API)  │
                         └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │ Database Update │
                         │  (PostgreSQL)   │
                         └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │ Faktur Page     │
                         │ (Receipt/Nota)  │
                         └─────────────────┘
```

---

## 📋 SERVICE PAGE FLOWCHART

```
┌──────────────────────────┐
│   SERVICE PAGE OPEN      │
└────────────┬─────────────┘
             │
             ▼
    ┌────────────────────┐
    │  Load Customers    │
    │  (via Riverpod)    │
    └────────┬───────────┘
             │
             ▼
┌──────────────────────────────────────┐
│  FORM: Service Order                 │
├──────────────────────────────────────┤
│                                      │
│  [1] Customer Section                │
│      ├─ Customer: [Autocomplete] 🔍  │
│      ├─ Phone: [Read-only]           │
│      └─ Address: [Read-only]         │
│                                      │
│  [2] Order History (Optional)        │
│      └─ [Pilih dari Order Lama] 📋  │
│                                      │
│  [3] Item Details                    │
│      ├─ Nama: [Input]                │
│      ├─ Berat: [Input]               │
│      ├─ Material: [Input]            │
│      └─ Kadar: [Input]               │
│                                      │
│  [4] Service Description             │
│      └─ Keterangan: [Text Area]      │
│                                      │
│  [5] QR Code (Optional)              │
│      ├─ QR: [Read-only]              │
│      └─ [Scan] 📷                    │
│                                      │
│  [6] Photo Upload (REQUIRED) ⭐      │
│      ├─ [Photo Preview]              │
│      └─ [Take Photo] 📸              │
│                                      │
│  [SUBMIT SERVICE] ✅                 │
│                                      │
└──────────┬───────────────────────────┘
           │
        ┌──┴──┐
        │     │
   ❌ Validation
   Error    │
   │        │ ✅ Valid
   │        │
   ▼        ▼
┌────────────────────┐
│ Show SnackBar      │ POST /orders
│ Error Message      │ ─────────────────┐
│                    │                  │
│ Retry Form         │                  ▼
└────────────────────┘   ┌──────────────────────┐
                         │ Backend Processing   │
                         │ ├─ Insert orders     │
                         │ ├─ Update items      │
                         │ └─ Stock history     │
                         └──────────┬───────────┘
                                    │
                              ┌─────▼─────┐
                              │ Response? │
                              └─────┬─────┘
                                    │
                          ┌─────────┴──────────┐
                          │                    │
                        ✅ 201              ❌ Error
                          │                    │
                          ▼                    ▼
                    ┌──────────────┐     ┌──────────────┐
                    │ Faktur Page  │     │ SnackBar     │
                    │ (Receipt)    │     │ Error Message│
                    └──────────────┘     └──────────────┘
```

---

## 💰 BUYBACK PAGE FLOWCHART

```
┌──────────────────────────┐
│  BUYBACK PAGE OPEN       │
└────────┬─────────────────┘
         │
         ▼
  ┌──────────────────┐
  │ Load Customers   │
  │ (via Riverpod)   │
  └────────┬─────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ FORM: Buyback Order                  │
├──────────────────────────────────────┤
│                                      │
│ [1] Customer Section                 │
│     ├─ Customer: [Autocomplete] 🔍   │
│     ├─ Phone: [Read-only]            │
│     └─ Address: [Read-only]          │
│                                      │
│ [2] Item Details                     │
│     ├─ Nama: [Input] ⭐              │
│     ├─ Berat: [Input] ⭐             │
│     ├─ Material: [Input] ⭐          │
│     ├─ Kadar: [Input]                │
│     └─ Harga Beli: [Input] ⭐        │
│         (UNIQUE for Buyback)         │
│                                      │
│ [3] QR Code (Optional)               │
│     ├─ QR: [Read-only]               │
│     └─ [Scan] 📷                     │
│                                      │
│ [4] Photo Upload (REQUIRED) ⭐       │
│     ├─ [Photo Preview]               │
│     └─ [Take Photo] 📸               │
│                                      │
│ [SUBMIT BUYBACK] ✅                  │
│                                      │
└──────────┬───────────────────────────┘
           │
        ┌──┴──┐
        │     │
   ❌ Validation
   Error    │
   │        │ ✅ Valid
   │        │
   ▼        ▼
┌────────────────────┐
│ Show SnackBar      │ POST /orders
│ Error Message      │ (harga_beli included)
│                    │ ────────────────────┐
│ Retry Form         │                     │
└────────────────────┘                     ▼
                          ┌──────────────────────┐
                          │ Backend Processing   │
                          │ ├─ Insert orders     │
                          │ ├─ Create items      │
                          │ │  (untuk stok)      │
                          │ └─ Stock history     │
                          └──────────┬───────────┘
                                     │
                               ┌─────▼─────┐
                               │ Response? │
                               └─────┬─────┘
                                     │
                           ┌─────────┴──────────┐
                           │                    │
                         ✅ 201              ❌ Error
                           │                    │
                           ▼                    ▼
                     ┌──────────────┐     ┌──────────────┐
                     │ Faktur Page  │     │ SnackBar     │
                     │ (Receipt)    │     │ Error Message│
                     │              │     │              │
                     │ Harga Beli   │     │ Retry        │
                     │ Akan masuk    │     │              │
                     │ ke STOK       │     └──────────────┘
                     └──────────────┘
```

---

## ⚙️ CUSTOM PAGE FLOWCHART

```
┌──────────────────────────┐
│   CUSTOM PAGE OPEN       │
└────────┬─────────────────┘
         │
         ▼
  ┌──────────────────┐
  │ Load Customers   │
  │ (via Riverpod)   │
  └────────┬─────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ FORM: Custom Order                   │
├──────────────────────────────────────┤
│                                      │
│ [1] Customer Section                 │
│     ├─ Customer: [Autocomplete] 🔍   │
│     ├─ Phone: [Read-only]            │
│     └─ Address: [Read-only]          │
│                                      │
│ [2] Spesifikasi Custom               │
│     ├─ Nama Barang: [Input] ⭐       │
│     ├─ Spesifikasi: [Text Area] ⭐  │
│     │  (Detail, ukuran, warna)       │
│     ├─ Material: [Input] ⭐          │
│     ├─ Kadar: [Input]                │
│     ├─ Berat Target: [Input]         │
│     └─ Estimasi Waktu: [Input]       │
│        (e.g., "2 minggu")            │
│                                      │
│ [3] Photo Upload (REQUIRED) ⭐       │
│     ├─ [Photo Preview]               │
│     └─ [Take Photo] 📸               │
│     (REFERENCE/DESIGN ONLY)          │
│                                      │
│ [NOTE] NO QR CODE SCANNING           │
│        (Item belum ada)              │
│                                      │
│ [SUBMIT CUSTOM] ✅                   │
│                                      │
└──────────┬───────────────────────────┘
           │
        ┌──┴──┐
        │     │
   ❌ Validation
   Error    │
   │        │ ✅ Valid
   │        │
   ▼        ▼
┌────────────────────┐
│ Show SnackBar      │ POST /orders
│ Error Message      │ (spesifikasi included)
│                    │ ─────────────────────┐
│ Retry Form         │                      │
└────────────────────┘                      ▼
                         ┌──────────────────────┐
                         │ Backend Processing   │
                         │ ├─ Insert orders     │
                         │ ├─ Create items      │
                         │ │  (status=          │
                         │ │   production)      │
                         │ └─ Stock history     │
                         └──────────┬───────────┘
                                    │
                              ┌─────▼─────┐
                              │ Response? │
                              └─────┬─────┘
                                    │
                          ┌─────────┴──────────┐
                          │                    │
                        ✅ 201              ❌ Error
                          │                    │
                          ▼                    ▼
                    ┌──────────────┐     ┌──────────────┐
                    │ Faktur Page  │     │ SnackBar     │
                    │ (Receipt)    │     │ Error Message│
                    │              │     │              │
                    │ Status:      │     │ Retry        │
                    │ production   │     │              │
                    │ (Workshop)   │     └──────────────┘
                    └──────────────┘
```

---

## 🔄 DATA TRANSFORMATION FLOW

```
USER INPUT (Flutter Form)
    │
    ├─ Customer Selection (Autocomplete)
    │   → _selectedCustomer (Map)
    │   → customer_id, name, phone, address
    │
    ├─ Item Details (Text Fields)
    │   → _namaItemController.text
    │   → _beratController.text
    │   → _materialController.text
    │   → _kadarController.text
    │
    ├─ Service/Buyback/Custom Specific
    │   → _keteranganServiceController (Service)
    │   → _hargaBeli (Buyback)
    │   → _spesifikasiController (Custom)
    │
    ├─ Photo Upload
    │   → _pickFoto() → _compressFoto()
    │   → Upload to /upload endpoint
    │   → Get URL response
    │
    └─ QR Code (Optional for S/B)
        → _scanQR() → Store in _qrScanController
    
              │
              ▼
    CREATE REQUEST PAYLOAD
    ┌──────────────────────────┐
    │ {                        │
    │   "order_type": "...",   │
    │   "status": "...",       │
    │   "customer_id": 123,    │
    │   "nama_item": "...",    │
    │   "material": "...",     │
    │   "kadar": "...",        │
    │   "berat": "...",        │
    │   "foto_new": "url",     │
    │   "user_id": 1,          │
    │   "branch_id": 1,        │
    │   ...                    │
    │ }                        │
    └──────────┬───────────────┘
               │
               ▼
    HTTP POST /orders
    └─→ Backend API
        ├─ Validate all required fields
        ├─ Check customer_id exists
        ├─ INSERT orders table
        ├─ INSERT/UPDATE items table
        ├─ INSERT stock_history
        └─ INSERT payments (if needed)
            │
            ▼
        Database Update
        ├─ orders table: NEW ORDER CREATED
        ├─ items table: NEW ITEM or UPDATE
        └─ stock_history: NEW HISTORY RECORD
            │
            ▼
        Response: { order_id, status }
            │
            ▼
        Navigation → Faktur Page
        ├─ Display order_id
        ├─ Display order details
        ├─ Print/Save option
        └─ Back button
```

---

## 🗄️ DATABASE STATE CHANGES

### SERVICE ORDER

```
BEFORE:
┌─────────────────────────────────────┐
│ orders table (empty)                │
│ items table (old items)             │
└─────────────────────────────────────┘

SUBMIT SERVICE FORM
    │
    ▼

INSERT INTO orders VALUES (
  order_id: 456,
  order_type: 'service',
  status: 'on-service',
  customer_id: 123,
  item_id: NULL (manual input),
  name: 'Gelang Emas',
  weight: 10,
  material: 'Emas',
  purity: '22K',
  photo_url: 'url',
  scanned_qr: 'ABC123'
);

UPDATE items SET status = 'on-service'
WHERE item_id = 456;

INSERT INTO stock_history VALUES (
  item_id: 456,
  old_status: 'ready',
  new_status: 'on-service',
  changed_by: 1
);

AFTER:
┌─────────────────────────────────────┐
│ orders: +1 row (service)            │
│ items: status updated to on-service │
│ stock_history: +1 history record    │
└─────────────────────────────────────┘
```

### BUYBACK ORDER

```
BEFORE:
┌─────────────────────────────────────┐
│ orders table (empty)                │
│ items table (current inventory)     │
└─────────────────────────────────────┘

SUBMIT BUYBACK FORM
    │
    ▼

INSERT INTO orders VALUES (
  order_id: 457,
  order_type: 'buyback',
  status: 'buyback',
  customer_id: 123,
  item_id: NULL,
  name: 'Cincin Emas',
  ...
  photo_url: 'url'
);

INSERT INTO items VALUES (
  NEW ITEM - dari buyback
  status: 'ready' (ready to sell)
);

INSERT INTO stock_history VALUES (
  NEW ITEM masuk inventory
);

INSERT INTO payments VALUES (
  order_id: 457,
  amount: 2500000,
  type: 'buyback'
);

AFTER:
┌─────────────────────────────────────┐
│ orders: +1 row (buyback)            │
│ items: +1 new item (ready for sale) │
│ stock_history: +1 record            │
│ payments: +1 payment record         │
└─────────────────────────────────────┘
```

### CUSTOM ORDER

```
BEFORE:
┌─────────────────────────────────────┐
│ orders table (empty)                │
│ items table (current inventory)     │
└─────────────────────────────────────┘

SUBMIT CUSTOM FORM
    │
    ▼

INSERT INTO orders VALUES (
  order_id: 458,
  order_type: 'custom',
  status: 'production',
  customer_id: 123,
  item_id: NULL,
  name: 'Cincin Pernikahan',
  ...
  photo_url: 'url' (reference)
);

INSERT INTO items VALUES (
  NEW ITEM - draft
  status: 'production'
);

INSERT INTO stock_history VALUES (
  NEW ITEM - production status
);

INSERT INTO payments VALUES (
  order_id: 458,
  amount: 4000000,
  type: 'dp' (down payment)
);

AFTER:
┌─────────────────────────────────────┐
│ orders: +1 row (custom)             │
│ items: +1 item (production status)  │
│ stock_history: +1 record            │
│ payments: +1 DP payment             │
└─────────────────────────────────────┘
```

---

## 📱 STATE MANAGEMENT DIAGRAM (Riverpod)

```
┌──────────────────────────────────┐
│  customersProvider (Riverpod)    │
│  ┌────────────────────────────┐  │
│  │ State: List<Customer>      │  │
│  │                            │  │
│  │ Initial: Load from /api/.. │  │
│  │ Watch: Inside build()      │  │
│  │                            │  │
│  │ Usage:                     │  │
│  │ final list = ref.watch(    │  │
│  │   customersProvider        │  │
│  │ );                         │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
           │
           │ Shared across
           │ Service, Buyback, Custom
           │
    ┌──────┴──────┬──────────┬──────────┐
    │             │          │          │
    ▼             ▼          ▼          ▼
Service Form  Buyback   Custom     Jual
Autocomplete  Autocomplete Autocomplete
```

---

## ✅ FILE STRUCTURE

```
lib/modules/cs/pages/
├── service_page.dart          ✅ 522 lines
├── buyback_page.dart          ✅ 415 lines
├── custom_page.dart           ✅ 424 lines
├── jual_page.dart             (reference)
├── customers_page.dart        (customer management)
└── faktur_page.dart           (receipt)

Documentation/
├── IMPLEMENTASI_SERVICE_BUYBACK_CUSTOM.md
├── PERBANDINGAN_ALUR_SERVICE_BUYBACK_CUSTOM.md
├── RINGKASAN_IMPLEMENTASI.md
├── QUICK_START_GUIDE.md
└── blueprint.txt (original)
```

---

**Dibuat**: 4 Januari 2026  
**Status**: ✅ DIAGRAM LENGKAP  
**Visual Quality**: 🎨 ASCII Art Diagrams
