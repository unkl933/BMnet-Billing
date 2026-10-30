# BMnet-Billing 🚀

**BMnet-Billing** adalah aplikasi mobile berbasis Flutter yang dirancang khusus untuk mengelola sistem penagihan (*billing*) pada usaha Mikro Internet Service Provider (Mini ISP). Aplikasi ini terintegrasi secara *real-time* dengan **Google Sheets** menggunakan **Google Apps Script** sebagai REST API tanpa memerlukan konfigurasi backend yang rumit.

---

## 📌 Fitur Utama
* **Manajemen Data Pelanggan**: Menampilkan daftar lengkap seluruh pelanggan secara dinamis.
* **Tambah Pelanggan Baru**: Form input data terstruktur (Nama, Alamat, Paket, No WhatsApp, NIK, dan Sales).
* **Auto-Generate IDPEL**: Sistem secara otomatis membuat ID Pelanggan unik jika dikosongkan saat pendaftaran.
* **Integrasi Google Spreadsheet**: Penyimpanan data terpusat di cloud yang mudah diakses, diexport, dan dibagikan.

---

## 📋 Daftar Paket Internet & Harga
Berdasarkan data operasional aktif, berikut adalah pilihan paket yang didukung oleh sistem:
* **LITE 7 Mbps** — Rp 90.090 / bulan
* **BASIC 10 Mbps** — Rp 108.108 / bulan
* **Paket Building (Free Android TV)** — Rp 121.622 / bulan
* **STANDAR 15 Mbps** — Rp 135.135 / bulan
* **25 Mbps** — Rp 200.000 / bulan
* **50 Mbps** — Rp 500.000 / bulan

---

## 📊 Struktur Kolom Google Sheets
Pastikan sheet pertama pada Google Spreadsheet Anda menggunakan format kolom berikut agar sinkron dengan aplikasi:

| Kolom | Header Spreadsheet | Keterangan |
| :---: | :--- | :--- |
| **A** | `NO` | Nomor urut pelanggan |
| **B** | `NAMA` | Nama lengkap pelanggan |
| **C** | `IDPEL` | ID Pelanggan unik (misal: `027260713004`) |
| **D** | `ALAMAT` | Alamat lokasi / kampung |
| **E** | `NO KTP` / `NIK` | Nomor Identitas Kependudukan |
| **F** | `NO WA` | Nomor WhatsApp aktif |
| **G** | `PAKET` | Nama paket internet yang dilanggan |
| **H** | `HARGA` | Nominal tagihan bulanan |
| **I** | `JATUH TEMPO` | Tanggal jatuh tempo pembayaran (cth: Tanggal 5) |
| **J** | `SALES` | Nama sales/petugas pencatat (opsional) |

---

## 🛠️ Persyaratan Sistem & Instalasi
1. **Flutter SDK** (Versi terbaru disarankan).
2. Koneksi internet untuk sinkronisasi data Google Sheets.
3. Tambahkan dependency `http` pada file `pubspec.yaml` proyek Anda:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     http: ^1.2.0
   ```

---

## 🚀 Panduan Menjalankan Proyek

1. **Clone Repositori Ini**:
   ```bash
   git clone https://github.com/USERNAME_ANDA/BMnet-Billing.git
   cd BMnet-Billing
   ```

2. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

3. **Konfigurasi URL Backend**:
   * Buat Google Apps Script di Google Sheets Anda.
   * Masukkan URL Web App Google Apps Script ke dalam variabel `scriptUrl` di file `lib/main.dart`:
     ```dart
     const String scriptUrl = 'URL_WEB_APP_GOOGLE_APPS_SCRIPT_ANDA';
     ```

4. **Jalankan Aplikasi**:
   ```bash
   flutter run
   ```

---

## 📄 Lisensi
Proyek ini bersifat open-source dan bebas digunakan untuk kebutuhan pengelolaan jaringan RT/RW Net atau Mini ISP Anda.