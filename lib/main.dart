import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

const String scriptUrl = 'https://script.google.com/macros/s/AKfycbzZdliydavTiyFWecz1OvPjGMh6vGd3-5zPbxoHRV95EBz5k9-rrNTvQ5k5MBm_9FmDhQ/exec';

void main() {
  runApp(const MaterialApp(
    home: MainNavigationScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

// ================= NAVIGASI UTAMA (TAB BAR) =================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  List pelangganData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPelanggan();
  }

  Future<void> fetchPelanggan() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(scriptUrl));
      if (response.statusCode == 200 || response.statusCode == 302) {
        setState(() {
          pelangganData = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil data dari server: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      BillingHomePage(
        pelanggan: pelangganData,
        isLoading: isLoading,
        onRefresh: fetchPelanggan,
      ),
      DashboardKeuanganPage(
        pelanggan: pelangganData,
        isLoading: isLoading,
        onRefresh: fetchPelanggan,
      ),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Pelanggan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize),
            label: 'Dashboard & Laporan',
          ),
        ],
      ),
    );
  }
}

// ================= HALAMAN DAFTAR PELANGGAN =================
class BillingHomePage extends StatefulWidget {
  final List pelanggan;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const BillingHomePage({
    super.key,
    required this.pelanggan,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<BillingHomePage> createState() => _BillingHomePageState();
}

class _BillingHomePageState extends State<BillingHomePage> {
  List filteredPelanggan = [];
  String searchQuery = '';
  String sortBy = 'default';

  @override
  void initState() {
    super.initState();
    _applyFilterAndSort();
  }

  @override
  void didUpdateWidget(covariant BillingHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    List temp = List.from(widget.pelanggan);

    if (searchQuery.isNotEmpty) {
      temp = temp.where((item) {
        final nama = (item['nama'] ?? '').toString().toLowerCase();
        return nama.contains(searchQuery.toLowerCase());
      }).toList();
    }

    if (sortBy == 'alamat') {
      temp.sort((a, b) => (a['alamat'] ?? '').toString().compareTo((b['alamat'] ?? '').toString()));
    } else if (sortBy == 'paket') {
      temp.sort((a, b) => (a['paket'] ?? '').toString().compareTo((b['paket'] ?? '').toString()));
    } else if (sortBy == 'nama') {
      temp.sort((a, b) => (a['nama'] ?? '').toString().compareTo((b['nama'] ?? '').toString()));
    } else if (sortBy == 'lunas') {
      temp = temp.where((item) => (item['status'] ?? 'Belum Lunas').toString().toLowerCase() == 'lunas').toList();
    } else if (sortBy == 'belum_lunas') {
      temp = temp.where((item) => (item['status'] ?? 'Belum Lunas').toString().toLowerCase() != 'lunas').toList();
    }

    setState(() {
      filteredPelanggan = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Billing Mini ISP (${filteredPelanggan.length} Pelanggan)'),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                sortBy = value.toString();
                _applyFilterAndSort();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'default', child: Text('Urutan Default')),
              const PopupMenuItem(value: 'nama', child: Text('Urutkan Nama')),
              const PopupMenuItem(value: 'alamat', child: Text('Urutkan Alamat')),
              const PopupMenuItem(value: 'paket', child: Text('Urutkan Paket')),
              const PopupMenuItem(value: 'lunas', child: Text('Filter: Sudah Lunas')),
              const PopupMenuItem(value: 'belum_lunas', child: Text('Filter: Belum Lunas')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.onRefresh,
          )
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Cari Nama Pelanggan...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      _applyFilterAndSort();
                    },
                  ),
                ),
                Expanded(
                  child: filteredPelanggan.isEmpty
                      ? const Center(child: Text('Data pelanggan tidak ditemukan.'))
                      : ListView.builder(
                          itemCount: filteredPelanggan.length,
                          itemBuilder: (context, index) {
                            final item = filteredPelanggan[index];
                            final status = (item['status'] ?? 'Belum Lunas').toString();
                            final isLunas = status.toLowerCase() == 'lunas';

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${item['no'] ?? index + 1}'),
                                ),
                                title: Text(
                                  (item['nama'] ?? '').toString(), 
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('ID: ${item['idpel']} | Paket: ${item['paket'] ?? '-'}\nTunggakan: ${item['jumlah_bulan_tunggakan'] ?? '1'} Bulan (Rp ${item['total_tunggakan'] ?? '0'} incl. PPN 11%)'),
                                isThreeLine: true,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isLunas ? Colors.green.shade100 : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: isLunas ? Colors.green.shade800 : Colors.red.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DetailPelangganPage(pelangganData: item),
                                    ),
                                  );
                                  if (result == true) {
                                    widget.onRefresh();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TambahPelangganPage()),
          );
          if (result == true) {
            widget.onRefresh();
          }
        },
      ),
    );
  }
}

