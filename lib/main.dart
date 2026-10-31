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

// ================= NAVIGASI UTAMA =================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  List pelangganData = [];
  List pengeluaranData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(scriptUrl));
      if (response.statusCode == 200 || response.statusCode == 302) {
        final decoded = json.decode(response.body);
        setState(() {
          if (decoded is Map) {
            pelangganData = decoded['pelanggan'] ?? [];
            pengeluaranData = decoded['pengeluaran'] ?? [];
          } else if (decoded is List) {
            pelangganData = decoded;
            pengeluaranData = [];
          }
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
        onRefresh: fetchData,
      ),
      PengeluaranPage(
        pengeluaran: pengeluaranData,
        isLoading: isLoading,
        onRefresh: fetchData,
      ),
      DashboardKeuanganPage(
        pelanggan: pelangganData,
        pengeluaran: pengeluaranData,
        isLoading: isLoading,
        onRefresh: fetchData,
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
            icon: Icon(Icons.money_off),
            label: 'Pengeluaran',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize),
            label: 'Laporan & Keuangan',
          ),
        ],
      ),
    );
  }
}

// ================= HALAMAN PENGELUARAN (FIXED STATE & FORM) =================
class PengeluaranPage extends StatefulWidget {
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PengeluaranPage({
    super.key,
    required this.pengeluaran,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends State<PengeluaranPage> {
  void _showTambahPengeluaranDialog(BuildContext context) {
    final TextEditingController keteranganController = TextEditingController();
    final TextEditingController nominalController = TextEditingController();
    String selectedKategori = 'Operasional';
    bool isSaving = false;

    final List<String> kategoriList = [
      'Belanja Aset',
      'Operasional',
      'Gaji Karyawan',
      'Hutang',
      'Donasi Sosial',
      'Maintenance / Pemeliharaan'
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Catatan Pengeluaran'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Kategori Pengeluaran'),
                      value: selectedKategori,
                      items: kategoriList.map((kat) {
                        return DropdownMenuItem(value: kat, child: Text(kat));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedKategori = val.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keteranganController,
                      decoration: const InputDecoration(labelText: 'Keterangan / Keperluan'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nominalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (nominalController.text.isEmpty || keteranganController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lengkapi form pengeluaran terlebih dahulu!')),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          final todayStr = DateTime.now().toString().split(' ')[0];
                          final payload = {
                            "action": "tambah_pengeluaran",
                            "kategori": selectedKategori,
                            "keterangan": keteranganController.text,
                            "nominal": nominalController.text,
                            "tanggal": todayStr,
                          };

                          try {
                            final response = await http.post(
                              Uri.parse(scriptUrl),
                              headers: {"Content-Type": "application/json"},
                              body: json.encode(payload),
                            );

                            if (response.statusCode == 200 || response.statusCode == 302) {
                              Navigator.pop(context);
                              await widget.onRefresh(); // Refresh data dari server
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Pengeluaran berhasil dicatat!')),
                                );
                              }
                            } else {
                              throw Exception('Respon server gagal');
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal menyimpan pengeluaran: $e')),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Simpan'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Pengeluaran (${widget.pengeluaran.length} Catatan)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.onRefresh,
          ),
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.pengeluaran.isEmpty
              ? const Center(child: Text('Belum ada data pengeluaran tercatat.'))
              : ListView.builder(
                  itemCount: widget.pengeluaran.length,
                  itemBuilder: (context, index) {
                    final item = widget.pengeluaran[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.redAccent,
                          child: Icon(Icons.money_off, color: Colors.white),
                        ),
                        title: Text(
                          item['keterangan']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Kategori: ${item['kategori'] ?? '-'}\nTanggal: ${item['tanggal'] ?? '-'}'),
                        isThreeLine: true,
                        trailing: Text(
                          'Rp ${item['nominal'] ?? '0'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTambahPengeluaranDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ================= DASHBOARD KEUANGAN =================
class DashboardKeuanganPage extends StatefulWidget {
  final List pelanggan;
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const DashboardKeuanganPage({
    super.key,
    required this.pelanggan,
    required this.pengeluaran,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<DashboardKeuanganPage> createState() => _DashboardKeuanganPageState();
}

class _DashboardKeuanganPageState extends State<DashboardKeuanganPage> {
  String selectedPeriode = 'Bulanan';

  int _parseNominal(dynamic val) {
    if (val == null) return 0;
    String str = val.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(str) ?? 0;
  }

  Future<void> _cetakLaporanPdf() async {
    final pdf = pw.Document();
    int totalLunas = 0;
    int totalTunggakan = 0;
    int totalPengeluaran = 0;

    Map<String, int> rekapKategoriPengeluaran = {};

    for (var item in widget.pelanggan) {
      final status = (item['status'] ?? 'Belum Lunas').toString().toLowerCase();
      final total = _parseNominal(item['total_tunggakan']);
      if (status == 'lunas') {
        totalLunas += total;
      } else {
        totalTunggakan += total;
      }
    }

    for (var item in widget.pengeluaran) {
      final nominal = _parseNominal(item['nominal']);
      final kategori = (item['kategori'] ?? 'Operasional').toString();
      totalPengeluaran += nominal;
      rekapKategoriPengeluaran[kategori] = (rekapKategoriPengeluaran[kategori] ?? 0) + nominal;
    }

    final int dppLunas = (totalLunas / 1.11).round();
    final int ppnLunas = totalLunas - dppLunas;
    final int labaBersih = totalLunas - totalPengeluaran;

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
              pw.Text('BMnet ISP - LAPORAN KEUANGAN & LABA RUGI', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              pw.Text('Periode: $selectedPeriode (${now.year}) | Cetak: $tglCetak', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColors.blue800),
              pw.SizedBox(height: 10),

              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green300), color: PdfColors.green50),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('PEMASUKAN (LUNAS)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                          pw.Text('Rp $totalLunas', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                          pw.Text('PPN 11%: Rp $ppnLunas', style: const pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red300), color: PdfColors.red50),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TOTAL PENGELUARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                          pw.Text('Rp $totalPengeluaran', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),

              pw.Text('REKAP PENGELUARAN PER KATEGORI', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Kategori Pengeluaran', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Nominal', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...rekapKategoriPengeluaran.entries.map((e) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rp ${e.value}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Text('LABA / RUGI BERSIH: Rp $labaBersih', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Laporan_Keuangan_Pengeluaran_BMnet.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalPemasukanLunas = 0;
    int totalTunggakan = 0;
    int totalPengeluaran = 0;
    int totalPelangganLunas = 0;
    int totalPelangganBelumLunas = 0;

    Map<String, int> rekapKategoriPengeluaran = {};

    for (var item in widget.pelanggan) {
      final status = (item['status'] ?? 'Belum Lunas').toString().toLowerCase();
      final total = _parseNominal(item['total_tunggakan']);
      if (status == 'lunas') {
        totalPemasukanLunas += total;
        totalPelangganLunas++;
      } else {
        totalTunggakan += total;
        totalPelangganBelumLunas++;
      }
    }

    for (var item in widget.pengeluaran) {
      final nominal = _parseNominal(item['nominal']);
      final kategori = (item['kategori'] ?? 'Operasional').toString();
      totalPengeluaran += nominal;
      rekapKategoriPengeluaran[kategori] = (rekapKategoriPengeluaran[kategori] ?? 0) + nominal;
    }

    final int labaBersih = totalPemasukanLunas - totalPengeluaran;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard & Laporan Keuangan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.onRefresh,
          ),
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Periode Laporan:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ToggleButtons(
                        isSelected: [selectedPeriode == 'Bulanan', selectedPeriode == 'Tahunan'],
                        onPressed: (index) {
                          setState(() {
                            selectedPeriode = index == 0 ? 'Bulanan' : 'Tahunan';
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        constraints: const BoxConstraints(minHeight: 32, minWidth: 90),
                        children: const [
                          Text('Bulanan', style: TextStyle(fontSize: 12)),
                          Text('Tahunan', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _cetakLaporanPdf,
                    icon: const Icon(Icons.print),
                    label: Text('Cetak Laporan $selectedPeriode (PDF + Pengeluaran)', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 15),

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
                          'Total Pengeluaran',
                          'Rp $totalPengeluaran',
                          Colors.red.shade700,
                          Icons.money_off,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: labaBersih >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: labaBersih >= 0 ? Colors.green.shade200 : Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Perkiraan Laba / Rugi Bersih:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Rp $labaBersih', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: labaBersih >= 0 ? Colors.green.shade800 : Colors.red.shade800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rekap Pengeluaran per Kategori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Divider(),
                          rekapKategoriPengeluaran.isEmpty
                              ? const Text('Belum ada pengeluaran tercatat.')
                              : Column(
                                  children: rekapKategoriPengeluaran.entries.map((e) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                                          Text('Rp ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
              Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

// ================= HALAMAN DAFTAR PELANGGAN / EDIT / DETAIL =================
class DetailPelangganPage extends StatefulWidget {
  final Map<String, dynamic> pelangganData;
  const DetailPelangganPage({super.key, required this.pelangganData});
  @override
  State<DetailPelangganPage> createState() => _DetailPelangganPageState();
}

class _DetailPelangganPageState extends State<DetailPelangganPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pelangganData['nama'] ?? 'Detail')),
      body: Center(child: Text('Detail Pelanggan ID: ${widget.pelangganData['idpel']}')),
    );
  }
}

class EditPelangganPage extends StatefulWidget {
  final Map<String, dynamic> pelangganData;
  const EditPelangganPage({super.key, required this.pelangganData});
  @override
  State<EditPelangganPage> createState() => _EditPelangganPageState();
}
class _EditPelangganPageState extends State<EditPelangganPage> {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Edit')));
}

class TambahPelangganPage extends StatefulWidget {
  const TambahPelangganPage({super.key});
  @override
  State<TambahPelangganPage> createState() => _TambahPelangganPageState();
}
class _TambahPelangganPageState extends State<TambahPelangganPage> {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Tambah')));
}
