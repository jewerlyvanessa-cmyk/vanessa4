import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';

class WorkshopSettingsPage extends ConsumerWidget {
  const WorkshopSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);
    final webSocketState = ref.watch(webSocketProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo_bulat.png',
              height: 36,
              width: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text('Pengaturan Workshop'),
          ],
        ),
        actions: [
          // Real-time connection indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(
                  webSocketState != null ? Icons.wifi : Icons.wifi_off,
                  color: webSocketState != null ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text('Live', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          SwitchBranchRoleWidget(),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // User Info Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin: ${userState.username}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Branch: ${userState.branch}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          // Settings Categories
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _SettingsCategory(
                  title: 'Pengaturan Workshop',
                  icon: Icons.settings,
                  children: [
                    _SettingsItem(
                      title: 'Informasi Workshop',
                      subtitle: 'Nama, alamat, kontak workshop',
                      icon: Icons.business,
                      onTap: () => _showWorkshopInfoSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Jam Operasional',
                      subtitle: 'Jadwal buka dan tutup workshop',
                      icon: Icons.schedule,
                      onTap: () => _showOperatingHoursSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Kapasitas Workshop',
                      subtitle: 'Jumlah teknisi dan workstation',
                      icon: Icons.people,
                      onTap: () => _showCapacitySettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsCategory(
                  title: 'Pengaturan Order',
                  icon: Icons.assignment,
                  children: [
                    _SettingsItem(
                      title: 'Kategori Layanan',
                      subtitle: 'Jenis-jenis layanan yang tersedia',
                      icon: Icons.category,
                      onTap: () => _showServiceCategoriesSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Estimasi Waktu',
                      subtitle: 'Waktu standar untuk setiap layanan',
                      icon: Icons.timer,
                      onTap: () => _showTimeEstimatesSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Harga Standar',
                      subtitle: 'Tarif dasar untuk layanan',
                      icon: Icons.attach_money,
                      onTap: () => _showPricingSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsCategory(
                  title: 'Pengaturan Material',
                  icon: Icons.inventory,
                  children: [
                    _SettingsItem(
                      title: 'Minimum Stok',
                      subtitle: 'Batas minimum stok material',
                      icon: Icons.warning,
                      onTap: () => _showMinimumStockSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Supplier',
                      subtitle: 'Daftar supplier material',
                      icon: Icons.local_shipping,
                      onTap: () => _showSupplierSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Kategori Material',
                      subtitle: 'Pengelompokan material',
                      icon: Icons.folder,
                      onTap: () => _showMaterialCategoriesSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsCategory(
                  title: 'Pengaturan Teknisi',
                  icon: Icons.engineering,
                  children: [
                    _SettingsItem(
                      title: 'Spesialisasi Teknisi',
                      subtitle: 'Keahlian dan spesialisasi',
                      icon: Icons.build,
                      onTap: () =>
                          _showTechnicianSpecializationsSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Target Produktivitas',
                      subtitle: 'Target order per hari/teknisi',
                      icon: Icons.track_changes,
                      onTap: () => _showProductivityTargetsSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Jadwal Kerja',
                      subtitle: 'Shift dan jadwal teknisi',
                      icon: Icons.calendar_today,
                      onTap: () => _showWorkScheduleSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsCategory(
                  title: 'Pengaturan Sistem',
                  icon: Icons.system_update,
                  children: [
                    _SettingsItem(
                      title: 'Notifikasi',
                      subtitle: 'Pengaturan alert dan reminder',
                      icon: Icons.notifications,
                      onTap: () => _showNotificationSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Backup & Restore',
                      subtitle: 'Pengaturan backup data',
                      icon: Icons.backup,
                      onTap: () => _showBackupSettings(context),
                    ),
                    _SettingsItem(
                      title: 'Integrasi',
                      subtitle: 'Pengaturan koneksi eksternal',
                      icon: Icons.link,
                      onTap: () => _showIntegrationSettings(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkshopInfoSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Informasi Workshop'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: 'Workshop Vanessa Emas',
                decoration: const InputDecoration(labelText: 'Nama Workshop'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: 'Jl. Emas No. 123, Jakarta Pusat',
                decoration: const InputDecoration(labelText: 'Alamat'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '+62 21 1234 5678',
                decoration: const InputDecoration(labelText: 'Telepon'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: 'workshop@vanessaemas.com',
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Informasi workshop berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showOperatingHoursSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jam Operasional'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Senin - Jumat:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '08:00',
                      decoration: const InputDecoration(labelText: 'Buka'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: '17:00',
                      decoration: const InputDecoration(labelText: 'Tutup'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Sabtu:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '08:00',
                      decoration: const InputDecoration(labelText: 'Buka'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: '15:00',
                      decoration: const InputDecoration(labelText: 'Tutup'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Minggu & Hari Libur: Tutup',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Jam operasional berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showCapacitySettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kapasitas Workshop'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: '8',
                decoration: const InputDecoration(labelText: 'Jumlah Teknisi'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '12',
                decoration: const InputDecoration(
                  labelText: 'Jumlah Workstation',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '25',
                decoration: const InputDecoration(
                  labelText: 'Kapasitas Order per Hari',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '50',
                decoration: const InputDecoration(
                  labelText: 'Kapasitas Order per Bulan',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kapasitas workshop berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showServiceCategoriesSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori Layanan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Reparasi'),
                value: true,
                onChanged: (value) {},
              ),
              CheckboxListTile(
                title: const Text('Custom Order'),
                value: true,
                onChanged: (value) {},
              ),
              CheckboxListTile(
                title: const Text('Buyback'),
                value: true,
                onChanged: (value) {},
              ),
              CheckboxListTile(
                title: const Text('Service Rutin'),
                value: true,
                onChanged: (value) {},
              ),
              CheckboxListTile(
                title: const Text('Cleaning & Polish'),
                value: true,
                onChanged: (value) {},
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Tambah Kategori Baru'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kategori layanan berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showTimeEstimatesSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estimasi Waktu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TimeEstimateItem(service: 'Reparasi Ringan', hours: '2-4'),
              _TimeEstimateItem(service: 'Reparasi Berat', hours: '8-12'),
              _TimeEstimateItem(service: 'Custom Order', hours: '24-72'),
              _TimeEstimateItem(service: 'Buyback', hours: '1-2'),
              _TimeEstimateItem(service: 'Cleaning & Polish', hours: '1-3'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Estimasi waktu berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showPricingSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Harga Standar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PricingItem(service: 'Konsultasi', price: '50,000'),
              _PricingItem(service: 'Cleaning Basic', price: '25,000'),
              _PricingItem(service: 'Polish', price: '75,000'),
              _PricingItem(service: 'Reparasi Ringan', price: '100,000'),
              _PricingItem(service: 'Reparasi Berat', price: '500,000'),
              const SizedBox(height: 16),
              const Text(
                '*Harga custom order berdasarkan kesepakatan',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Harga standar berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showMinimumStockSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Minimum Stok'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StockThresholdItem(
                material: 'Emas 24K',
                current: '125.5',
                minimum: '50',
                unit: 'gram',
              ),
              _StockThresholdItem(
                material: 'Perak 99.9%',
                current: '89.2',
                minimum: '30',
                unit: 'gram',
              ),
              _StockThresholdItem(
                material: 'Lem Emas',
                current: '12',
                minimum: '5',
                unit: 'botol',
              ),
              _StockThresholdItem(
                material: 'Cat Emas',
                current: '8',
                minimum: '3',
                unit: 'kaleng',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Minimum stok berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showSupplierSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daftar Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SupplierItem(
                name: 'PT Emas Jaya',
                contact: '+62 21 9876 5432',
                category: 'Logam Mulia',
              ),
              _SupplierItem(
                name: 'CV Perak Indah',
                contact: '+62 21 8765 4321',
                category: 'Perak',
              ),
              _SupplierItem(
                name: 'UD Kimia Emas',
                contact: '+62 21 7654 3210',
                category: 'Bahan Kimia',
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Tambah Supplier'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showMaterialCategoriesSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori Material'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CategoryItem(name: 'Logam Mulia'),
              _CategoryItem(name: 'Logam'),
              _CategoryItem(name: 'Bahan Kimia'),
              _CategoryItem(name: 'Peralatan'),
              _CategoryItem(name: 'Packaging'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Tambah Kategori'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kategori material berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showTechnicianSpecializationsSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spesialisasi Teknisi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SpecializationItem(
                technician: 'Ahmad Surya',
                specializations: ['Reparasi', 'Custom Order'],
              ),
              _SpecializationItem(
                technician: 'Budi Santoso',
                specializations: ['Buyback', 'Cleaning'],
              ),
              _SpecializationItem(
                technician: 'Citra Dewi',
                specializations: ['Reparasi', 'Polish'],
              ),
              _SpecializationItem(
                technician: 'Dedi Kurniawan',
                specializations: ['Custom Order', 'Reparasi'],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showProductivityTargetsSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Target Produktivitas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: '5',
                decoration: const InputDecoration(
                  labelText: 'Target Order per Hari per Teknisi',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '25',
                decoration: const InputDecoration(
                  labelText: 'Target Order per Bulan per Teknisi',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: '95',
                decoration: const InputDecoration(
                  labelText: 'Target Tingkat Kepuasan (%)',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Target produktivitas berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showWorkScheduleSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jadwal Kerja Teknisi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Shift Pagi: 08:00 - 16:00'),
              const Text('Shift Siang: 16:00 - 24:00'),
              const SizedBox(height: 16),
              const Text('Teknisi Shift Pagi: Ahmad, Citra'),
              const Text('Teknisi Shift Siang: Budi, Dedi'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit),
                label: const Text('Edit Jadwal'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pengaturan Notifikasi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Order Baru'),
                subtitle: const Text('Notifikasi ketika ada order masuk'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('Stok Rendah'),
                subtitle: const Text('Alert ketika material stok rendah'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('Order Terlambat'),
                subtitle: const Text('Reminder untuk order yang terlambat'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('Backup Otomatis'),
                subtitle: const Text('Notifikasi hasil backup harian'),
                value: false,
                onChanged: (value) {},
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pengaturan notifikasi berhasil diperbarui'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showBackupSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup & Restore'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Backup Manual'),
                subtitle: const Text('Buat backup data sekarang'),
                trailing: const Icon(Icons.backup),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Backup manual sedang diproses...'),
                  ),
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Backup Otomatis'),
                subtitle: const Text('Backup harian pukul 02:00'),
                value: true,
                onChanged: (value) {},
              ),
              const SizedBox(height: 16),
              const Text('Backup Terakhir: 15 Jan 2025 02:00'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.restore),
                label: const Text('Restore dari Backup'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showIntegrationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pengaturan Integrasi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('WhatsApp Business'),
                subtitle: const Text('Terhubung - API aktif'),
                trailing: Icon(Icons.check_circle, color: Colors.green[600]),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Email Service'),
                subtitle: const Text('Terhubung - SMTP aktif'),
                trailing: Icon(Icons.check_circle, color: Colors.green[600]),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Payment Gateway'),
                subtitle: const Text('Belum terhubung'),
                trailing: Icon(Icons.error, color: Colors.red[600]),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Cloud Storage'),
                subtitle: const Text('Google Drive - Terhubung'),
                trailing: Icon(Icons.check_circle, color: Colors.green[600]),
                onTap: () {},
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCategory extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCategory({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).primaryColor.withValues(alpha: 0.1),
          child: Icon(icon, color: Theme.of(context).primaryColor),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class _TimeEstimateItem extends StatelessWidget {
  final String service;
  final String hours;

  const _TimeEstimateItem({required this.service, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(service)),
          Text(
            '$hours jam',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PricingItem extends StatelessWidget {
  final String service;
  final String price;

  const _PricingItem({required this.service, required this.price});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(service)),
          Text(
            'Rp $price',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StockThresholdItem extends StatelessWidget {
  final String material;
  final String current;
  final String minimum;
  final String unit;

  const _StockThresholdItem({
    required this.material,
    required this.current,
    required this.minimum,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(material, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: minimum,
                  decoration: InputDecoration(labelText: 'Minimum ($unit)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Text('Sekarang: $current $unit'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierItem extends StatelessWidget {
  final String name;
  final String contact;
  final String category;

  const _SupplierItem({
    required this.name,
    required this.contact,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact),
            Text('Kategori: $category', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 20),
          onPressed: () {},
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final String name;

  const _CategoryItem({required this.name});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name),
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 20),
          onPressed: () {},
        ),
      ),
    );
  }
}

class _SpecializationItem extends StatelessWidget {
  final String technician;
  final List<String> specializations;

  const _SpecializationItem({
    required this.technician,
    required this.specializations,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(technician),
        subtitle: Text('Spesialisasi: ${specializations.join(", ")}'),
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 20),
          onPressed: () {},
        ),
      ),
    );
  }
}
