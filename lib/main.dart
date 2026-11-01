import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

const String scriptUrl = 'https://script.google.com/macros/s/AKfycbwkQ4HbMaBlE4tVxlIUIfhNTgXgkgmzz-kWF-CHmuMMs1BB95okkMvuntsCFwx_F0M/exec';
// Theme Colors
const Color bgDark = Color(0xFF090D16);
const Color surfaceDark = Color(0xFF141C2E);
const Color cardDark = Color(0xFF1E293B);
const Color primaryCyan = Color(0xFF06B6D4);
const Color accentBlue = Color(0xFF3B82F6);
const Color colorEmerald = Color(0xFF10B981);
const Color colorRose = Color(0xFFF43F5E);
const Color textMuted = Color(0xFF94A3B8);

List daftarPaketGlobal = [
  {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
  {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
  {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
  {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
];

void main() {
  runApp(const BMNetworkApp());
}

class BMNetworkApp extends StatelessWidget {
  const BMNetworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BM Network Ops',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        colorScheme: const ColorScheme.dark(
          primary: primaryCyan,
          secondary: accentBlue,
          surface: surfaceDark,
          error: colorRose,
        ),
        cardTheme: CardThemeData(
          color: cardDark,
          elevation: 4,
          shadowColor: Colors.black45,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryCyan,
          foregroundColor: Colors.black,
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F172A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryCyan, width: 2)),
          labelStyle: const TextStyle(color: textMuted),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  List pelangganData = [];
  List pengeluaranData = [];
  List stokData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? colorRose : colorEmerald,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(scriptUrl));
      if (response.statusCode == 200 || response.statusCode == 302) {
        final decoded = json.decode(response.body);
        if (decoded is Map) {
          List rawPelanggan = decoded['pelanggan'] ?? [];
          List listPelanggan = rawPelanggan.map((item) {
            return {
              'idpel': (item['idpel'] ?? item['id_pelanggan'] ?? '').toString(),
              'nama': (item['nama'] ?? item['nama_pelanggan'] ?? '').toString(),
              'alamat': (item['alamat'] ?? '').toString(),
              'paket': (item['paket'] ?? '').toString(),
              'harga': (item['harga'] ?? '').toString(),
              'no_hp': (item['no_hp'] ?? '').toString(),
              'teknisi': (item['teknisi'] ?? '').toString(),
              'jumlah_bulan_tunggakan': (item['jumlah_bulan_tunggakan'] ?? '1').toString(),
              'petugas_penerima': (item['petugas_penerima'] ?? '').toString(),
              'status': (item['status'] ?? 'Belum Lunas').toString(),
              'total_tunggakan': (item['total_tunggakan'] ?? '0').toString(),
              'metode_pembayaran': (item['metode_pembayaran'] ?? '').toString(),
              'material_terpakai': (item['material_terpakai'] ?? '').toString(),
            };
          }).toList();

          List rawPengeluaran = decoded['pengeluaran'] ?? [];
          List listPengeluaran = rawPengeluaran.map((item) {
            return {
              'tanggal': (item['tanggal'] ?? '-').toString(),
              'kategori': (item['kategori'] ?? 'Operasional').toString(),
              'keterangan': (item['keterangan'] ?? '-').toString(),
              'nominal': (item['nominal'] ?? '0').toString(),
              'jumlah_stok': (item['jumlah_stok'] ?? '').toString(),
              'satuan_stok': (item['satuan_stok'] ?? '').toString(),
            };
          }).toList();

          List rawStok = decoded['stok'] ?? [];
          List listStok = rawStok.map((item) {
            return {
              'nama_barang': (item['nama_barang'] ?? '-').toString(),
              'kategori': (item['kategori'] ?? 'Umum').toString(),
              'jumlah': (item['jumlah'] ?? '0').toString(),
              'satuan': (item['satuan'] ?? 'Pcs').toString(),
              'keterangan': (item['keterangan'] ?? '-').toString(),
            };
          }).toList();

          if (decoded['paket'] != null && (decoded['paket'] as List).isNotEmpty) {
            List listPaketBaru = [];
            for (var item in (decoded['paket'] as List)) {
              listPaketBaru.add({
                'nama': (item['nama_paket'] ?? item['nama'] ?? '').toString(),
                'harga': (item['harga'] ?? '').toString(),
              });
            }
            daftarPaketGlobal = listPaketBaru;
          }

          setState(() {
            pelangganData = listPelanggan;
            pengeluaranData = listPengeluaran;
            stokData = listStok;
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
        _showSnackBar('Gagal terhubung: HTTP ${response.statusCode}', isError: true);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Koneksi Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PelangganView(pelanggan: pelangganData, stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      PengeluaranView(pengeluaran: pengeluaranData, stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      StokBarangView(stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      PaketInternetView(isLoading: isLoading, onRefresh: fetchData),
      DashboardKeuanganView(pelanggan: pelangganData, pengeluaran: pengeluaranData, isLoading: isLoading, onRefresh: fetchData),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: surfaceDark,
          indicatorColor: primaryCyan.withOpacity(0.2),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people, color: primaryCyan), label: 'Pelanggan'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long, color: primaryCyan), label: 'Pengeluaran'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2, color: primaryCyan), label: 'Stok'),
            NavigationDestination(icon: Icon(Icons.wifi_tethering), selectedIcon: Icon(Icons.wifi_tethering, color: primaryCyan), label: 'Paket'),
            NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics, color: primaryCyan), label: 'Keuangan'),
          ],
        ),
      ),
    );
  }
}

