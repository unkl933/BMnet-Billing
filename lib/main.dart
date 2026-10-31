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

// ================= NAVIGASI UTAMA (4 TAB) =================
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

// ================= TAB 1: HALAMAN PELANGGAN =================
class BillingHomePage extends StatelessWidget {
  final List pelanggan;
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const BillingHomePage({super.key, required this.pelanggan, required this.stok, required this.isLoading, required this.onRefresh});

  void _showPelangganDetailDialog(BuildContext context, Map item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item['nama'] ?? 'Detail Pelanggan', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID Pelanggan : ${item['idpel'] ?? '-'}'),
              Text('Alamat       : ${item['alamat'] ?? '-'}'),
              Text('Paket        : ${item['paket'] ?? '-'} (${item['harga'] ?? '-'})'),
              Text('No HP/WA     : ${item['no_hp'] ?? '-'}'),
              Text('Teknisi      : ${item['teknisi'] ?? '-'}'),
              Text('Material     : ${item['material_terpakai'] ?? '-'}'),
              Text('SN ONT       : ${item['sn_ont'] ?? '-'}'),
              Text('Gangguan     : ${item['jenis_gangguan'] ?? '-'}'),
              Text('Bulan Tagih  : ${item['jumlah_bulan_tunggakan'] ?? '1'} Bulan'),
              const Divider(),
              Text('Status       : ${item['status'] ?? 'Belum Lunas'}', style: TextStyle(fontWeight: FontWeight.bold, color: (item['status'] == 'Lunas') ? Colors.green : Colors.red)),
              Text('Total Tagihan: Rp ${item['total_tunggakan'] ?? '0'}'),
              Text('Metode Bayar : ${item['metode_pembayaran'] ?? '-'}'),
            ],
          ),
        ),
        actions: [
          if ((item['status'] ?? '').toString().toLowerCase() != 'lunas')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _showBayarDialog(context, item);
              },
              icon: const Icon(Icons.payment, size: 16),
              label: const Text('Bayar'),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UpgradePelangganPage(pelangganItem: item, stokList: stok)),
              ).then((res) => { if (res == true) onRefresh() });
            },
            icon: const Icon(Icons.upgrade, size: 16),
            label: const Text('Upgrade & Perbaikan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showBayarDialog(BuildContext context, Map item) {
    String selectedMetode = 'Tunai';
    final List<String> metodeList = ['Tunai', 'Transfer Bank', 'QRIS', 'DANA', 'GoPay', 'ShopeePay', 'OVO'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Pelunasan: ${item['nama']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Tagihan (${item['jumlah_bulan_tunggakan'] ?? '1'} Bulan): Rp ${item['total_tunggakan']}'),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Pilih Metode Pembayaran'),
                      value: selectedMetode,
                      items: metodeList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (val) => setDialogState(() => selectedMetode = val.toString()),
                    ),
                    const SizedBox(height: 15),
                    if (selectedMetode == 'Transfer Bank') ...[
                      const ContainerInfoBayar(
                        judul: 'Informasi Transfer Bank BCA',
                        detail: 'Nama Bank : BCA\nNo Rek : 2801971611\nAtas Nama : Irsyam Aufar Zuhdan',
                      ),
                    ] else if (['DANA', 'GoPay', 'ShopeePay', 'OVO'].contains(selectedMetode)) ...[
                      ContainerInfoBayar(
                        judul: 'Informasi E-Wallet ($selectedMetode)',
                        detail: 'Layanan : $selectedMetode\nNo Tujuan : 083827777207\nAtas Nama : Irsyam Aufar Zuhdan',
                      ),
                    ] else if (selectedMetode == 'QRIS') ...[
                      const SizedBox(height: 10),
                      const Text('Scan QRIS di bawah ini:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      Center(
                        child: Image.asset(
                          'assets/images/qris.png',
                          height: 180,
                          width: 180,
                          errorBuilder: (context, error, stackTrace) => const Text(
                            'Gambar QRIS tidak ditemukan di assets/images/qris.png',
                            style: TextStyle(color: Colors.red, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Atas Nama: Irsyam Aufar Zuhdan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(context);
                    final payload = {
                      "action": "bayar_pelanggan",
                      "idpel": item['idpel'],
                      "metode_pembayaran": selectedMetode,
                      "total_tunggakan": item['total_tunggakan'],
                      "status": "Lunas"
                    };
                    try {
                      final response = await http.post(
                        Uri.parse(scriptUrl),
                        headers: {"Content-Type": "application/json"},
                        body: json.encode(payload),
                      );
                      if (response.statusCode == 200 || response.statusCode == 302) {
                        onRefresh();
                      }
                    } catch (e) {
                      // ignore
                    }
                  },
                  child: const Text('Konfirmasi Lunas'),
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
                    onTap: () => _showPelangganDetailDialog(context, item),
                    title: Text(item['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('ID: ${item['idpel']} | Paket: ${item['paket']}\nTagihan: ${item['jumlah_bulan_tunggakan'] ?? '1'} Bln (Rp ${item['total_tunggakan'] ?? '0'})\nStatus: ${item['status'] ?? 'Belum Lunas'}'),
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

class ContainerInfoBayar extends StatelessWidget {
  final String judul;
  final String detail;
  const ContainerInfoBayar({super.key, required this.judul, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13)),
          const SizedBox(height: 5),
          Text(detail, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ================= HALAMAN TAMBAH PELANGGAN & POTONG STOK =================
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
              DropdownButtonFormField>(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaket.map((p) => DropdownMenuItem>(value: p, child: Text('${p['nama']} (${p['harga']} + PPN)'))).toList(),
                onChanged: (val) => setState(() => selectedPaket = val),
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

                  List materialPakai = [];
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

// ================= HALAMAN UPGRADE DATA & PENANGANAN GANGGUAN =================
class UpgradePelangganPage extends StatefulWidget {
  final Map pelangganItem;
  final List stokList;
  const UpgradePelangganPage({super.key, required this.pelangganItem, required this.stokList});

  @override
  State<UpgradePelangganPage> createState() => _UpgradePelangganPageState();
}

class _UpgradePelangganPageState extends State<UpgradePelangganPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _namaController;
  late TextEditingController _alamatController;
  late TextEditingController _hpController;
  late TextEditingController _bulanController;
  late TextEditingController _snOntController;
  late TextEditingController _gangguanController;
  late TextEditingController _teknisiController;

  String selectedStatus = 'Belum Lunas';
  String? selectedOntBaru;
  bool isSaving = false;

  var daftarPaket = [
    {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
    {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
    {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
    {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
  ];

  Map<String, dynamic>? selectedPaketBaru;

  @override
  void initState() {
    super.initState();
    _namaController = TextEditingController(text: widget.pelangganItem['nama']);
    _alamatController = TextEditingController(text: widget.pelangganItem['alamat']);
    _hpController = TextEditingController(text: widget.pelangganItem['no_hp']);
    _bulanController = TextEditingController(text: widget.pelangganItem['jumlah_bulan_tunggakan']?.toString() ?? '1');
    _snOntController = TextEditingController(text: widget.pelangganItem['sn_ont'] ?? '');
    _gangguanController = TextEditingController(text: widget.pelangganItem['jenis_gangguan'] ?? '');
    _teknisiController = TextEditingController(text: widget.pelangganItem['teknisi'] ?? '');
    selectedStatus = widget.pelangganItem['status'] ?? 'Belum Lunas';
    
    var currentPaketName = widget.pelangganItem['paket'];
    for (var p in daftarPaket) {
      if (p['nama'] == currentPaketName) {
        selectedPaketBaru = p;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List ontList = widget.stokList.where((s) => (s['kategori'] ?? '').toString().toLowerCase().contains('ont')).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Upgrade & Perbaikan: ${widget.pelangganItem['nama']}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text('Informasi & Ganti Paket', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 15)),
              const Divider(),
              TextFormField(controller: _namaController, decoration: const InputDecoration(labelText: 'Nama Pelanggan')),
              TextFormField(controller: _alamatController, decoration: const InputDecoration(labelText: 'Alamat')),
              TextFormField(controller: _hpController, decoration: const InputDecoration(labelText: 'No WhatsApp')),
              
              const SizedBox(height: 15),
              DropdownButtonFormField>(
                decoration: const InputDecoration(labelText: 'Ganti Paket Internet (Upgrade/Downgrade)'),
                value: selectedPaketBaru,
                items: daftarPaket.map((p) => DropdownMenuItem>(value: p, child: Text('${p['nama']} (${p['harga']} + PPN)'))).toList(),
                onChanged: (val) => setState(() => selectedPaketBaru = val),
              ),

              TextFormField(
                controller: _bulanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah Bulan Tagihan'),
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Status Tagihan'),
                value: selectedStatus,
                items: ['Lunas', 'Belum Lunas'].map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => selectedStatus = val.toString()),
              ),

              const SizedBox(height: 25),
              const Text('Penanganan Gangguan & Perangkat', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent, fontSize: 15)),
              const Divider(),
              
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Penggantian ONT Baru (Opsional jika rusak)'),
                value: selectedOntBaru,
                items: ontList.isEmpty 
                    ? [const DropdownMenuItem<String>(value: null, child: Text('Stok ONT Kosong'))]
                    : ontList.map((o) => DropdownMenuItem<String>(value: o['nama_barang'].toString(), child: Text('${o['nama_barang']} (Sisa: ${o['jumlah']})'))).toList(),
                onChanged: (val) => setState(() => selectedOntBaru = val),
              ),

              TextFormField(
                controller: _snOntController,
                decoration: const InputDecoration(labelText: 'Serial Number (SN) ONT'),
              ),
              TextFormField(
                controller: _gangguanController,
                decoration: const InputDecoration(labelText: 'Jenis Gangguan yang Diperbaiki (Cth: Redaman Tinggi / Mati Total)'),
              ),
              TextFormField(
                controller: _teknisiController,
                decoration: const InputDecoration(labelText: 'Nama Teknisi yang Memperbaiki'),
              ),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: isSaving ? null : () async {
                  if (!_formKey.currentState!.validate() || selectedPaketBaru == null) return;
                  setState(() => isSaving = true);

                  int hargaInt = int.tryParse(selectedPaketBaru!['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
                  int jmlBulan = int.tryParse(_bulanController.text) ?? 1;
                  int totalTagihanBaru = (hargaInt * jmlBulan * 1.11).round();

                  List materialPakai = [];
                  if (selectedOntBaru != null) {
                    materialPakai.add({"nama": selectedOntBaru, "qty": 1});
                  }

                  final payload = {
                    "action": "upgrade_dan_perbaikan",
                    "idpel": widget.pelangganItem['idpel'],
                    "nama": _namaController.text,
                    "alamat": _alamatController.text,
                    "no_hp": _hpController.text,
                    "paket": selectedPaketBaru!['nama'],
                    "harga": selectedPaketBaru!['harga'],
                    "jumlah_bulan_tunggakan": jmlBulan.toString(),
                    "total_tunggakan": totalTagihanBaru.toString(),
                    "status": selectedStatus,
                    "sn_ont": _snOntController.text,
                    "jenis_gangguan": _gangguanController.text,
                    "teknisi": _teknisiController.text,
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
                label: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Simpan Upgrade & Perbaikan', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= TAB 2: HALAMAN PENGELUARAN =================
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
                      items: kategoriList.map((kat) => DropdownMenuItem<String>(value: kat, child: Text(kat))).toList(),
                      onChanged: (val) => setDialogState(() => selectedKategori = val.toString()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keteranganController,
                      decoration: InputDecoration(labelText: isBelanjaAset ? 'Nama Perangkat / Barang Aset' : 'Keterangan'),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: nominalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
                    
                    if (isBelanjaAset) ...[
                      const SizedBox(height: 15),
                      const Divider(),
                      const Text('Otomatis Masuk ke Stok Barang:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(flex: 2, child: TextField(controller: jumlahStokController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah'))),
                          const SizedBox(width: 10),
                          Expanded(flex: 1, child: TextField(controller: satuanStokController, decoration: const InputDecoration(labelText: 'Satuan'))),
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

// ================= TAB 3: HALAMAN STOK BARANG =================
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

// ================= TAB 4: DASHBOARD KEUANGAN & LAPORAN =================
class DashboardKeuanganPage extends StatefulWidget {
  final List pelanggan;
  final List pengeluaran;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const DashboardKeuanganPage({super.key, required this.pelanggan, required this.pengeluaran, required this.isLoading, required this.onRefresh});

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
    int totalPengeluaran = 0;
    Map<String, int> rekapKategoriPengeluaran = {};

    for (var item in widget.pelanggan) {
      if ((item['status'] ?? '').toString().toLowerCase() == 'lunas') {
        totalPemasukanLunas += _parseNominal(item['total_tunggakan']);
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
      appBar: AppBar(title: const Text('Dashboard Keuangan'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onRefresh)]),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Periode Laporan:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ToggleButtons(
                      isSelected: [selectedPeriode == 'Bulanan', selectedPeriode == 'Tahunan'],
                      onPressed: (index) => setState(() => selectedPeriode = index == 0 ? 'Bulanan' : 'Tahunan'),
                      borderRadius: BorderRadius.circular(8),
                      constraints: const BoxConstraints(minHeight: 32, minWidth: 90),
                      children: const [Text('Bulanan', style: TextStyle(fontSize: 12)), Text('Tahunan', style: TextStyle(fontSize: 12))],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: _cetakLaporanPdf,
                  icon: const Icon(Icons.print),
                  label: Text('Cetak Laporan $selectedPeriode (PDF)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 15),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Pemasukan (Lunas): Rp $totalPemasukanLunas', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                        const SizedBox(height: 8),
                        Text('Total Pengeluaran: Rp $totalPengeluaran', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red)),
                        const Divider(),
                        Text('Laba / Rugi Bersih: Rp $labaBersih', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: labaBersih >= 0 ? Colors.blue : Colors.orange)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
