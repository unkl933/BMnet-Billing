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
            stokData = decoded['stok'] ?? [];
          }
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      BillingHomePage(pelanggan: pelangganData, isLoading: isLoading, onRefresh: fetchData),
      PengeluaranPage(pengeluaran: pengeluaranData, isLoading: isLoading, onRefresh: fetchData),
      StokBarangPage(stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      DashboardKeuanganPage(pelanggan: pelangganData, pengeluaran: pengeluaranData, isLoading: isLoading, onRefresh: fetchData),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Pelanggan'),
          BottomNavigationBarItem(icon: Icon(Icons.money_off), label: 'Pengeluaran'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Stok'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_customize), label: 'Keuangan'),
        ],
      ),
    );
  }
}

// ================= HALAMAN PENGELUARAN DENGAN INTEGRASI STOK =================
class PengeluaranPage extends StatefulWidget {
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PengeluaranPage({super.key, required this.pengeluaran, required this.isLoading, required this.onRefresh});

  @override
  State<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends State<PengeluaranPage> {
  void _showTambahPengeluaranDialog(BuildContext context) {
    final TextEditingController keteranganController = TextEditingController();
    final TextEditingController nominalController = TextEditingController();
    final TextEditingController jumlahStokController = TextEditingController(text: '1');
    final TextEditingController satuanStokController = TextEditingController(text: 'Pcs');
    String selectedKategori = 'Operasional';

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
            bool isBelanjaAset = selectedKategori == 'Belanja Aset';

            return AlertDialog(
              title: const Text('Tambah Pengeluaran'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      value: selectedKategori,
                      items: kategoriList.map((kat) => DropdownMenuItem(value: kat, child: Text(kat))).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedKategori = val.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keteranganController,
                      decoration: InputDecoration(
                        labelText: isBelanjaAset ? 'Nama Perangkat / Barang Aset' : 'Keterangan Keperluan',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nominalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Total Biaya (Rp)'),
                    ),
                    
                    // JIKA BELANJA ASET, MUNCULKAN INPUT JUMLAH STOK
                    if (isBelanjaAset) ...[
                      const SizedBox(height: 15),
                      const Divider(),
                      const Text('Otomatis Masuk ke Stok Barang:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: jumlahStokController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Jumlah Stok'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: satuanStokController,
                              decoration: const InputDecoration(labelText: 'Satuan'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () async {
                    if (nominalController.text.isEmpty || keteranganController.text.isEmpty) return;
                    
                    final payload = {
                      "action": "tambah_pengeluaran",
                      "kategori": selectedKategori,
                      "keterangan": keteranganController.text,
                      "nominal": nominalController.text,
                      "jumlah_stok": jumlahStokController.text,
                      "satuan_stok": satuanStokController.text,
                      "tanggal": DateTime.now().toString().split(' ')[0],
                    };

                    Navigator.pop(context);
                    try {
                      final response = await http.post(
                        Uri.parse(scriptUrl),
                        headers: {"Content-Type": "application/json"},
                        body: json.encode(payload),
                      );
                      if (response.statusCode == 200 || response.statusCode == 302) {
                        widget.onRefresh();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pengeluaran & Stok berhasil dicatat!')),
                        );
                      }
                    } catch (e) {
                      // ignore
                    }
                  },
                  child: const Text('Simpan'),
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
      appBar: AppBar(title: Text('Pengeluaran (${widget.pengeluaran.length})'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onRefresh)]),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.pengeluaran.isEmpty
              ? const Center(child: Text('Belum ada data pengeluaran.'))
              : ListView.builder(
                  itemCount: widget.pengeluaran.length,
                  itemBuilder: (context, index) {
                    final item = widget.pengeluaran[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.money_off, color: Colors.red),
                        title: Text(item['keterangan'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Kategori: ${item['kategori'] ?? '-'}\nTgl: ${item['tanggal'] ?? '-'}'),
                        trailing: Text('Rp ${item['nominal'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showTambahPengeluaranDialog(context), child: const Icon(Icons.add)),
    );
  }
}

// ================= HALAMAN STOK BARANG =================
class StokBarangPage extends StatelessWidget {
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const StokBarangPage({super.key, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stok Barang Jaringan (${stok.length})'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh)]),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : stok.isEmpty
              ? const Center(child: Text('Belum ada stok barang.'))
              : ListView.builder(
                  itemCount: stok.length,
                  itemBuilder: (context, index) {
                    final item = stok[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.router, color: Colors.indigo),
                        title: Text(item['nama_barang'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Kategori: ${item['kategori'] ?? '-'}'),
                        trailing: Text('${item['jumlah'] ?? '0'} ${item['satuan'] ?? 'Pcs'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ),
                    );
                  },
                ),
    );
  }
}

// ================= HALAMAN LAINNYA (Pelanggan & Keuangan) =================
class BillingHomePage extends StatelessWidget {
  final List pelanggan;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const BillingHomePage({super.key, required this.pelanggan, required this.isLoading, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Pelanggan (${pelanggan.length})')), body: const Center(child: Text('Menu Pelanggan')));
}

class DashboardKeuanganPage extends StatelessWidget {
  final List pelanggan;
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const DashboardKeuanganPage({super.key, required this.pelanggan, required this.pengeluaran, required this.isLoading, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Keuangan')), body: const Center(child: Text('Dashboard Keuangan')));
}
