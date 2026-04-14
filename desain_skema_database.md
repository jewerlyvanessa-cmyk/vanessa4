# Desain Skema Database Aplikasi Vanessa

## 1. Pendahuluan
Skema database dirancang untuk mendukung fitur utama aplikasi Vanessa, termasuk manajemen user, branch, order, dan inventory. Fokus utama adalah memastikan integritas data dan mendukung kebutuhan operasional CS, kasir, dan superadmin.

---

## 2. Tabel Utama

### 2.1 Tabel `users`
- **Deskripsi**: Menyimpan data pengguna aplikasi.
- **Kolom**:
  - `user_id` (BIGSERIAL, PK): ID unik untuk setiap user.
  - `username` (TEXT, UNIQUE): Nama pengguna untuk login.
  - `password_hash` (TEXT): Hash password.
  - `status` (TEXT): Status user ('active', 'inactive').
  - `created_at` (TIMESTAMP): Waktu pembuatan.
  - `updated_at` (TIMESTAMP): Waktu pembaruan.

### 2.2 Tabel `branches`
- **Deskripsi**: Menyimpan data cabang.
- **Kolom**:
  - `branch_id` (BIGSERIAL, PK): ID unik untuk setiap cabang.
  - `name` (TEXT): Nama cabang.
  - `code` (TEXT, UNIQUE): Kode cabang.
  - `created_at` (TIMESTAMP): Waktu pembuatan.
  - `updated_at` (TIMESTAMP): Waktu pembaruan.

### 2.3 Tabel `user_branch_roles`
- **Deskripsi**: Menghubungkan user dengan branch dan role.
- **Kolom**:
  - `id` (BIGSERIAL, PK): ID unik.
  - `user_id` (BIGINT, FK): Foreign key ke `users`.
  - `branch_id` (BIGINT, FK): Foreign key ke `branches`.
  - `role` (TEXT): Role user ('cs', 'kasir', 'superadmin', dll).
  - `is_primary` (BOOLEAN): TRUE jika role utama.

### 2.4 Tabel `items`
- **Deskripsi**: Menyimpan data item/barang.
- **Kolom**:
  - `item_id` (BIGSERIAL, PK): ID unik untuk setiap item.
  - `name` (TEXT): Nama item.
  - `weight` (NUMERIC): Berat item.
  - `material` (TEXT): Material item.
  - `purity` (TEXT): Tingkat kemurnian.
  - `status` (TEXT): Status item ('ready', 'sold', dll).
  - `branch_id` (BIGINT, FK): Foreign key ke `branches`.
  - `photo_url` (TEXT): URL foto item.
  - `metadata` (JSONB): Metadata fleksibel.

### 2.5 Tabel `orders`
- **Deskripsi**: Menyimpan data order.
- **Kolom**:
  - `order_id` (BIGSERIAL, PK): ID unik untuk setiap order.
  - `order_type` (TEXT): Jenis order ('jual', 'buyback', dll).
  - `item_id` (BIGINT, FK): Foreign key ke `items`.
  - `status` (TEXT): Status order ('draft', 'reserved', dll).
  - `branch_id` (BIGINT, FK): Foreign key ke `branches`.
  - `created_at` (TIMESTAMP): Waktu pembuatan.
  - `updated_at` (TIMESTAMP): Waktu pembaruan.

### 2.6 Tabel `stock_history`
- **Deskripsi**: Menyimpan log perubahan status item.
- **Kolom**:
  - `history_id` (BIGSERIAL, PK): ID unik untuk setiap log.
  - `item_id` (BIGINT, FK): Foreign key ke `items`.
  - `old_status` (TEXT): Status sebelum perubahan.
  - `new_status` (TEXT): Status setelah perubahan.
  - `changed_by` (BIGINT, FK): User yang melakukan perubahan.
  - `timestamp` (TIMESTAMP): Waktu perubahan.

---

## 3. Relasi Antar Tabel

### 3.1 Relasi User dan Branch
- **Deskripsi**: User dapat memiliki banyak branch dan role.
- **Relasi**:
  - `users` → `user_branch_roles` → `branches`

### 3.2 Relasi Order dan Item
- **Deskripsi**: Order dapat mengambil data dari item atau manual input.
- **Relasi**:
  - `orders` → `items`

### 3.3 Relasi Stock History
- **Deskripsi**: Setiap perubahan status item dicatat di `stock_history`.
- **Relasi**:
  - `items` → `stock_history`

---

## 4. Diagram ERD
```
erDiagram
    USERS ||--o{ USER_BRANCH_ROLES : has
    BRANCHES ||--o{ USER_BRANCH_ROLES : has
    BRANCHES ||--o{ ITEMS : contains
    ITEMS ||--o{ ORDERS : used_in
    ITEMS ||--o{ STOCK_HISTORY : logs
    USERS ||--o{ STOCK_HISTORY : changes
```

---

## 5. Penutup
Skema database ini dirancang untuk mendukung kebutuhan operasional aplikasi Vanessa, dengan fokus pada integritas data dan efisiensi. Setiap perubahan pada skema akan didiskusikan lebih lanjut dengan tim pengembang.
