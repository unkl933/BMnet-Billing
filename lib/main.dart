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
      BillingHomePage(pelanggan: pelangganData, stok: stokData, isLoading: isLoading, onRefresh: fetchData),
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

// ================= HALAMAN PELANGGAN =================
class BillingHomePage extends StatelessWidget {
  final List pelanggan;
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const BillingHomePage({super.key, required this.pelanggan, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pelanggan (${pelanggan.length})'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh)]),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: pelanggan.length,
              itemBuilder: (context, index) {
                final item = pelanggan[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(item['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('ID: ${item['idpel']} | Paket: ${item['paket']}\nTeknisi: ${item['teknisi'] ?? '-'}'),
                    isThreeLine: true,
                    trailing: Text(item['status'] ?? 'Belum Lunas', style: TextStyle(color: (item['status'] == 'Lunas') ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => TambahPelangganPage(stokList: stok)),
          );
          if (result == true) onRefresh();
        },
      ),
    );
  }
}

// ================= HALAMAN TAMBAH PELANGGAN + PEMAKAIAN MATERIAL & TEKNISI =================
class TambahPelangganPage extends StatefulWidget {
  final List stokList;
  const TambahPelangganPage({super.key, required this.stokList});

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
  final TextEditingController _teknisiController = TextEditingController();
  
  // Input pemakaian material
  final TextEditingController _dropcoreController = TextEditingController(text: '0');
  final TextEditingController _patchcoreController = TextEditingController(text: '0');
  
  String? selectedOnt;
  String selectedJatuhTempo = 'Tanggal 5';
  bool isSaving = false;

  var daftarPaket = [
    {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
    {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
    {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
    {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
  ];

  Map<String, dynamic>? selectedPaket;

  @override
  Widget build(BuildContext context) {
    // Filter stok yang kategorinya ONT untuk dipilih saat instalasi
    List ontList = widget.stokList.where((s) => (s['kategori'] ?? '').toString().toLowerCase().contains('ont')).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Pelanggan & Pasang Baru')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text('Data Pelanggan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 16)),
              const Divider(),
              TextFormField(controller: _idpelController, decoration: const InputDecoration(labelText: 'ID Pelanggan (Opsional / Otomatis)')),
              TextFormField(controller: _namaController, decoration: const InputDecoration(labelText: 'Nama Lengkap'), validator: (val) => val!.isEmpty ? 'Wajib diisi' : null),
              TextFormField(controller: _alamatController, decoration: const InputDecoration(labelText: 'Alamat Pemasangan'), validator: (val) => val!.isEmpty ? 'Wajib diisi' : null),
              TextFormField(controller: _hpController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'No WhatsApp')),
              
              const SizedBox(height: 15),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaket.map((p) => DropdownMenuItem(value: p, child: Text('${p['nama']} (${p['harga']} + PPN)'))).toList(),
                onChanged: (val) => setState(() => selectedPaket = val as Map<String, dynamic>?),
              ),

              const SizedBox(height: 20),
              const Text('Instalasi & Teknisi Lapangan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 16)),
              const Divider(),
              TextFormField(controller: _teknisiController, decoration: const InputDecoration(labelText: 'Nama Teknisi yang Bertugas (Cth: Budi / Joko)')),
              
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Pilih Perangkat ONT yang Dipasang'),
                value: selectedOnt,
                items: ontList.isEmpty 
                    ? [const DropdownMenuItem(value: null, child: Text('Stok ONT Kosong'))]
                    : ontList.map((o) => DropdownMenuItem<String>(value: o['nama_barang'].toString(), child: Text('${o['nama_barang']} (Sisa: ${o['jumlah']})'))).toList(),
                onChanged: (val) => setState(() => selectedOnt = val),
              ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _dropcoreController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Kabel Dropcore (Meter)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _patchcoreController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Patchcore (Pcs)'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                onPressed: isSaving ? null : () async {
                  if (!_formKey.currentState!.validate() || selectedPaket == null) return;
                  setState(() => isSaving = true);

                  int hargaInt = int.tryParse(selectedPaket!['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
                  int totalTunggakan = (hargaInt * 1.11).round();

                  // Menyusun daftar material yang terpakai untuk mengurangi stok
                  List> materialPakai = [];
                  if (selectedOnt != null) {
                    materialPakai.add({"nama": selectedOnt, "qty": 1});
                  }
                  double dropcoreVal = double.tryParse(_dropcoreController.text) ?? 0;
                  if (dropcoreVal > 0) {
                    materialPakai.add({"nama": "Kabel FO Dropcore", "qty": dropcoreVal});
                  }
                  int patchcoreVal = int.tryParse(_patchcoreController.text) ?? 0;
                  if (patchcoreVal > 0) {
                    materialPakai.add({"nama": "Patchcord / Pigtail", "qty": patchcoreVal});
                  }

                  String materialStr = "ONT: ${selectedOnt ?? '-'}, Dropcore: ${_dropcoreController.text}m, Patchcore: ${_patchcoreController.text}pcs";

                  final payload = {
                    "idpel": _idpelController.text,
                    "nama": _namaController.text,
                    "alamat": _alamatController.text,
                    "paket": selectedPaket!['nama'],
                    "harga": selectedPaket!['harga'],
                    "no_hp": _hpController.text,
                    "nik": _nikController.text,
                    "jatuh_tempo": selectedJatuhTempo,
                    "status": "Belum Lunas",
                    "sales": _salesController.text,
                    "teknisi": _teknisiController.text.isEmpty ? "Tim Teknisi" : _teknisiController.text,
                    "material_terpakai": materialStr,
                    "jumlah_bulan_tunggakan": "1",
                    "total_tunggakan": totalTunggakan.toString(),
                    "sisa_tunggakan": totalTunggakan.toString(),
                    "pemakaian_material": materialPakai,
                  };

                  try {
                    final response = await http.post(
                      Uri.parse(scriptUrl),
                      headers: {"Content-Type": "application/json"},
                      body: json.encode(payload),
                    );
                    if (response.statusCode == 200 || response.statusCode == 302) {
                      Navigator.pop(context, true);
                    }
                  } catch (e) {
                    setState(() => isSaving = false);
                  }
                },
                icon: const Icon(Icons.save),
                label: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Simpan Pelanggan & Potong Stok', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= HALAMAN LAINNYA =================
class PengeluaranPage extends StatelessWidget {
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const PengeluaranPage({super.key, required this.pengeluaran, required this.isLoading, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Pengeluaran')));
}

class StokBarangPage extends StatelessWidget {
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const StokBarangPage({super.key, required this.stok, required this.isLoading, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Stok Barang')));
}

class DashboardKeuanganPage extends StatelessWidget {
  final List pelanggan;
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const DashboardKeuanganPage({super.key, required this.pelanggan, required this.pengeluaran, required this.isLoading, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Keuangan')));
}
