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
  List pelanggan = [];
  List filteredPelanggan = [];
  bool isLoading = true;
  String searchQuery = '';
  String sortBy = 'default';

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
          _applyFilterAndSort();
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

  void _applyFilterAndSort() {
    List temp = List.from(pelanggan);

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                sortBy = value;
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
            onPressed: fetchPelanggan,
          )
        ],
      ),
      body: isLoading
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
                                subtitle: Text('Paket: ${item['paket'] ?? '-'}\nTunggakan: ${item['jumlah_bulan_tunggakan'] ?? '0'} Bulan (${item['status'] ?? '-'})'),
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
                                    fetchPelanggan();
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
            fetchPelanggan();
          }
        },
      ),
    );
  }
}

// ================= Halaman Detail Pelanggan =================
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

  // Dialog Konfirmasi Pembayaran & Custom Tunggakan
  void _showPaymentDialog() {
    String selectedMetode = 'Tunai';
    final TextEditingController penerimaController = TextEditingController();
    final TextEditingController bulanController = TextEditingController(text: '1');
    final TextEditingController totalTunggakanController = TextEditingController();
    final TextEditingController bayarController = TextEditingController();

    // Parse harga paket mentah menjadi angka untuk estimasi
    String hargaStr = (widget.pelangganData['harga'] ?? '0').toString().replaceAll(RegInMapNumberFilter(), '');
    // Regex pengganti sederhanakan ambil angka dari string harga (misal: "Rp 120.000" -> 120000)
    int hargaPaket = int.tryParse(widget.pelangganData['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
    
    totalTunggakanController.text = hargaPaket.toString();
    bayarController.text = hargaPaket.toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kelola Pembayaran & Tunggakan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: bulanController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Jumlah Bulan Tunggakan'),
                      onChanged: (val) {
                        int bulan = int.tryParse(val) ?? 1;
                        int total = bulan * hargaPaket;
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
                      decoration: const InputDecoration(labelText: 'Total Nominal Tunggakan (Rp)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bayarController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah yang Dibayar Sekarang (Rp)',
                        hintText: 'Misal: bayar 200rb dulu',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                      value: selectedMetode,
                      items: ['Tunai', 'QRIS', 'Transfer Bank'].map((metode) {
                        return DropdownMenuItem(value: metode, child: Text(metode));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedMetode = val!;
                        });
                      },
                    ),
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
                    _buildRow('Bulan Tunggakan', '${widget.pelangganData['jumlah_bulan_tunggakan'] ?? '0'} Bulan'),
                    _buildRow('Total Tunggakan', 'Rp ${widget.pelangganData['total_tunggakan'] ?? '0'}'),
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
            const SizedBox(height: 20),
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
                        // Reset jika ingin jadikan belum lunas lagi
                        updateStatusData({
                          "action": "update_status",
                          "idpel": widget.pelangganData['idpel']?.toString(),
                          "nama": widget.pelangganData['nama']?.toString(),
                          "status": "Belum Lunas",
                          "metode_pembayaran": "-",
                          "diterima_oleh": "-",
                          "jumlah_bulan_tunggakan": "1",
                          "total_tunggakan": "0",
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

// ================= Halaman Edit Pelanggan =================
class EditPelangganPage extends StatefulWidget {
  final Map<String, dynamic> pelangganData;

  const EditPelangganPage({super.key, required this.pelangganData});

  @override
  State<EditPelangganPage> createState() => _EditPelangganPageState();
}

class _EditPelangganPageState extends State<EditPelangganPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _namaController;
  late TextEditingController _alamatController;
  late TextEditingController _hpController;
  late TextEditingController _nikController;
  late TextEditingController _salesController;

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
    _namaController = TextEditingController(text: widget.pelangganData['nama']?.toString() ?? '');
    _alamatController = TextEditingController(text: widget.pelangganData['alamat']?.toString() ?? '');
    _hpController = TextEditingController(text: widget.pelangganData['no_hp']?.toString() ?? '');
    _nikController = TextEditingController(text: widget.pelangganData['nik']?.toString() ?? '');
    _salesController = TextEditingController(text: widget.pelangganData['sales']?.toString() ?? '');

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

    final payload = {
      "action": "update_pelanggan",
      "idpel": widget.pelangganData['idpel']?.toString(),
      "nama": _namaController.text,
      "alamat": _alamatController.text,
      "paket": selectedPaket!['nama'],
      "harga": selectedPaket!['harga'],
      "no_hp": _hpController.text,
      "nik": _nikController.text,
      "jatuh_tempo": selectedJatuhTempo,
      "sales": _salesController.text,
    };

    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        widget.pelangganData['nama'] = _namaController.text;
        widget.pelangganData['alamat'] = _alamatController.text;
        widget.pelangganData['paket'] = selectedPaket!['nama'];
        widget.pelangganData['harga'] = selectedPaket!['harga'];
        widget.pelangganData['no_hp'] = _hpController.text;
        widget.pelangganData['nik'] = _nikController.text;
        widget.pelangganData['jatuh_tempo'] = selectedJatuhTempo;
        widget.pelangganData['sales'] = _salesController.text;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data pelanggan berhasil diperbarui!')),
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
                value: selectedPaket,
                items: daftarPaket.map((paket) {
                  return DropdownMenuItem(
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
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tanggal Jatuh Tempo'),
                value: selectedJatuhTempo,
                items: daftarJatuhTempo.map((tgl) {
                  return DropdownMenuItem(value: tgl, child: Text(tgl));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedJatuhTempo = val!;
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

// ================= Halaman Tambah Pelanggan =================
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

    final payload = {
      "nama": _namaController.text,
      "alamat": _alamatController.text,
      "paket": selectedPaket!['nama'],
      "harga": selectedPaket!['harga'],
      "no_hp": _hpController.text,
      "nik": _nikController.text,
      "jatuh_tempo": selectedJatuhTempo,
      "status": selectedStatus,
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
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaket.map((paket) {
                  return DropdownMenuItem(
                    value: paket,
                    child: Text('${paket['nama']} (${paket['harga']})'),
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
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tanggal Jatuh Tempo'),
                value: selectedJatuhTempo,
                items: daftarJatuhTempo.map((tgl) {
                  return DropdownMenuItem(value: tgl, child: Text(tgl));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedJatuhTempo = val!;
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Status Pembayaran Awal'),
                value: selectedStatus,
                items: daftarStatus.map((st) {
                  return DropdownMenuItem(value: st, child: Text(st));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedStatus = val!;
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

// Helper kecil untuk regEx pencarian angka
RegExp RegInMapNumberFilter() => RegExp(r'[^0-9]');
