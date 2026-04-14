# Arsitektur Aplikasi Vanessa

## 1. Pendahuluan
Arsitektur aplikasi Vanessa dirancang untuk mendukung kebutuhan operasional toko dan workshop, dengan fokus pada tiga peran utama: CS, kasir, dan superadmin. Arsitektur ini mencakup frontend, backend, database, dan integrasi sistem.

---

## 2. Komponen Utama

### 2.1 Frontend (Flutter)
- **Fitur Utama**:
  - Login/logout dengan autentikasi berbasis role.
  - Dashboard sesuai role (CS, kasir, superadmin).
  - Manajemen order (scan QR, upload foto, manual input).
  - Realtime update menggunakan WebSocket.
- **Teknologi**:
  - Flutter, Riverpod/Bloc, Hive.

### 2.2 Backend (Node.js/FastAPI)
- **Fitur Utama**:
  - Authentication menggunakan JWT.
  - CRUD untuk orders, items, dan users.
  - Realtime notification menggunakan WebSocket/FCM.
  - PDF/nota generator.
- **Teknologi**:
  - Node.js/FastAPI, REST API, WebSocket.

### 2.3 Database (PostgreSQL)
- **Tabel Utama**:
  - `users`, `branches`, `items`, `orders`, `order_items`, `stock_history`.
- **Fitur Database**:
  - JSONB untuk metadata fleksibel.
  - Partitioning untuk tabel besar.
  - Foreign key untuk menjaga integritas data.

### 2.4 Storage
- **Fitur Utama**:
  - Penyimpanan foto produk dan PDF nota/slip.
  - Dukungan untuk lokal atau cloud (MinIO/S3).

### 2.5 Notifikasi
- **Fitur Utama**:
  - Push notification untuk order baru, pekerjaan selesai, dan pembayaran diterima.
  - Menggunakan WebSocket/FCM.

---

## 3. Alur Kerja Utama

### 3.1 Login dan Dashboard
1. User membuka aplikasi dan login.
2. Backend memvalidasi kredensial dan mengembalikan role serta branch utama.
3. Dashboard ditampilkan sesuai role (CS, kasir, superadmin).

### 3.2 Manajemen Order
1. CS membuat order baru (scan QR, upload foto, atau manual input).
2. Order dikirim ke backend untuk diproses.
3. Status order diperbarui di database dan notifikasi dikirim ke pihak terkait.

### 3.3 Pembayaran
1. Kasir memproses pembayaran untuk order.
2. Backend mencatat pembayaran dan memperbarui status order.
3. Nota pembayaran dihasilkan dan dapat diunduh.

### 3.4 Manajemen Superadmin
1. Superadmin mengelola user, branch, dan role.
2. Data dapat diimpor/ekspor untuk laporan.
3. Analitik ditampilkan untuk pengambilan keputusan.

---

## 4. Diagram Arsitektur
```
+-------------------------+
|       FRONTEND          |
|-------------------------|
| Flutter App             |
| - Login / Dashboard     |
| - Order Management      |
| - Payment Processing    |
| - Reporting             |
+-------------------------+
           |
           | HTTPS / REST API / WebSocket
           v
+-------------------------+
|       BACKEND API       |
|-------------------------|
| Node.js / FastAPI       |
| - Auth & JWT Token      |
| - CRUD Operations       |
| - Realtime Notification |
| - PDF Generator         |
+-------------------------+
           |
           | SQL
           v
+-------------------------+
|       DATABASE          |
|-------------------------|
| PostgreSQL              |
| - users                 |
| - branches              |
| - items                 |
| - orders                |
| - stock_history         |
+-------------------------+
           |
           | File Storage
           v
+-------------------------+
|       STORAGE           |
|-------------------------|
| Lokal / Cloud           |
| - Foto Produk           |
| - PDF Nota              |
+-------------------------+
```

---

## 5. Penutup
Arsitektur ini dirancang untuk memastikan aplikasi Vanessa dapat memenuhi kebutuhan operasional toko dan workshop, dengan fokus pada kemudahan penggunaan, skalabilitas, dan keamanan.
