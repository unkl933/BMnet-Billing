import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String scriptUrl = 'https://script.google.com/macros/s/AKfycbzZdliydavTiyFWecz1OvPjGMh6vGd3-5zPbxoHRV95EBz5k9-rrNTvQ5k5MBm_9FmDhQ/exec';

void main() {
  runApp(const MaterialApp(
    home: BillingHomePage(),
    debugShowCheckedModeBanner: false,
  ));
}

class BillingHomePage extends StatefulWidget {
  const BillingHomePage({super.key});

  @override
  State<BillingHomePage> createState() => _BillingHomePageState();
}

class _BillingHomePageState extends State<BillingHomePage> {
  List<dynamic> pelanggan = [];
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
          pelanggan = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Billing Mini ISP (${pelanggan.length} Pelanggan)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPelanggan,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : pelanggan.isEmpty
              ? const Center(child: Text('Belum ada data pelanggan.'))
              : ListView.builder(
                  itemCount: pelanggan.length,
                  itemBuilder: (context, index) {
                    final item = pelanggan[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${item['no'] ?? index + 1}')),
                        title: Text(item['nama'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'IDPEL: ${item['idpel']}\nPaket: ${item['paket']} (${item['harga']})\nAlamat: ${item['alamat']}\nWA: ${item['no_hp']} | Tempo: ${item['jatuh_tempo']}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TambahPelangganPage()),
          );
          if (result == true) {
            fetchPelanggan();
          }
        },
      ),
    );
  }
}

class TambahPelangganPage extends StatefulWidget {
  const TambahPelangganPage({super.key});

  @override
  State<TambahPelangganPage> createState() => _TambahPelangganPageState();
}

class _TambahPelangganPageState extends State<TambahPelangganPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _alamatController = TextEditingController();
  final TextEditingController _hpController = TextEditingController();
  final TextEditingController _nikController = TextEditingController();
  final TextEditingController _salesController = TextEditingController();

  final List> daftarPaket = [
    {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
    {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
    {'nama': 'Paket Building (Free Android TV)', 'harga': 'Rp 121.622'},
    {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
    {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
    {'nama': '50 Mbps', 'harga': 'Rp 500.000'},
  ];

  Map<String, dynamic>? selectedPaket;
  bool isSaving = false;

  Future<void> simpanPelanggan() async {
    if (!_formKey.currentState!.validate() || selectedPaket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi form dan pilih paket internet!')),
      );
      return;
    }

    setState(() => isSaving = true);

    final payload = {
      "nama": _namaController.text,
      "alamat": _alamatController.text,
      "paket": selectedPaket!['nama'],
      "harga": selectedPaket!['harga'],
      "no_hp": _hpController.text,
      "nik": _nikController.text,
      "jatuh_tempo": "Tanggal 5",
      "sales": _salesController.text,
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
              DropdownButtonFormField>(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaket.map((paket) {
                  return DropdownMenuItem>(
                    value: paket,
                    child: Text('${paket['nama']} (${paket['harga']})'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedPaket = val;
                  });
                },
                validator: (val) => val == null ? 'Pilih paket' : null,
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