// ================= TAB 1: PELANGGAN =================
class PelangganView extends StatefulWidget {
  final List pelanggan;
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PelangganView({super.key, required this.pelanggan, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  State<PelangganView> createState() => _PelangganViewState();
}

class _PelangganViewState extends State<PelangganView> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    List filtered = widget.pelanggan.where((p) {
      final q = searchQuery.toLowerCase();
      final nama = (p['nama'] ?? '').toString().toLowerCase();
      final idpel = (p['idpel'] ?? '').toString().toLowerCase();
      return nama.contains(q) || idpel.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Pelanggan'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryCyan), onPressed: widget.onRefresh),
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryCyan))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    onChanged: (val) => setState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Cari Pelanggan / ID...',
                      prefixIcon: const Icon(Icons.search, color: textMuted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Data pelanggan tidak ditemukan.', style: TextStyle(color: textMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            bool isLunas = (item['status'] ?? '').toString().toLowerCase() == 'lunas';
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                onTap: () => _showDetailModal(context, item),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isLunas ? colorEmerald.withOpacity(0.15) : colorRose.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isLunas ? Icons.check_circle : Icons.warning_amber_rounded,
                                    color: isLunas ? colorEmerald : colorRose,
                                  ),
                                ),
                                title: Text(item['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                subtitle: Text('ID: ${item['idpel']} • ${item['paket']}', style: const TextStyle(color: textMuted, fontSize: 12)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Rp ${item['total_tunggakan']}', style: TextStyle(fontWeight: FontWeight.bold, color: isLunas ? colorEmerald : colorRose)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isLunas ? colorEmerald.withOpacity(0.2) : colorRose.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isLunas ? 'LUNAS' : 'TAGIHAN',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLunas ? colorEmerald : colorRose),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Pasang Baru', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => FormTambahPelangganPage(stokList: widget.stok)));
          if (res == true) widget.onRefresh();
        },
      ),
    );
  }

  void _showDetailModal(BuildContext context, Map item) {
    bool isLunas = (item['status'] ?? '').toString().toLowerCase() == 'lunas';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item['nama'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLunas ? colorEmerald.withOpacity(0.2) : colorRose.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isLunas ? colorEmerald : colorRose),
                  ),
                  child: Text(isLunas ? 'LUNAS' : 'BELUM LUNAS', style: TextStyle(fontWeight: FontWeight.bold, color: isLunas ? colorEmerald : colorRose, fontSize: 11)),
                )
              ],
            ),
            const Divider(color: Color(0xFF334155), height: 24),
            _infoRow('ID Pelanggan', item['idpel']),
            _infoRow('Alamat', item['alamat']),
            _infoRow('Paket Internet', '${item['paket']} (${item['harga']})'),
            _infoRow('No WhatsApp', item['no_hp']),
            _infoRow('Teknisi', item['teknisi']),
            _infoRow('Total Tagihan', 'Rp ${item['total_tunggakan']} (${item['jumlah_bulan_tunggakan']} Bln)'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: primaryCyan, side: const BorderSide(color: primaryCyan)),
                    onPressed: () {
                      Navigator.pop(context);
                      _cetakNotaPdf(item, isLunas);
                    },
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('Nota PDF'),
                  ),
                ),
                const SizedBox(width: 10),
                if (!isLunas)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: colorEmerald, foregroundColor: Colors.black),
                      onPressed: () {
                        Navigator.pop(context);
                        _showModalBayar(context, item);
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Bayar'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String? val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: textMuted, fontSize: 13)),
          Text(val ?? '-', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  void _showModalBayar(BuildContext context, Map item) {
    String selectedMetode = 'Tunai';
    final TextEditingController kasirCtrl = TextEditingController(text: 'Admin BM Network');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: surfaceDark,
          title: Text('Pelunasan: ${item['nama']}', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total Tagihan: Rp ${item['total_tunggakan']}', style: const TextStyle(color: primaryCyan, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: kasirCtrl, decoration: const InputDecoration(labelText: 'Nama Petugas/Kasir')),
              const SizedBox(height: 12),
              DropdownButtonFormField(
                dropdownColor: surfaceDark,
                value: selectedMetode,
                decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                items: ['Tunai', 'Transfer BCA', 'QRIS', 'DANA', 'OVO', 'GoPay'].map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: (val) => setDlgState(() => selectedMetode = val.toString()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Batal', style: TextStyle(color: textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colorEmerald, foregroundColor: Colors.black),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final payload = {
                  "action": "bayar_pelanggan",
                  "idpel": item['idpel'],
                  "metode_pembayaran": selectedMetode,
                  "petugas_penerima": kasirCtrl.text,
                };
                await http.post(Uri.parse(scriptUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
                widget.onRefresh();
              },
              child: const Text('Konfirmasi Lunas', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cetakNotaPdf(Map item, bool isLunas) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BM NETWORK - NOTA RESMI', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.Text('ID Pelanggan : ${item['idpel']}'),
                pw.Text('Nama         : ${item['nama']}'),
                pw.Text('Paket        : ${item['paket']}'),
                pw.Text('Total        : Rp ${item['total_tunggakan']}'),
                pw.Text('Status       : ${isLunas ? "LUNAS" : "BELUM LUNAS"}'),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}

// FORM TAMBAH PELANGGAN
class FormTambahPelangganPage extends StatefulWidget {
  final List stokList;
  const FormTambahPelangganPage({super.key, required this.stokList});

  @override
  State<FormTambahPelangganPage> createState() => _FormTambahPelangganPageState();
}

class _FormTambahPelangganPageState extends State<FormTambahPelangganPage> {
  final _formKey = GlobalKey<FormState>();
  final _namaCtrl = TextEditingController();
  final _alamatCtrl = TextEditingController();
  final _hpCtrl = TextEditingController();
  final _teknisiCtrl = TextEditingController();
  var selectedPaket;
  bool isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pasang Baru Pelanggan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _namaCtrl, decoration: const InputDecoration(labelText: 'Nama Lengkap'), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _alamatCtrl, decoration: const InputDecoration(labelText: 'Alamat Pemasangan'), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _hpCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'No WhatsApp')),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              dropdownColor: surfaceDark,
              decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
              items: daftarPaketGlobal.map((p) => DropdownMenuItem(value: p, child: Text('${p['nama']} (${p['harga']})', style: const TextStyle(color: Colors.white)))).toList(),
              onChanged: (val) => setState(() => selectedPaket = val),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _teknisiCtrl, decoration: const InputDecoration(labelText: 'Nama Teknisi')),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryCyan, foregroundColor: Colors.black, padding: const EdgeInsets.all(16)),
              onPressed: isSaving ? null : () async {
                if (!_formKey.currentState!.validate() || selectedPaket == null) return;
                setState(() => isSaving = true);

                final payload = {
                  "action": "tambah_pelanggan",
                  "nama": _namaCtrl.text,
                  "alamat": _alamatCtrl.text,
                  "no_hp": _hpCtrl.text,
                  "paket": selectedPaket['nama'],
                  "harga": selectedPaket['harga'],
                  "teknisi": _teknisiCtrl.text.isEmpty ? "Teknisi Field" : _teknisiCtrl.text,
                  "total_tunggakan": selectedPaket['harga'].toString().replaceAll(RegExp(r'[^0-9]'), ''),
                };

                await http.post(Uri.parse(scriptUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
                if (mounted) Navigator.pop(context, true);
              },
              child: isSaving ? const CircularProgressIndicator(color: Colors.black) : const Text('Simpan Pelanggan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= TAB 2: PENGELUARAN =================
class PengeluaranView extends StatelessWidget {
  final List pengeluaran;
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PengeluaranView({super.key, required this.pengeluaran, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pengeluaran Operasional (${pengeluaran.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryCyan), onPressed: onRefresh)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryCyan))
          : pengeluaran.isEmpty
              ? const Center(child: Text('Belum ada data pengeluaran.', style: TextStyle(color: textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: pengeluaran.length,
                  itemBuilder: (context, index) {
                    final item = pengeluaran[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: colorRose.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.arrow_downward, color: colorRose),
                        ),
                        title: Text(item['keterangan'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text('${item['kategori']} • ${item['tanggal']}', style: const TextStyle(color: textMuted, fontSize: 12)),
                        trailing: Text('Rp ${item['nominal']}', style: const TextStyle(fontWeight: FontWeight.bold, color: colorRose, fontSize: 14)),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Tambah Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showDialogTambahPengeluaran(context),
      ),
    );
  }

  void _showDialogTambahPengeluaran(BuildContext context) {
    final ketCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    final jmlStokCtrl = TextEditingController(text: '1');
    String kategori = 'Operasional';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: surfaceDark,
          title: const Text('Tambah Pengeluaran Baru', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                dropdownColor: surfaceDark,
                value: kategori,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: ['Operasional', 'Belanja Aset', 'Gaji Karyawan', 'Maintenance'].map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: (v) => setDlgState(() => kategori = v.toString()),
              ),
              const SizedBox(height: 10),
              TextField(controller: ketCtrl, decoration: const InputDecoration(labelText: 'Keterangan Barang/Jasa')),
              const SizedBox(height: 10),
              TextField(controller: nomCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal Biaya (Rp)')),
              if (kategori == 'Belanja Aset') ...[
                const SizedBox(height: 10),
                TextField(controller: jmlStokCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Unit Masuk Stok')),
              ]
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Batal', style: TextStyle(color: textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryCyan, foregroundColor: Colors.black),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final payload = {
                  "action": "tambah_pengeluaran",
                  "kategori": kategori,
                  "keterangan": ketCtrl.text,
                  "nominal": nomCtrl.text,
                  "jumlah_stok": jmlStokCtrl.text,
                  "satuan_stok": "Pcs"
                };
                await http.post(Uri.parse(scriptUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
                onRefresh();
              },
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= TAB 3: STOK BARANG =================
class StokBarangView extends StatelessWidget {
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const StokBarangView({super.key, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stok Barang Gudang (${stok.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryCyan), onPressed: onRefresh)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryCyan))
          : stok.isEmpty
              ? const Center(child: Text('Belum ada stok barang.', style: TextStyle(color: textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: stok.length,
                  itemBuilder: (context, index) {
                    final item = stok[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: accentBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.router, color: accentBlue),
                        ),
                        title: Text(item['nama_barang'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text('Kategori: ${item['kategori']}', style: const TextStyle(color: textMuted, fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: primaryCyan.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text('${item['jumlah']} ${item['satuan']}', style: const TextStyle(fontWeight: FontWeight.bold, color: primaryCyan, fontSize: 13)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ================= TAB 4: PAKET INTERNET =================
class PaketInternetView extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PaketInternetView({super.key, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Paket Internet (${daftarPaketGlobal.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryCyan), onPressed: onRefresh)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryCyan))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: daftarPaketGlobal.length,
              itemBuilder: (context, index) {
                final item = daftarPaketGlobal[index];
                return Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: primaryCyan.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.speed, color: primaryCyan),
                    ),
                    title: Text(item['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text('Tarif Bulanan: ${item['harga']}', style: const TextStyle(color: textMuted)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Tambah Paket', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showDialogTambahPaket(context),
      ),
    );
  }

  void _showDialogTambahPaket(BuildContext context) {
    final namaCtrl = TextEditingController();
    final hargaCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surfaceDark,
        title: const Text('Tambah Paket Internet', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: namaCtrl, decoration: const InputDecoration(labelText: 'Nama Paket (mis: 20 Mbps)')),
            const SizedBox(height: 10),
            TextField(controller: hargaCtrl, decoration: const InputDecoration(labelText: 'Harga (mis: Rp 150.000)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Batal', style: TextStyle(color: textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryCyan, foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final payload = {
                "action": "tambah_paket",
                "nama": namaCtrl.text,
                "harga": hargaCtrl.text,
              };
              await http.post(Uri.parse(scriptUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
              onRefresh();
            },
            child: const Text('Simpan Paket', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ================= TAB 5: KEUANGAN =================
class DashboardKeuanganView extends StatelessWidget {
  final List pelanggan;
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const DashboardKeuanganView({super.key, required this.pelanggan, required this.pengeluaran, required this.isLoading, required this.onRefresh});

  int _parse(dynamic val) {
    if (val == null) return 0;
    return int.tryParse(val.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    int totalPemasukan = 0;
    int totalPiutang = 0;
    int totalPengeluaran = 0;

    for (var p in pelanggan) {
      int nominal = _parse(p['total_tunggakan']);
      if ((p['status'] ?? '').toString().toLowerCase() == 'lunas') {
        totalPemasukan += nominal;
      } else {
        totalPiutang += nominal;
      }
    }

    for (var ex in pengeluaran) {
      totalPengeluaran += _parse(ex['nominal']);
    }

    int labaBersih = totalPemasukan - totalPengeluaran;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Analytics'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryCyan), onPressed: onRefresh)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryCyan))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _cardStat('Pemasukan Lunas', 'Rp $totalPemasukan', colorEmerald, Icons.trending_up),
                const SizedBox(height: 12),
                _cardStat('Total Piutang Tagihan', 'Rp $totalPiutang', Colors.amber, Icons.pending_actions),
                const SizedBox(height: 12),
                _cardStat('Total Pengeluaran', 'Rp $totalPengeluaran', colorRose, Icons.trending_down),
                const SizedBox(height: 20),
                Card(
                  color: surfaceDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: labaBersih >= 0 ? primaryCyan : colorRose, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('ESTIMASI LABA / RUGI BERSIH', style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        Text('Rp $labaBersih', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: labaBersih >= 0 ? primaryCyan : colorRose)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _cardStat(String title, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
