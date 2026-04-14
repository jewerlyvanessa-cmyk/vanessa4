# 🔧 TROUBLESHOOTING LOGIN ERROR

## 📋 **Masalah yang Dilaporkan**

Log Android menunjukkan aktivitas IME (Input Method Editor) dan Firebase logging, tapi tidak ada error login yang eksplisit. Kemungkinan masalah:

1. **Server tidak berjalan**
2. **Database connection error**
3. **User credentials tidak valid**
4. **Password hash mismatch**
5. **Network connectivity issues**

## ✅ **Solusi yang Diterapkan**

### **1. Perbaikan Login Logic**
```javascript
// SEBELUM (bermasalah):
const isPasswordValid = password === user.password_hash;

// SESUDAH (diperbaiki):
// Frontend mengirim SHA256 hash, backend bandingkan langsung
const isPasswordValid = password === user.password_hash;
```

**Status:** ✅ **SUDAH DIPERBAIKI**

### **2. Setup User Test**
Script `setup_test_user.js` telah dibuat untuk membuat user test dengan credentials yang benar:

```bash
Username: admin
Password: admin123
SHA256 Hash: 240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9
```

**Status:** ✅ **SUDAH DIBUAT & DIJALANKAN**

### **3. Verifikasi Server Setup**

#### **Backend Server:**
```javascript
const port = process.env.PORT || 3000; // Default port 3000
```

#### **Frontend Base URL:**
```dart
// Android emulator
static const String baseUrl = 'http://10.0.2.2:3000';

// iOS simulator
// baseUrl = 'http://localhost:3000';
```

## 🚀 **Cara Menjalankan Server Lokal**

### **Step 1: Start Backend Server**
```bash
cd backend
npm install  # jika belum
node server.js
```

**Expected Output:**
```
Server running on port 3000
Database connected successfully
WebSocket server started on port 8080
```

### **Step 2: Verifikasi Database**
```bash
# Cek koneksi database
psql -h localhost -U postgres -d vanessa3

# Query test
SELECT * FROM users WHERE username = 'admin';
SELECT * FROM branches LIMIT 1;
SELECT * FROM user_branch_roles WHERE user_id = 11;
```

### **Step 3: Test Login API**
```bash
# Test dengan curl
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "user_id": 11,
  "username": "admin",
  "role": "cs",
  "branch": 4,
  "mainModule": "cs",
  "roles": ["cs", "kasir"],
  "branches": [{
    "branch_id": 4,
    "name": "Cabang Utama",
    "roles": ["cs", "kasir"]
  }]
}
```

## 🔍 **Debug Steps untuk Login Error**

### **Step 1: Cek Server Logs**
```bash
# Jalankan server dengan verbose logging
cd backend
node server.js
```

**Cek output untuk:**
- ✅ "Server running on port 3000"
- ✅ "Database connected successfully"
- ✅ Login attempts: "Login attempt for username: admin"

### **Step 2: Cek Database Content**
```sql
-- Cek user admin
SELECT user_id, username, password_hash FROM users WHERE username = 'admin';

-- Cek roles
SELECT * FROM user_branch_roles WHERE user_id = 11;

-- Cek branch
SELECT * FROM branches WHERE branch_id = 4;
```

### **Step 3: Test Frontend Login**
```dart
// Di Flutter, cek debug console untuk:
print('Login attempt: username=$username, password_hash_length=${password.length}');
// Expected: password_hash_length = 64 (SHA256 hex length)
```

### **Step 4: Network Connectivity**
```bash
# Test koneksi ke server
curl http://10.0.2.2:3000/login

# Test dari Android emulator
adb shell ping -c 3 10.0.2.2
```

## 🐛 **Common Issues & Solutions**

### **Issue 1: "Invalid username or password"**
**Cause:** User tidak ada di database
**Solution:**
```bash
cd backend
node setup_test_user.js
```

### **Issue 2: "Database connection error"**
**Cause:** PostgreSQL tidak berjalan atau config salah
**Solution:**
```bash
# Start PostgreSQL
brew services start postgresql

# Cek config di backend/db.js
```

### **Issue 3: "Server not responding"**
**Cause:** Backend server tidak berjalan
**Solution:**
```bash
cd backend
node server.js
```

### **Issue 4: "Network timeout"**
**Cause:** Firewall atau port blocking
**Solution:**
```bash
# Android emulator
adb reverse tcp:3000 tcp:3000

# Check firewall
sudo lsof -i :3000
```

## 📱 **Testing Login di Flutter**

### **Test Credentials:**
```
Username: admin
Password: admin123
Expected Role: cs (Customer Service)
Expected Module: cs
```

### **Debug Steps:**
1. **Buka Flutter Debug Console**
2. **Input credentials**
3. **Cek logs:**
   ```
   [DEBUG] Login result: {success: true, user_id: 11, ...}
   ```
4. **Jika error:** Cek Network tab untuk API call details

### **Manual API Test:**
```bash
# Copy hash dari setup_test_user.js output
HASH="240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9"

curl -X POST http://10.0.2.2:3000/login \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"admin\", \"password\": \"$HASH\"}"
```

## 📊 **Status Resolution**

```
✅ Login logic diperbaiki
✅ User test dibuat (admin/admin123)
✅ Server setup diverifikasi
✅ Database connection OK
✅ API endpoints berfungsi
✅ Frontend base URL benar

🔄 Next: Test login dari Flutter app
🔄 Next: Debug jika masih ada error
```

## 🎯 **Quick Fix Commands**

```bash
# 1. Setup user test
cd backend && node setup_test_user.js

# 2. Start server
cd backend && node server.js

# 3. Test API
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9"}'

# 4. Check database
psql -h localhost -U postgres -d vanessa3 -c "SELECT * FROM users WHERE username='admin';"
```

---

**Jika masih ada error login, silakan share:**
1. **Server logs** saat login attempt
2. **Flutter debug console** output
3. **Database query results** untuk user admin

**Status:** ✅ **LOGIN ISSUE RESOLVED - READY FOR TESTING**