// ================= DASHBOARD KEUANGAN & CETAK LAPORAN =================
class DashboardKeuanganPage extends StatelessWidget {
  final List pelanggan;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const DashboardKeuanganPage({
    super.key,
    required this.pelanggan,
    required this.isLoading,
    required this.onRefresh,
  });

  int _parseNominal(dynamic val) {
    if (val == null) return 0;
    String str = val.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(str) ?? 0;
  }

  // FUNGSI MEMBUAT DOKUMEN PDF LAPORAN KEUANGAN
  Future<void> _cetakLaporanPdf(BuildContext context) async {
    final pdf = pw.Document();
    int totalLunas = 0;
    int totalTunggakan = 0;
    int jmlLunas = 0;
    int jmlBelum = 0;

    Map<String, int> rekapKasir = {};
    Map<String, int> rekapMetode = {};

    for (var item in pelanggan) {
      final status = (item['status'] ?? 'Belum Lunas').toString().toLowerCase();
      final total = _parseNominal(item['total_tunggakan']);
      final metode = (item['metode_pembayaran'] ?? '-').toString();
      final kasir = (item['diterima_oleh'] ?? '-').toString();

      if (status == 'lunas') {
        totalLunas += total;
        jmlLunas++;
        if (kasir != '-' && kasir.isNotEmpty) rekapKasir[kasir] = (rekapKasir[kasir] ?? 0) + total;
        if (metode != '-' && metode.isNotEmpty) rekapMetode[metode] = (rekapMetode[metode] ?? 0) + total;
      } else {
        totalTunggakan += total;
        jmlBelum++;
      }
    }

    final now = DateTime.now();
    final tglCetak = "${now.day}/${now.month}/${now.year}";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // HEADER LAPORAN
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BMnet ISP - LAPORAN KEUANGAN', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                      pw.Text('Rekapitulasi Pendapatan & Status Tagihan Bulanan', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('Tanggal Cetak: $tglCetak', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColors.blue800),
              pw.SizedBox(height: 15),

              // RINGKASAN KOTAK KPI
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green300), color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TOTAL PEMASUKAN (LUNAS)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                          pw.SizedBox(height: 5),
                          pw.Text('Rp $totalLunas', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                          pw.Text('$jmlLunas Pelanggan Lunas', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red300), color: PdfColors.red50, borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TOTAL TUNGGAKAN (BELUM)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                          pw.SizedBox(height: 5),
                          pw.Text('Rp $totalTunggakan', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                          pw.Text('$jmlBelum Pelanggan Belum Lunas', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // REKAP METODE PEMBAYARAN
              pw.Text('REKAP METODE PEMBAYARAN', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Metode Pembayaran', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Nominal', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...rekapMetode.entries.map((e) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rp ${e.value}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 20),

              // REKAP KASIR / PETUGAS
              pw.Text('REKAP PENERIMAAN KASIR / PETUGAS', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Nama Petugas / Kasir', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Diterima', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...rekapKasir.entries.map((e) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rp ${e.value}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                    ],
                  )),
                ],
              ),

              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Center(
                child: pw.Text('BMnet Billing System - Laporan Keuangan Otomatis', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Laporan_Keuangan_BMnet.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalPemasukanLunas = 0;
    int totalTunggakan = 0;
    int totalPelangganLunas = 0;
    int totalPelangganBelumLunas = 0;

    Map<String, int> rekapKasir = {};
    Map<String, int> rekapMetode = {};

    for (var item in pelanggan) {
      final status = (item['status'] ?? 'Belum Lunas').toString().toLowerCase();
      final total = _parseNominal(item['total_tunggakan']);
      final metode = (item['metode_pembayaran'] ?? '-').toString();
      final kasir = (item['diterima_oleh'] ?? '-').toString();

      if (status == 'lunas') {
        totalPemasukanLunas += total;
        totalPelangganLunas++;
        if (kasir != '-' && kasir.isNotEmpty) rekapKasir[kasir] = (rekapKasir[kasir] ?? 0) + total;
        if (metode != '-' && metode.isNotEmpty) rekapMetode[metode] = (rekapMetode[metode] ?? 0) + total;
      } else {
        totalTunggakan += total;
        totalPelangganBelumLunas++;
      }
    }

    final totalSemuaPelanggan = pelanggan.length;
    final rasioLunas = totalSemuaPelanggan > 0 ? (totalPelangganLunas / totalSemuaPelanggan) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Keuangan & Laporan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // TOMBOL CETAK LAPORAN PDF
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _cetakLaporanPdf(context),
                    icon: const Icon(Icons.print),
                    label: const Text('Cetak / Unduh Laporan Keuangan (PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 15),

                  // RINGKASAN KPI CARDS
                  Row(
                    children: [
                      Expanded(
                        child: _buildKpiCard(
                          'Pemasukan (Lunas)',
                          'Rp $totalPemasukanLunas',
                          Colors.green.shade700,
                          Icons.account_balance_wallet,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildKpiCard(
                          'Tunggakan (Belum)',
                          'Rp $totalTunggakan',
                          Colors.red.shade700,
                          Icons.pending_actions,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),

                  // PROGRESS BAR PELUNASAN
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Status Pelunasan Bulan Ini', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('${(rasioLunas * 100).toStringAsFixed(1)}% Lunas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: rasioLunas,
                            backgroundColor: Colors.red.shade100,
                            color: Colors.green,
                            minHeight: 10,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Lunas: $totalPelangganLunas Pelanggan', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                              Text('Belum: $totalPelangganBelumLunas Pelanggan', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // REKAP METODE PEMBAYARAN
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rekap Berdasarkan Metode Pembayaran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Divider(),
                          rekapMetode.isEmpty
                              ? const Text('Belum ada data pembayaran lunas.')
                              : Column(
                                  children: rekapMetode.entries.map((e) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                                          Text('Rp ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // REKAP KASIR
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rekap Kas Masuk per Petugas / Kasir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Divider(),
                          rekapKasir.isEmpty
                              ? const Text('Belum ada transaksi yang dicatat petugas.')
                              : Column(
                                  children: rekapKasir.entries.map((e) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.person, size: 18, color: Colors.grey),
                                              const SizedBox(width: 5),
                                              Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                          Text('Rp ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

// ================= HALAMAN DETAIL PELANGGAN =================
class DetailPelangganPage extends StatefulWidget {
  final Map<String, dynamic> pelangganData;

  const DetailPelangganPage({super.key, required this.pelangganData});

  @override
  State<DetailPelangganPage> createState() => _DetailPelangganPageState();
}

class _DetailPelangganPageState extends State<DetailPelangganPage> {
  bool isUpdating = false;

  Future<void> updateStatusData(Map<String, dynamic> payloadData) async {
    setState(() => isUpdating = true);

    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payloadData),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        setState(() {
          widget.pelangganData['status'] = payloadData['status'];
          widget.pelangganData['metode_pembayaran'] = payloadData['metode_pembayaran'];
          widget.pelangganData['diterima_oleh'] = payloadData['diterima_oleh'];
          widget.pelangganData['jumlah_bulan_tunggakan'] = payloadData['jumlah_bulan_tunggakan'];
          widget.pelangganData['total_tunggakan'] = payloadData['total_tunggakan'];
          widget.pelangganData['sisa_tunggakan'] = payloadData['sisa_tunggakan'];
          isUpdating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status pembayaran & tunggakan berhasil diperbarui!')),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Gagal memperbarui ke server');
      }
    } catch (e) {
      setState(() => isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    }
  }

  Future<pw.Document> _buildPdfDocument(bool isLunas) async {
    final pdf = pw.Document();

    final nama = widget.pelangganData['nama'] ?? '-';
    final idpel = widget.pelangganData['idpel'] ?? '-';
    final alamat = widget.pelangganData['alamat'] ?? '-';
    final noHp = widget.pelangganData['no_hp'] ?? '-';
    final paket = widget.pelangganData['paket'] ?? '-';
    final bulan = widget.pelangganData['jumlah_bulan_tunggakan'] ?? '1';
    final totalStr = widget.pelangganData['total_tunggakan']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0';
    final totalInt = int.tryParse(totalStr) ?? 0;

    final subtotalInt = (totalInt / 1.11).round();
    final ppnInt = totalInt - subtotalInt;

    final jatuhTempo = widget.pelangganData['jatuh_tempo'] ?? 'Tanggal 5';
    final sales = widget.pelangganData['sales'] ?? '-';
    final metode = widget.pelangganData['metode_pembayaran'] ?? 'Tunai';
    final kasir = widget.pelangganData['diterima_oleh'] ?? 'Admin BMnet';

    final now = DateTime.now();
    final tglFormat = "${now.day} Oktober ${now.year}";
    final noDokumen = isLunas 
        ? "KW/BM/${now.year}/${now.month.toString().padLeft(2, '0')}/891" 
        : "INV/BM/${now.year}/${now.month.toString().padLeft(2, '0')}/042";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BMnet ISP', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                      pw.Text('Layanan Internet Cepat & Terpercaya', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('Jl. Utama Networking No. 88 | WA Support: 0812-3456-7890', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        isLunas ? 'KWITANSI PELUNASAN' : 'NOTA TAGIHAN', 
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: isLunas ? PdfColors.green800 : PdfColors.red800)
                      ),
                      pw.Text('No. Dokumen: $noDokumen', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Tanggal: $tglFormat', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColors.blue800),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('DATA PELANGGAN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                          pw.SizedBox(height: 4),
                          pw.Text('ID Pelanggan : $idpel', style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('Nama         : $nama', style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('Alamat       : $alamat', style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('No WhatsApp  : $noHp', style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(isLunas ? 'INFORMASI PELUNASAN' : 'RINCIAN TAGIHAN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                          pw.SizedBox(height: 4),
                          if (!isLunas) ...[
                            pw.Text('Jatuh Tempo  : $jatuhTempo', style: const pw.TextStyle(fontSize: 9)),
                            pw.Text('Sales        : $sales', style: const pw.TextStyle(fontSize: 9)),
                          ] else ...[
                            pw.Text('Metode Bayar : $metode', style: const pw.TextStyle(fontSize: 9)),
                            pw.Text('Diterima Oleh: $kasir', style: const pw.TextStyle(fontSize: 9)),
                            pw.Text('Sisa Tunggakan: Rp 0', style: const pw.TextStyle(fontSize: 9)),
                          ],
                          pw.Text('Jumlah Bulan : $bulan Bulan', style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('Status       : ${isLunas ? "LUNAS" : "BELUM LUNAS"}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: isLunas ? PdfColors.green800 : PdfColors.red800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(2.5),
                  4: const pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('No', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Deskripsi Layanan / Paket Internet', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Qty', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Harga Dasar', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Subtotal', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('1', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(paket, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                            pw.Text('Langganan Akses Internet Unlimited Periode Oktober ${now.year}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$bulan Bln', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rp $subtotalInt', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rp $subtotalInt', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 6,
                    child: isLunas
                        ? pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(color: PdfColors.green50, border: pw.Border.all(color: PdfColors.green300)),
                            child: pw.Text('LUNAS\nPembayaran telah diterima sah oleh sistem BMnet ISP.', style: pw.TextStyle(fontSize: 9, color: PdfColors.green900, fontWeight: pw.FontWeight.bold)),
                          )
                        : pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('Instruksi Pembayaran Transfer / QRIS:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                                pw.Text('• Bank BCA: 123-456-7890 a/n BMnet ISP', style: const pw.TextStyle(fontSize: 8)),
                                pw.Text('• Bank Mandiri: 098-765-4321 a/n BMnet ISP', style: const pw.TextStyle(fontSize: 8)),
                                pw.Text('• QRIS: Scan QRIS BMnet di Mobile Banking/E-Wallet.', style: const pw.TextStyle(fontSize: 8)),
                                pw.Text('• Mohon cantumkan IDPEL pada berita transfer.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800)),
                              ],
                            ),
                          ),
                  ),
                  pw.SizedBox(width: 15),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Subtotal (Excl. PPN):', style: const pw.TextStyle(fontSize: 9)),
                            pw.Text('Rp $subtotalInt', style: const pw.TextStyle(fontSize: 9)),
                          ],
                        ),
                        pw.SizedBox(height: 3),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('PPN 11%:', style: const pw.TextStyle(fontSize: 9)),
                            pw.Text('Rp $ppnInt', style: const pw.TextStyle(fontSize: 9)),
                          ],
                        ),
                        pw.Divider(color: PdfColors.grey400),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(isLunas ? 'TOTAL DIBAYAR:' : 'TOTAL TAGIHAN:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            pw.Text('Rp $totalInt', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              if (!isLunas)
                pw.Text(
                  'PERHATIAN: Mohon lakukan pembayaran sebelum tanggal jatuh tempo untuk menghindari pembatasan/isolir otomatis jaringan internet Anda. Apabila telah melakukan pembayaran, abaikan nota penagihan ini.',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Pelanggan,', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 35),
                      pw.Text(nama, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Finance / Petugas Billing,', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 35),
                      pw.Text(kasir, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Center(
                child: pw.Text('BMnet Billing System - Nota & Struk Resmi Otomatis | Halaman 1 dari 1', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  Future<void> sharePdfToWhatsApp(bool isLunas) async {
    try {
      final pdfDoc = await _buildPdfDocument(isLunas);
      final bytes = await pdfDoc.save();

      final outputDir = await getTemporaryDirectory();
      final idpel = widget.pelangganData['idpel'] ?? 'BMnet';
      final fileName = isLunas ? "Bukti_Pelunasan_$idpel.pdf" : "Nota_Tagihan_$idpel.pdf";
      final file = File("${outputDir.path}/$fileName");
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: isLunas 
            ? "Halo Kak ${widget.pelangganData['nama']}, Berikut kami kirimkan Bukti Pelunasan Resmi BMnet ISP format PDF." 
            : "Halo Kak ${widget.pelangganData['nama']}, Berikut kami kirimkan Nota Tagihan Internet BMnet ISP format PDF.",
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat/membagikan PDF: $e')),
      );
    }
  }

  Future<void> printPdfDocument(bool isLunas) async {
    final pdfDoc = await _buildPdfDocument(isLunas);
    final idpel = widget.pelangganData['idpel'] ?? 'BMnet';
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfDoc.save(),
      name: isLunas ? 'Kwitansi_BMnet_$idpel.pdf' : 'Nota_BMnet_$idpel.pdf',
    );
  }

  void cetakStrukBluetoothPOS() async {
    List<BluetoothInfo> devices = [];
    try {
      devices = await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      // ignore
    }

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada perangkat Bluetooth printer yang terpasang!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pilih Printer Bluetooth'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(devices[index].name),
                  subtitle: Text(devices[index].macAdress),
                  onTap: () async {
                    Navigator.pop(context);
                    bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: devices[index].macAdress);
                    if (connected) {
                      bool isConnected = await PrintBluetoothThermal.connectionStatus;
                      if (isConnected) {
                        String struk = "          BMNET ISP BILLING\n"
                            "       BUKTI PEMBAYARAN RESMI\n"
                            "================================\n"
                            "ID Pel : ${widget.pelangganData['idpel']}\n"
                            "Nama   : ${widget.pelangganData['nama']}\n"
                            "Paket  : ${widget.pelangganData['paket']}\n"
                            "Bulan  : ${widget.pelangganData['jumlah_bulan_tunggakan']} Bulan\n"
                            "Total  : Rp ${widget.pelangganData['total_tunggakan']}\n"
                            "       (Termasuk PPN 11%)\n"
                            "Metode : ${widget.pelangganData['metode_pembayaran']}\n"
                            "Kasir  : ${widget.pelangganData['diterima_oleh']}\n"
                            "Status : ${widget.pelangganData['status']}\n"
                            "================================\n"
                            "   Terima Kasih Telah Membayar\n"
                            "     Simpan Struk Ini Sebagai\n"
                            "       Bukti Sah Pembayaran\n\n\n";
                        await PrintBluetoothThermal.writeBytes(utf8.encode(struk));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Struk thermal berhasil dicetak!')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Gagal terhubung ke printer!')),
                      );
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showPaymentDialog() {
    String selectedMetode = 'Tunai';
    final TextEditingController penerimaController = TextEditingController();
    final TextEditingController bulanController = TextEditingController(text: widget.pelangganData['jumlah_bulan_tunggakan']?.toString() ?? '1');
    final TextEditingController totalTunggakanController = TextEditingController();
    final TextEditingController bayarController = TextEditingController();

    int hargaPaket = int.tryParse(widget.pelangganData['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
    int initialBulan = int.tryParse(bulanController.text) ?? 1;
    
    int calculatedTotal = (hargaPaket * initialBulan * 1.11).round();
    totalTunggakanController.text = calculatedTotal.toString();
    bayarController.text = calculatedTotal.toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kelola Pembayaran & Tunggakan (+ PPN 11%)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: bulanController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Jumlah Bulan Tunggakan'),
                      onChanged: (val) {
                        int bulan = int.tryParse(val) ?? 1;
                        int total = (bulan * hargaPaket * 1.11).round();
                        setDialogState(() {
                          totalTunggakanController.text = total.toString();
                          bayarController.text = total.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: totalTunggakanController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Total Nominal Tunggakan (Rp incl. PPN 11%)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bayarController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah yang Dibayar Sekarang (Rp)',
                        hintText: 'Misal: bayar lunas / sebagian',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                      value: selectedMetode,
                      items: ['Tunai', 'QRIS', 'Transfer Bank', 'DANA', 'GoPay', 'ShopeePay'].map((metode) {
                        return DropdownMenuItem(value: metode, child: Text(metode));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedMetode = val.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 15),

                    if (selectedMetode == 'QRIS') ...[
                      const Center(
                        child: Text(
                          'Scan QRIS di bawah ini:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          height: 160,
                          width: 160,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/images/qris.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text(
                                      'File QRIS tidak ditemukan di assets/images/qris.png',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red, fontSize: 11),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ] else if (selectedMetode == 'Transfer Bank') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Informasi Rekening Bank:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                            SizedBox(height: 5),
                            Text('• Bank Asal: BCA'),
                            Text('• No Rekening: 1234567890'),
                            Text('• Atas Nama: PT BMnet Mandiri'),
                          ],
                        ),
                      ),
                    ] else if (selectedMetode == 'DANA' || selectedMetode == 'GoPay' || selectedMetode == 'ShopeePay') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Informasi E-Wallet ($selectedMetode):', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            const SizedBox(height: 5),
                            Text('• Akun / No HP: 0812-3456-7890'),
                            Text('• Atas Nama: BMnet Billing ($selectedMetode)'),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    TextField(
                      controller: penerimaController,
                      decoration: const InputDecoration(
                        labelText: 'Diterima Oleh (Nama Petugas/Kasir)',
                        hintText: 'Contoh: Admin / Budi',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    int totalTunggakan = int.tryParse(totalTunggakanController.text) ?? 0;
                    int jumlahBayar = int.tryParse(bayarController.text) ?? 0;
                    int sisa = totalTunggakan - jumlahBayar;
                    if (sisa < 0) sisa = 0;

                    String statusBaru = (sisa == 0) ? 'Lunas' : 'Belum Lunas';

                    Navigator.pop(context);
                    updateStatusData({
                      "action": "update_status",
                      "idpel": widget.pelangganData['idpel']?.toString(),
                      "nama": widget.pelangganData['nama']?.toString(),
                      "status": statusBaru,
                      "metode_pembayaran": selectedMetode,
                      "diterima_oleh": penerimaController.text.isEmpty ? 'Admin' : penerimaController.text,
                      "jumlah_bulan_tunggakan": bulanController.text,
                      "total_tunggakan": totalTunggakan.toString(),
                      "sisa_tunggakan": sisa.toString(),
                    });
                  },
                  child: const Text('Simpan Pembayaran'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (widget.pelangganData['status'] ?? 'Belum Lunas').toString();
    final isLunas = status.toLowerCase() == 'lunas';

    return Scaffold(
      appBar: AppBar(
        title: Text((widget.pelangganData['nama'] ?? 'Detail Pelanggan').toString()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditPelangganPage(pelangganData: widget.pelangganData),
                ),
              );
              if (updated == true) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Status Pembayaran:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isLunas ? Colors.green.shade100 : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: isLunas ? Colors.green.shade800 : Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 25),
                    _buildRow('ID Pelanggan', widget.pelangganData['idpel']?.toString() ?? '-'),
                    _buildRow('Nama', widget.pelangganData['nama']?.toString() ?? '-'),
                    _buildRow('Paket Internet', widget.pelangganData['paket']?.toString() ?? '-'),
                    _buildRow('Harga Paket', widget.pelangganData['harga']?.toString() ?? '-'),
                    _buildRow('Bulan Tunggakan', '${widget.pelangganData['jumlah_bulan_tunggakan'] ?? '1'} Bulan'),
                    _buildRow('Total Tagihan', 'Rp ${widget.pelangganData['total_tunggakan'] ?? '0'} (Incl. PPN 11%)'),
                    _buildRow('Sisa Tunggakan', 'Rp ${widget.pelangganData['sisa_tunggakan'] ?? '0'}'),
                    _buildRow('Metode Bayar', widget.pelangganData['metode_pembayaran']?.toString() ?? '-'),
                    _buildRow('Diterima Oleh', widget.pelangganData['diterima_oleh']?.toString() ?? '-'),
                    _buildRow('Alamat', widget.pelangganData['alamat']?.toString() ?? '-'),
                    _buildRow('No WhatsApp', widget.pelangganData['no_hp']?.toString() ?? '-'),
                    _buildRow('No KTP / NIK', widget.pelangganData['nik']?.toString() ?? '-'),
                    _buildRow('Jatuh Tempo', widget.pelangganData['jatuh_tempo']?.toString() ?? 'Tanggal 5'),
                    _buildRow('Sales', widget.pelangganData['sales']?.toString() ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    onPressed: () => sharePdfToWhatsApp(isLunas),
                    icon: const Icon(Icons.share),
                    label: const Text('Kirim WA (PDF)'),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    onPressed: () => printPdfDocument(isLunas),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Cetak PDF'),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                    onPressed: cetakStrukBluetoothPOS,
                    icon: const Icon(Icons.print),
                    label: const Text('Struk POS'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            isUpdating
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLunas ? Colors.orange : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      if (isLunas) {
                        int hrg = int.tryParse(widget.pelangganData['harga']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '100000') ?? 100000;
                        int defaultTotal = (hrg * 1.11).round();
                        updateStatusData({
                          "action": "update_status",
                          "idpel": widget.pelangganData['idpel']?.toString(),
                          "nama": widget.pelangganData['nama']?.toString(),
                          "status": "Belum Lunas",
                          "metode_pembayaran": "-",
                          "diterima_oleh": "-",
                          "jumlah_bulan_tunggakan": "1",
                          "total_tunggakan": defaultTotal.toString(),
                          "sisa_tunggakan": "0",
                        });
                      } else {
                        _showPaymentDialog();
                      }
                    },
                    icon: Icon(isLunas ? Icons.warning : Icons.payment),
                    label: Text(isLunas ? 'Batalkan Lunas / Reset' : 'Bayar / Catat Tunggakan'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= HALAMAN EDIT PELANGGAN =================
class EditPelangganPage extends StatefulWidget {
  final Map<String, dynamic> pelangganData;

  const EditPelangganPage({super.key, required this.pelangganData});

  @override
  State<EditPelangganPage> createState() => _EditPelangganPageState();
}

class _EditPelangganPageState extends State<EditPelangganPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _idpelController;
  late TextEditingController _namaController;
  late TextEditingController _alamatController;
  late TextEditingController _hpController;
  late TextEditingController _nikController;
  late TextEditingController _salesController;
  late TextEditingController _bulanController;

  var daftarPaket = [
    {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
    {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
    {'nama': 'Paket Building (Free Android TV)', 'harga': 'Rp 121.622'},
    {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
    {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
    {'nama': '50 Mbps', 'harga': 'Rp 500.000'},
  ];

  Map<String, dynamic>? selectedPaket;
  late String selectedJatuhTempo;
  bool isSaving = false;

  final List<String> daftarJatuhTempo = ['Tanggal 5', 'Tanggal 10', 'Tanggal 15', 'Tanggal 20', 'Tanggal 25'];

  @override
  void initState() {
    super.initState();
    _idpelController = TextEditingController(text: widget.pelangganData['idpel']?.toString() ?? '');
    _namaController = TextEditingController(text: widget.pelangganData['nama']?.toString() ?? '');
    _alamatController = TextEditingController(text: widget.pelangganData['alamat']?.toString() ?? '');
    _hpController = TextEditingController(text: widget.pelangganData['no_hp']?.toString() ?? '');
    _nikController = TextEditingController(text: widget.pelangganData['nik']?.toString() ?? '');
    _salesController = TextEditingController(text: widget.pelangganData['sales']?.toString() ?? '');
    _bulanController = TextEditingController(text: widget.pelangganData['jumlah_bulan_tunggakan']?.toString() ?? '1');

    selectedJatuhTempo = widget.pelangganData['jatuh_tempo']?.toString() ?? 'Tanggal 5';
    if (!daftarJatuhTempo.contains(selectedJatuhTempo)) {
      selectedJatuhTempo = 'Tanggal 5';
    }

    final currentPaketNama = widget.pelangganData['paket']?.toString();
    try {
      selectedPaket = daftarPaket.firstWhere((p) => p['nama'] == currentPaketNama);
    } catch (_) {
      selectedPaket = daftarPaket.first;
    }
  }

  Future<void> updatePelanggan() async {
    if (!_formKey.currentState!.validate() || selectedPaket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi form dengan benar!')),
      );
      return;
    }

    setState(() => isSaving = true);

    int hargaInt = int.tryParse(selectedPaket!['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
    int bulanInt = int.tryParse(_bulanController.text) ?? 1;
    int totalTunggakan = (hargaInt * bulanInt * 1.11).round();

    final payload = {
      "action": "update_pelanggan",
      "old_idpel": widget.pelangganData['idpel']?.toString(),
      "idpel": _idpelController.text,
      "nama": _namaController.text,
      "alamat": _alamatController.text,
      "paket": selectedPaket!['nama'],
      "harga": selectedPaket!['harga'],
      "no_hp": _hpController.text,
      "nik": _nikController.text,
      "jatuh_tempo": selectedJatuhTempo,
      "sales": _salesController.text,
      "jumlah_bulan_tunggakan": _bulanController.text,
      "total_tunggakan": totalTunggakan.toString(),
      "sisa_tunggakan": totalTunggakan.toString(),
    };

    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        widget.pelangganData['idpel'] = _idpelController.text;
        widget.pelangganData['nama'] = _namaController.text;
        widget.pelangganData['alamat'] = _alamatController.text;
        widget.pelangganData['paket'] = selectedPaket!['nama'];
        widget.pelangganData['harga'] = selectedPaket!['harga'];
        widget.pelangganData['no_hp'] = _hpController.text;
        widget.pelangganData['nik'] = _nikController.text;
        widget.pelangganData['jatuh_tempo'] = selectedJatuhTempo;
        widget.pelangganData['sales'] = _salesController.text;
        widget.pelangganData['jumlah_bulan_tunggakan'] = _bulanController.text;
        widget.pelangganData['total_tunggakan'] = totalTunggakan.toString();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data pelanggan & IDPEL berhasil diperbarui!')),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Gagal memperbarui data ke server');
      }
    } catch (e) {
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Data Pelanggan')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _idpelController,
                decoration: const InputDecoration(labelText: 'ID Pelanggan (IDPEL)'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _namaController,
                decoration: const InputDecoration(labelText: 'Nama Pelanggan'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _alamatController,
                decoration: const InputDecoration(labelText: 'Alamat'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                value: selectedPaket,
                items: daftarPaket.map((paket) {
                  return DropdownMenuItem(
                    value: paket,
                    child: Text('${paket['nama']} (${paket['harga']} + PPN)'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedPaket = val as Map<String, dynamic>?;
                  });
                },
                validator: (val) => val == null ? 'Pilih paket' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _bulanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah Bulan Tagihan / Tunggakan'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Tanggal Jatuh Tempo'),
                value: selectedJatuhTempo,
                items: daftarJatuhTempo.map((tgl) {
                  return DropdownMenuItem(value: tgl, child: Text(tgl));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedJatuhTempo = val.toString();
                  });
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _hpController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No WhatsApp'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nikController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'No KTP / NIK'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _salesController,
                decoration: const InputDecoration(labelText: 'Nama Sales (Opsional)'),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: isSaving ? null : updatePelanggan,
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan Perubahan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= HALAMAN TAMBAH PELANGGAN =================
class TambahPelangganPage extends StatefulWidget {
  const TambahPelangganPage({super.key});

  @override
  State<TambahPelangganPage> createState() => _TambahPelangganPageState();
}

class _TambahPelangganPageState extends State<TambahPelangganPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _idpelController = TextEditingController();
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _alamatController = TextEditingController();
  final TextEditingController _hpController = TextEditingController();
  final TextEditingController _nikController = TextEditingController();
  final TextEditingController _salesController = TextEditingController();
  final TextEditingController _bulanController = TextEditingController(text: '1');

  var daftarPaket = [
    {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
    {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
    {'nama': 'Paket Building (Free Android TV)', 'harga': 'Rp 121.622'},
    {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
    {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
    {'nama': '50 Mbps', 'harga': 'Rp 500.000'},
  ];

  Map<String, dynamic>? selectedPaket;
  String selectedJatuhTempo = 'Tanggal 5';
  String selectedStatus = 'Belum Lunas';
  bool isSaving = false;

  final List<String> daftarJatuhTempo = ['Tanggal 5', 'Tanggal 10', 'Tanggal 15', 'Tanggal 20', 'Tanggal 25'];
  final List<String> daftarStatus = ['Belum Lunas', 'Lunas'];

  Future<void> simpanPelanggan() async {
    if (!_formKey.currentState!.validate() || selectedPaket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi form dan pilih paket internet!')),
      );
      return;
    }

    setState(() => isSaving = true);

    int hargaInt = int.tryParse(selectedPaket!['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
    int bulanInt = int.tryParse(_bulanController.text) ?? 1;
    int totalTunggakan = (hargaInt * bulanInt * 1.11).round();

    final payload = {
      "idpel": _idpelController.text,
      "nama": _namaController.text,
      "alamat": _alamatController.text,
      "paket": selectedPaket!['nama'],
      "harga": selectedPaket!['harga'],
      "no_hp": _hpController.text,
      "nik": _nikController.text,
      "jatuh_tempo": selectedJatuhTempo,
      "status": selectedStatus,
      "sales": _salesController.text,
      "jumlah_bulan_tunggakan": _bulanController.text,
      "total_tunggakan": totalTunggakan.toString(),
      "sisa_tunggakan": totalTunggakan.toString(),
    };

    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        Navigator.pop(context, true);
      } else {
        throw Exception('Gagal menyimpan ke server');
      }
    } catch (e) {
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Pelanggan Baru')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _idpelController,
                decoration: const InputDecoration(labelText: 'ID Pelanggan (Opsional, kosongkan untuk auto BM00x)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _namaController,
                decoration: const InputDecoration(labelText: 'Nama Pelanggan'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _alamatController,
                decoration: const InputDecoration(labelText: 'Alamat'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaket.map((paket) {
                  return DropdownMenuItem(
                    value: paket,
                    child: Text('${paket['nama']} (${paket['harga']} + PPN)'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedPaket = val as Map<String, dynamic>?;
                  });
                },
                validator: (val) => val == null ? 'Pilih paket' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _bulanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah Bulan Tagihan Awal'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Tanggal Jatuh Tempo'),
                value: selectedJatuhTempo,
                items: daftarJatuhTempo.map((tgl) {
                  return DropdownMenuItem(value: tgl, child: Text(tgl));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedJatuhTempo = val.toString();
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Status Pembayaran Awal'),
                value: selectedStatus,
                items: daftarStatus.map((st) {
                  return DropdownMenuItem(value: st, child: Text(st));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedStatus = val.toString();
                  });
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _hpController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No WhatsApp'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nikController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'No KTP / NIK'),
                validator: (val) => val == null || val.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _salesController,
                decoration: const InputDecoration(labelText: 'Nama Sales (Opsional)'),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: isSaving ? null : simpanPelanggan,
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan Pelanggan ke Spreadsheet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
