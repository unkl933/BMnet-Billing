# 📶 BMnet Billing - Application System Mini ISP

Aplikasi manajemen billing dan operasional *Mini ISP* berbasis Flutter yang terintegrasi secara *real-time* dengan Google Sheets melalui Google Apps Script (GAS). Aplikasi ini mempermudah pencatatan pelanggan, pengelolaan tunggakan, kalkulasi pajak PPN 11%, pencetakan struk pembayaran via Bluetooth Thermal Printer, serta pembagian nota digital via WhatsApp.

---

## 🌟 Fitur Utama

- **Management Data Pelanggan:**
  - Tambah, Edit, dan Hapus data pelanggan secara *real-time*.
  - Pencarian fleksibel berdasarkan nama pelanggan.
  - Pengurutan data (Berdasarkan Nama, Alamat, Paket, Status Lunas / Belum Lunas).
- **Sistem Pembayaran & Tunggakan:**
  - Perhitungan **PPN 11%** otomatis dari harga dasar paket.
  - Pencatatan jumlah bulan tunggakan dan pembagian nominal pembayaran (Lunas / Pembayaran Sebagian / Cicilan).
  - Pilihan metode pembayaran yang beragam (**Tunai**, **QRIS**, **Transfer Bank**).
  - Pencatatan nama petugas/kasir penerima pembayaran.
- **Cetak Struk & Pembagian Digital:**
  - **Bluetooth Thermal Printer Integration:** Cetak struk fisik langsung ke printer kasir portable/thermal bluetooth.
  - **Share Struk via WhatsApp (`share_plus`):** Bagikan teks bukti pembayaran resmi beserta detail transaksi langsung ke aplikasi WhatsApp pelanggan.

---

## 💰 Daftar Harga Paket Internet (Termasuk PPN 11%)

Berikut adalah rincian perhitungan harga dasar paket internet setelah ditambahkan kalkulasi otomatis **PPN 11%**:

| Nama Paket Internet | Harga Dasar (Excl. PPN) | PPN 11% | Total Harga (Incl. PPN 11%) |
| :--- | :---: | :---: | :---: |
| **LITE 7 Mbps** | Rp 90.090 | Rp 9.910 | **Rp 100.000** |
| **BASIC 10 Mbps** | Rp 108.108 | Rp 11.892 | **Rp 120.000** |
| **Paket Building (Free Android TV)** | Rp 121.622 | Rp 13.378 | **Rp 135.000** |
| **STANDAR 15 Mbps** | Rp 135.135 | Rp 14.865 | **Rp 150.000** |
| **25 Mbps** | Rp 200.000 | Rp 22.000 | **Rp 222.000** |
| **50 Mbps** | Rp 500.000 | Rp 55.000 | **Rp 555.000** |

---

## 🧾 Struktur Kolom Spreadsheet (Google Apps Script)

Proses penyimpanan data di Google Sheets memanfaatkan urutan kolom berikut:

| Index | Nama Kolom | Keterangan |
| :---: | :--- | :--- |
| **A** | `no` | Nomor Urut |
| **B** | `idpel` | ID Pelanggan (Contoh: `BM001`) |
| **C** | `nama` | Nama Lengkap Pelanggan |
| **D** | `alamat` | Alamat Rumah / Pemasangan |
| **E** | `paket` | Nama Paket Internet |
| **F** | `harga` | Harga Dasar Paket |
| **G** | `no_hp` | Nomor WhatsApp |
| **H** | `nik` | Nomor KTP / NIK |
| **I** | `jatuh_tempo` | Tanggal Jatuh Tempo (Misal: Tanggal 5) |
| **J** | `status` | Status Tagihan (`Lunas` / `Belum Lunas`) |
| **K** | `sales` | Nama Sales Pemasangan |
| **L** | `metode_pembayaran` | Tunai / QRIS / Transfer Bank |
| **M** | `diterima_oleh` | Nama Kasir / Admin Penerima |
| **N** | `jumlah_bulan_tunggakan` | Durasi Tunggakan (Bulan) |
| **O** | `total_tunggakan` | Total Nominal Tagihan (Incl. PPN 11%) |
| **P** | `sisa_tunggakan` | Sisa Tagihan (Jika Pembayaran Sebagian) |

---

## 🛠️ Stack Teknologi & Dependensi Utama

- **Framework:** [Flutter](https://flutter.dev) (Dart)
- **Backend Storage:** Google Sheets API via Google Apps Script (Web App)
- **CI/CD:** GitHub Actions (Automated Flutter Release Build)
- **Dependencies (`pubspec.yaml`):**
  - `http`: Pengiriman request HTTP API.
  - `print_bluetooth_thermal`: Integrasi koneksi & cetak printer thermal bluetooth.
  - `share_plus`: Fitur pembagian teks nota/struk pembayaran.

---

## 🚀 Panduan Deploy GitHub Actions

Repositori ini telah dikonfigurasi dengan workflow otomatis untuk membuat APK *Release* secara terotomatisasi.

1. Lakukan *commit* dan *push* perubahan kode ke *branch* `main`:
   ```bash
   git add .
   git commit -m "feat: pembaruan aplikasi dan dokumentasi"
   git push origin main
   ```
2. Buka tab **Actions** di repositori GitHub (`BMnet-Billing`).
3. Pilih workflow **Build Release APK** untuk mengunduh file `.apk` terbaru hasil kompilasi.