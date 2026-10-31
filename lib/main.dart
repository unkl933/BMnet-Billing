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

const String scriptUrl = 'https://script.google.com/macros/s/AKfycbzZdliydavTiyFWecz1OvPjGMh6vGd3-5zPbxoHRV95EBz5k9-rrNTvQ5k5MBm_9FmDhQ/exec';

// PERBAIKAN: Gunakan penulisan List> dengan benar
List> daftarPaketGlobal = [
  {'nama': 'LITE 7 Mbps', 'harga': 'Rp 90.090'},
  {'nama': 'BASIC 10 Mbps', 'harga': 'Rp 108.108'},
  {'nama': 'STANDAR 15 Mbps', 'harga': 'Rp 135.135'},
  {'nama': '25 Mbps', 'harga': 'Rp 200.000'},
];

void main() {
  runApp(const MaterialApp(
    home: MainNavigationScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

// ================= NAVIGASI UTAMA (5 TAB) =================
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
      PengeluaranPage(pengeluaran: pengeluaranData, stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      StokBarangPage(stok: stokData, isLoading: isLoading, onRefresh: fetchData),
      PaketInternetPage(onUpdate: () => setState(() {})),
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
          BottomNavigationBarItem(icon: Icon(Icons.wifi), label: 'Paket'),
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

  Future<void> _sharePdfNotaWa(Map item, bool isLunas) async {
    final pdf = pw.Document();
    
    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      logoImage = null;
    }

    final now = DateTime.now();
    final tanggalCetak = "${now.day}/${now.month}/${now.year}";
    final noRef = isLunas ? "KW/BM/${now.year}/${now.month}/${item['idpel'] ?? '891'}" : "INV/BM/${now.year}/${now.month}/${item['idpel'] ?? '042'}";

    int totalNominal = int.tryParse((item['total_tunggakan'] ?? '0').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
    int dpp = (totalNominal / 1.11).round();
    int ppn = totalNominal - dpp;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              if (logoImage != null)
                pw.Center(
                  child: pw.Opacity(
                    opacity: 0.08,
                    child: pw.Image(logoImage, width: 300, height: 300),
                  ),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        children: [
                          if (logoImage != null)
                            pw.Image(logoImage, width: 40, height: 40)
                          else
                            pw.Container(
                              width: 40,
                              height: 40,
                              decoration: const pw.BoxDecoration(color: PdfColors.blue800, shape: pw.BoxShape.circle),
                              child: pw.Center(child: pw.Text('BN', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12))),
                            ),
                          pw.SizedBox(width: 10),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('BM Network', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                              pw.Text('Layanan Internet Cepat & Terpercaya', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                              pw.Text('Jl. Utama Networking No. 88 | WA: 0812-3456-7890', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                            ],
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(isLunas ? 'KWITANSI PELUNASAN' : 'NOTA TAGIHAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: isLunas ? PdfColors.green800 : PdfColors.blue800)),
                          pw.SizedBox(height: 2),
                          pw.Text('No: $noRef', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                          pw.Text('Tanggal: $tanggalCetak', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1.2, color: PdfColors.blue800),
                  pw.SizedBox(height: 8),
                  pw.Text('DATA PELANGGAN', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(children: [
                          pw.SizedBox(width: 90, child: pw.Text('ID Pelanggan', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(child: pw.Text(': ${item['idpel'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.SizedBox(width: 90, child: pw.Text('Nama Lengkap', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(child: pw.Text(': ${item['nama'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.SizedBox(width: 90, child: pw.Text('Alamat', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(child: pw.Text(': ${item['alamat'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.SizedBox(width: 90, child: pw.Text('No WhatsApp', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(child: pw.Text(': ${item['no_hp'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                        ]),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('RINCIAN LAYANAN & TARIF', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Deskripsi Paket / Layanan', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Periode (Bln)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Jumlah', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Paket Internet: ${item['paket'] ?? '-'}\nLangganan Akses Internet Unlimited', style: const pw.TextStyle(fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${item['jumlah_bulan_tunggakan'] ?? '1'}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rp $dpp', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.SizedBox(
                        width: 200,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                              pw.Text('Subtotal (Excl. PPN):', style: const pw.TextStyle(fontSize: 8)),
                              pw.Text('Rp $dpp', style: const pw.TextStyle(fontSize: 8)),
                            ]),
                            pw.SizedBox(height: 2),
                            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                              pw.Text('PPN 11%:', style: const pw.TextStyle(fontSize: 8)),
                              pw.Text('Rp $ppn', style: const pw.TextStyle(fontSize: 8)),
                            ]),
                            pw.Divider(thickness: 0.8),
                            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                              pw.Text('TOTAL PEMBAYARAN:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                              pw.Text('Rp $totalNominal', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Status: ${isLunas ? "LUNAS" : "BELUM LUNAS"}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: isLunas ? PdfColors.green800 : PdfColors.red800)),
                          if (isLunas) ...[
                            pw.Text('Metode Bayar: ${item['metode_pembayaran'] ?? "-"}', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('Admin / Petugas: ${item['petugas_penerima'] ?? "Admin BM Network"}', style: const pw.TextStyle(fontSize: 8)),
                          ]
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  if (!isLunas) ...[
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(color: PdfColors.blue50, border: pw.Border.all(color: PdfColors.blue200), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('METODE PEMBAYARAN (TRANSFER BANK, E-WALLET & QRIS):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                          pw.SizedBox(height: 3),
                          pw.Text('• Transfer Bank BCA: 2801-971-611 a.n. Irsyam Aufar Zuhdan', style: const pw.TextStyle(fontSize: 7)),
                          pw.Text('• E-Wallet (DANA / OVO / GoPay / ShopeePay): 0838-2777-7207 a.n. Irsyam Aufar Zuhdan', style: const pw.TextStyle(fontSize: 7)),
                          pw.Text('• QRIS: Scan kode QR resmi BM Network pada aplikasi Mobile Banking atau E-Wallet Anda.', style: const pw.TextStyle(fontSize: 7)),
                          pw.Text('• Mohon cantumkan ID Pelanggan (${item['idpel']}) pada catatan/berita transfer.', style: const pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 6),
                  ],
                  pw.Container(
                    padding: const pw.EdgeInsets.all(5),
                    decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
                    child: pw.Text(
                      isLunas 
                        ? "Terima kasih, pembayaran Anda telah diterima sah oleh sistem BM Network. Simpan kwitansi ini sebagai bukti pembayaran yang sah."
                        : "PERHATIAN: Mohon lakukan pembayaran sebelum tanggal jatuh tempo untuk menghindari isolir otomatis jaringan internet Anda. Abaikan penagihan jika pembayaran telah dilakukan.",
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    try {
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/${isLunas ? 'Kwitansi_Pelunasan' : 'Nota_Tagihan'}_${item['idpel']}.pdf");
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: isLunas 
            ? "Halo ${item['nama']}, berikut terlampir Kwitansi Pelunasan Resmi digital dari BM Network. Terima kasih!" 
            : "Halo ${item['nama']}, berikut terlampir Nota Tagihan internet BM Network untuk paket ${item['paket']}. Silakan lakukan pembayaran sebelum jatuh tempo. Abaikan penagihan jika pembayaran telah dilakukan.",
      );
    } catch (e) {
      // ignore
    }
  }

  void _showPelangganDetailDialog(BuildContext context, Map item) {
    bool isLunas = (item['status'] ?? '').toString().toLowerCase() == 'lunas';

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
              Text('Tunggakan    : ${item['jumlah_bulan_tunggakan'] ?? '1'} Bulan'),
              Text('Petugas/Kasir: ${item['petugas_penerima'] ?? '-'}'),
              const Divider(),
              Text('Status       : ${item['status'] ?? 'Belum Lunas'}', style: TextStyle(fontWeight: FontWeight.bold, color: isLunas ? Colors.green : Colors.red)),
              Text('Total Tagihan: Rp ${item['total_tunggakan'] ?? '0'}'),
              Text('Metode Bayar : ${item['metode_pembayaran'] ?? '-'}'),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.teal),
            onPressed: () => _sharePdfNotaWa(item, isLunas),
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: Text(isLunas ? 'Kirim Struk PDF' : 'Kirim Nota PDF'),
          ),
          if (!isLunas)
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
            label: const Text('Upgrade'),
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
    final TextEditingController petugasController = TextEditingController(text: 'Admin BM Network');
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
                    const SizedBox(height: 10),
                    TextField(
                      controller: petugasController,
                      decoration: const InputDecoration(labelText: 'Nama Petugas / Kasir Penerima'),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField(
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
                          height: 160,
                          width: 160,
                          errorBuilder: (context, error, stackTrace) => const Text(
                            'QRIS Image not found in assets/images/qris.png',
                            style: TextStyle(color: Colors.red, fontSize: 10),
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
                      "petugas_penerima": petugasController.text,
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
                bool isLunas = (item['status'] ?? '').toString().toLowerCase() == 'lunas';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    onTap: () => _showPelangganDetailDialog(context, item),
                    title: Text(item['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('ID: ${item['idpel']} | Paket: ${item['paket']}\nTagihan: ${item['jumlah_bulan_tunggakan'] ?? '1'} Bln (Rp ${item['total_tunggakan'] ?? '0'})\nStatus: ${item['status'] ?? 'Belum Lunas'}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.teal),
                      onPressed: () => _sharePdfNotaWa(item, isLunas),
                      tooltip: 'Kirim PDF via WhatsApp',
                    ),
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
  final TextEditingController _bulanTunggakanController = TextEditingController(text: '1');
  
  final TextEditingController _dropcoreController = TextEditingController(text: '0');
  final TextEditingController _patchcoreController = TextEditingController(text: '0');
  
  var selectedOnt;
  String selectedJatuhTempo = 'Tanggal 5';
  bool isSaving = false;
  var selectedPaket;

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
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Paket Internet'),
                items: daftarPaketGlobal.map((p) => DropdownMenuItem(value: p, child: Text('${p['nama']} (${p['harga']} + PPN)'))).toList(),
                onChanged: (val) => setState(() => selectedPaket = val),
              ),
              TextFormField(
                controller: _bulanTunggakanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah Bulan Tagihan / Tunggakan Awal'),
              ),

              const SizedBox(height: 20),
              const Text('Instalasi & Teknisi Lapangan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 16)),
              const Divider(),
              TextFormField(controller: _teknisiController, decoration: const InputDecoration(labelText: 'Nama Teknisi yang Bertugas')),
              
              const SizedBox(height: 10),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Pilih Perangkat ONT yang Dipasang'),
                value: selectedOnt,
                items: ontList.isEmpty 
                    ? [const DropdownMenuItem(value: null, child: Text('Stok ONT Kosong'))]
                    : ontList.map((o) => DropdownMenuItem(value: o['nama_barang'].toString(), child: Text('${o['nama_barang']} (Sisa: ${o['jumlah']})'))).toList(),
                onChanged: (val) => setState(() => selectedOnt = val),
              ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _dropcoreController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kabel Dropcore (Meter)'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(controller: _patchcoreController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Patchcore (Pcs)'))),
                ],
              ),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                onPressed: isSaving ? null : () async {
                  if (!_formKey.currentState!.validate() || selectedPaket == null) return;
                  setState(() => isSaving = true);

                  int hargaInt = int.tryParse(selectedPaket!['harga'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 100000;
                  int jmlBulan = int.tryParse(_bulanTunggakanController.text) ?? 1;
                  int totalTunggakan = (hargaInt * jmlBulan * 1.11).round();

                  List materialPakai = [];
                  if (selectedOnt != null) {
                    materialPakai.add({"nama": selectedOnt, "qty": 1});
                  }
                  double dropcoreVal = double.tryParse(_dropcoreController.text) ?? 0;
                  if (dropcoreVal > 0) {
                    materialPakai.add({"nama": "Dropcore 1 Roll", "qty": dropcoreVal});
                  }
                  int patchcoreVal = int.tryParse(_patchcoreController.text) ?? 0;
                  if (patchcoreVal > 0) {
                    materialPakai.add({"nama": "Patchcore", "qty": patchcoreVal});
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
                    "jumlah_bulan_tunggakan": jmlBulan.toString(),
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
  var selectedOntBaru;
  bool isSaving = false;
  var selectedPaketBaru;

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
    for (var p in daftarPaketGlobal) {
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
              const Text('Informasi & Ganti Paket / Tunggakan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 15)),
              const Divider(),
              TextFormField(controller: _namaController, decoration: const InputDecoration(labelText: 'Nama Pelanggan')),
              TextFormField(controller: _alamatController, decoration: const InputDecoration(labelText: 'Alamat')),
              TextFormField(controller: _hpController, decoration: const InputDecoration(labelText: 'No WhatsApp')),
              
              const SizedBox(height: 15),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Ganti Paket Internet'),
                value: selectedPaketBaru,
                items: daftarPaketGlobal.map((p) => DropdownMenuItem(value: p, child: Text('${p['nama']} (${p['harga']} + PPN)'))).toList(),
                onChanged: (val) => setState(() => selectedPaketBaru = val),
              ),

              TextFormField(
                controller: _bulanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah Bulan Tunggakan / Tagihan'),
              ),
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Status Tagihan'),
                value: selectedStatus,
                items: ['Lunas', 'Belum Lunas'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => selectedStatus = val.toString()),
              ),

              const SizedBox(height: 25),
              const Text('Penanganan Gangguan & Perangkat', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent, fontSize: 15)),
              const Divider(),
              
              DropdownButtonFormField(
                decoration: const InputDecoration(labelText: 'Penggantian ONT Baru (Opsional)'),
                value: selectedOntBaru,
                items: ontList.isEmpty 
                    ? [const DropdownMenuItem(value: null, child: Text('Stok ONT Kosong'))]
                    : ontList.map((o) => DropdownMenuItem(value: o['nama_barang'].toString(), child: Text('${o['nama_barang']} (Sisa: ${o['jumlah']})'))).toList(),
                onChanged: (val) => setState(() => selectedOntBaru = val),
              ),

              TextFormField(controller: _snOntController, decoration: const InputDecoration(labelText: 'Serial Number (SN) ONT')),
              TextFormField(controller: _gangguanController, decoration: const InputDecoration(labelText: 'Jenis Gangguan (Cth: Redaman Tinggi / Los)')),
              TextFormField(controller: _teknisiController, decoration: const InputDecoration(labelText: 'Nama Teknisi Perbaikan')),

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
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const PengeluaranPage({super.key, required this.pengeluaran, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  State<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends State<PengeluaranPage> {
  
  void _showFormPengeluaranDialog(BuildContext context, {Map? itemEdit}) {
    bool isEdit = itemEdit != null;
    final TextEditingController keteranganController = TextEditingController(text: isEdit ? itemEdit['keterangan'] : '');
    final TextEditingController nominalController = TextEditingController(text: isEdit ? itemEdit['nominal'] : '');
    
    final TextEditingController coreFoController = TextEditingController(text: '2');
    final TextEditingController rollFoController = TextEditingController(text: '1');
    final TextEditingController meterPerRollController = TextEditingController(text: '1000');

    final TextEditingController meterFoJalurController = TextEditingController(text: isEdit ? (itemEdit['meter_fo'] ?? '0') : '0');
    final TextEditingController jumlahPekerjaController = TextEditingController(text: isEdit ? (itemEdit['jumlah_pekerja'] ?? '1') : '1');
    final TextEditingController tanggalJalurController = TextEditingController(text: isEdit ? (itemEdit['tanggal_jalur'] ?? DateTime.now().toString().split(' ')[0]) : DateTime.now().toString().split(' ')[0]);
    final TextEditingController wilayahJalurController = TextEditingController(text: isEdit ? (itemEdit['wilayah'] ?? '') : '');

    final TextEditingController jumlahStokController = TextEditingController(text: isEdit ? (itemEdit['jumlah_stok'] ?? '1') : '1');
    final TextEditingController satuanStokController = TextEditingController(text: isEdit ? (itemEdit['satuan_stok'] ?? 'Pcs') : 'Pcs');

    String selectedKategori = isEdit ? (itemEdit['kategori'] ?? 'Operasional') : 'Operasional';
    String selectedJenisAset = 'ONT';

    final List<String> kategoriList = [
      'Belanja Aset',
      'Operasional',
      'Gaji Karyawan',
      'Hutang',
      'Donasi Sosial',
      'Maintenance / Pemeliharaan',
      'Penarikan Jalur FO'
    ];

    final List<String> jenisAsetList = [
      'ONT',
      'OLT',
      'FO',
      'STB',
      'Patchcore',
      'Protect',
      'Tools',
      'Aksesoris'
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isBelanjaAset = selectedKategori == 'Belanja Aset';
            bool isPenarikanJalur = selectedKategori == 'Penarikan Jalur FO';
            bool isFO = isBelanjaAset && selectedJenisAset == 'FO';

            return AlertDialog(
              title: Text(isEdit ? 'Edit Pengeluaran' : 'Tambah Pengeluaran'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      value: selectedKategori,
                      items: kategoriList.map((kat) => DropdownMenuItem(value: kat, child: Text(kat))).toList(),
                      onChanged: (val) => setDialogState(() => selectedKategori = val.toString()),
                    ),
                    const SizedBox(height: 10),

                    if (isBelanjaAset) ...[
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Jenis Barang Aset'),
                        value: selectedJenisAset,
                        items: jenisAsetList.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
                        onChanged: (val) => setDialogState(() => selectedJenisAset = val.toString()),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (isPenarikanJalur) ...[
                      TextField(
                        controller: wilayahJalurController,
                        decoration: const InputDecoration(labelText: 'Wilayah Penarikan Jalur'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: meterFoJalurController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Banyak Kabel FO yang Digunakan (Meter)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: jumlahPekerjaController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Jumlah Orang yang Mengerjakan'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tanggalJalurController,
                        decoration: const InputDecoration(labelText: 'Tanggal Penarikan (YYYY-MM-DD)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: keteranganController,
                        decoration: const InputDecoration(labelText: 'Keterangan Tambahan / Nama Jalur'),
                      ),
                    ] else ...[
                      TextField(
                        controller: keteranganController, 
                        decoration: InputDecoration(labelText: isBelanjaAset ? 'Nama / Merek Perangkat Aset' : 'Keterangan Pengeluaran'),
                      ),
                    ],

                    const SizedBox(height: 10),
                    TextField(
                      controller: nominalController, 
                      keyboardType: TextInputType.number, 
                      decoration: const InputDecoration(labelText: 'Total Nominal Biaya (Rp)'),
                    ),
                    
                    if (isBelanjaAset) ...[
                      const SizedBox(height: 15),
                      const Divider(),
                      const Text('Konfigurasi Stok Gudang Otomatis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                      const SizedBox(height: 8),

                      if (isFO) ...[
                        Row(
                          children: [
                            Expanded(child: TextField(controller: coreFoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Banyak Core (Cth: 2/4)'))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: rollFoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Banyak Roll'))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: meterPerRollController, 
                          keyboardType: TextInputType.number, 
                          decoration: const InputDecoration(labelText: 'Meter Per Roll (Cth: 1000)'),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(flex: 2, child: TextField(controller: jumlahStokController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah'))),
                            const SizedBox(width: 10),
                            Expanded(flex: 1, child: TextField(controller: satuanStokController, decoration: const InputDecoration(labelText: 'Satuan'))),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () async {
                    if (nominalController.text.isEmpty) return;
                    
                    String finalJumlahStok = jumlahStokController.text;
                    String finalSatuanStok = satuanStokController.text;
                    String namaBarangFinal = keteranganController.text;
                    List pemakaianMaterial = [];

                    if (isBelanjaAset) {
                      if (isFO) {
                        int rolls = int.tryParse(rollFoController.text) ?? 1;
                        int meters = int.tryParse(meterPerRollController.text) ?? 1000;
                        int totalMeter = rolls * meters;
                        finalJumlahStok = totalMeter.toString();
                        finalSatuanStok = 'Meter';
                        namaBarangFinal = 'Kabel FO ${coreFoController.text} Core ($rolls Roll x $meters Meter)';
                      } else {
                        namaBarangFinal = '[$selectedJenisAset] ${keteranganController.text}';
                      }
                    } else if (isPenarikanJalur) {
                      double meterFo = double.tryParse(meterFoJalurController.text) ?? 0;
                      namaBarangFinal = 'Penarikan Jalur FO di ${wilayahJalurController.text} (${meterFo} Meter, ${jumlahPekerjaController.text} Orang)';
                      if (meterFo > 0) {
                        pemakaianMaterial.add({"nama": "Kabel FO", "qty": meterFo});
                      }
                    }

                    final payload = {
                      "action": isEdit ? "edit_pengeluaran" : "tambah_pengeluaran",
                      "index": isEdit ? widget.pengeluaran.indexOf(itemEdit) : null,
                      "kategori": selectedKategori,
                      "keterangan": namaBarangFinal,
                      "nominal": nominalController.text,
                      "jumlah_stok": finalJumlahStok,
                      "satuan_stok": finalSatuanStok,
                      "pemakaian_material": pemakaianMaterial.isNotEmpty ? pemakaianMaterial : null,
                      "tanggal": isEdit ? (itemEdit['tanggal'] ?? DateTime.now().toString().split(' ')[0]) : DateTime.now().toString().split(' ')[0],
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Rp ${item['nominal'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                              onPressed: () => _showFormPengeluaranDialog(context, itemEdit: item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showFormPengeluaranDialog(context), child: const Icon(Icons.add)),
    );
  }
}

// ================= TAB 3: HALAMAN STOK BARANG =================
class StokBarangPage extends StatefulWidget {
  final List stok;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const StokBarangPage({super.key, required this.stok, required this.isLoading, required this.onRefresh});

  @override
  State<StokBarangPage> createState() => _StokBarangPageState();
}

class _StokBarangPageState extends State<StokBarangPage> {

  void _showFormStokDialog(BuildContext context, {Map? itemEdit}) {
    bool isEdit = itemEdit != null;
    final TextEditingController namaController = TextEditingController(text: isEdit ? itemEdit['nama_barang'] : '');
    final TextEditingController kategoriController = TextEditingController(text: isEdit ? itemEdit['kategori'] : 'ONT/Perangkat');
    final TextEditingController jumlahController = TextEditingController(text: isEdit ? itemEdit['jumlah'].toString() : '1');
    final TextEditingController satuanController = TextEditingController(text: isEdit ? itemEdit['satuan'] : 'Pcs');
    final TextEditingController ketController = TextEditingController(text: isEdit ? itemEdit['keterangan'] : 'Stok Gudang');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Stok Barang' : 'Tambah Stok Gudang Manual'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: namaController, decoration: const InputDecoration(labelText: 'Nama Barang')),
                TextField(controller: kategoriController, decoration: const InputDecoration(labelText: 'Kategori')),
                TextField(controller: jumlahController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah / Qty')),
                TextField(controller: satuanController, decoration: const InputDecoration(labelText: 'Satuan (Pcs / Meter / Roll)')),
                TextField(controller: ketController, decoration: const InputDecoration(labelText: 'Keterangan')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (namaController.text.isEmpty || jumlahController.text.isEmpty) return;
                final payload = {
                  "action": isEdit ? "edit_stok" : "tambah_stok_manual",
                  "index": isEdit ? widget.stok.indexOf(itemEdit) : null,
                  "nama_barang": namaController.text,
                  "kategori": kategoriController.text,
                  "jumlah": jumlahController.text,
                  "satuan": satuanController.text,
                  "keterangan": ketController.text,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stok Barang Jaringan (${widget.stok.length})'), 
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onRefresh)
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.stok.isEmpty
              ? const Center(child: Text('Belum ada stok barang.'))
              : ListView.builder(
                  itemCount: widget.stok.length,
                  itemBuilder: (context, index) {
                    final item = widget.stok[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.router, color: Colors.indigo),
                        title: Text(item['nama_barang'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Kategori: ${item['kategori'] ?? '-'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${item['jumlah'] ?? '0'} ${item['satuan'] ?? 'Pcs'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                              onPressed: () => _showFormStokDialog(context, itemEdit: item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormStokDialog(context),
        child: const Icon(Icons.add),
        tooltip: 'Tambah Stok Barang',
      ),
    );
  }
}

// ================= TAB 4: HALAMAN MANAJEMEN PAKET INTERNET =================
class PaketInternetPage extends StatefulWidget {
  final VoidCallback onUpdate;
  const PaketInternetPage({super.key, required this.onUpdate});

  @override
  State<PaketInternetPage> createState() => _PaketInternetPageState();
}

class _PaketInternetPageState extends State<PaketInternetPage> {
  void _showFormPaketDialog({Map<String, dynamic>? itemEdit}) {
    bool isEdit = itemEdit != null;
    final TextEditingController namaController = TextEditingController(text: isEdit ? itemEdit['nama'] : '');
    final TextEditingController hargaController = TextEditingController(text: isEdit ? itemEdit['harga'] : '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Paket Internet' : 'Tambah Paket Internet Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: namaController, decoration: const InputDecoration(labelText: 'Nama Paket (Cth: 30 Mbps)')),
              const SizedBox(height: 10),
              TextField(controller: hargaController, decoration: const InputDecoration(labelText: 'Harga (Cth: Rp 150.000)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                if (namaController.text.isEmpty || hargaController.text.isEmpty) return;
                setState(() {
                  if (isEdit) {
                    itemEdit['nama'] = namaController.text;
                    itemEdit['harga'] = hargaController.text;
                  } else {
                    daftarPaketGlobal.add({
                      'nama': namaController.text,
                      'harga': hargaController.text,
                    });
                  }
                });
                widget.onUpdate();
                Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Daftar Paket Internet (${daftarPaketGlobal.length})')),
      body: ListView.builder(
        itemCount: daftarPaketGlobal.length,
        itemBuilder: (context, index) {
          final paket = daftarPaketGlobal[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: const Icon(Icons.wifi, color: Colors.blueAccent),
              title: Text(paket['nama'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Tarif: ${paket['harga']} (+ PPN 11%)'),
              trailing: IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: () => _showFormPaketDialog(itemEdit: paket),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormPaketDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Tambah Paket Baru',
      ),
    );
  }
}

// ================= TAB 5: DASHBOARD KEUANGAN & LAPORAN =================
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
    int totalPotensiTunggakan = 0;
    int totalPengeluaran = 0;

    Map<String, int> rekapKategoriPengeluaran = {};
    List rincianPemasukanLunas = [];
    List rincianPenguranganMaterial = [];

    for (var item in widget.pelanggan) {
      final status = (item['status'] ?? 'Belum Lunas').toString().toLowerCase();
      final total = _parseNominal(item['total_tunggakan']);
      if (status == 'lunas') {
        totalLunas += total;
        rincianPemasukanLunas.add({
          "nama": item['nama'] ?? '-',
          "idpel": item['idpel'] ?? '-',
          "paket": item['paket'] ?? '-',
          "metode": item['metode_pembayaran'] ?? 'Tunai',
          "petugas": item['petugas_penerima'] ?? 'Admin',
          "nominal": total,
        });
      } else {
        totalPotensiTunggakan += total;
      }

      if (item['material_terpakai'] != null && item['material_terpakai'].toString() != '-' && item['material_terpakai'].toString().isNotEmpty) {
        rincianPenguranganMaterial.add({
          "pelanggan": item['nama'] ?? '-',
          "material": item['material_terpakai'],
          "teknisi": item['teknisi'] ?? '-',
        });
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
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('BM Network - LAPORAN KEUANGAN & REKAP BULANAN', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                    pw.Text('Periode: $selectedPeriode (${now.year}) | Tanggal Cetak: $tglCetak', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1.2, color: PdfColors.blue800),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green300), color: PdfColors.green50),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PEMASUKAN (LUNAS)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                        pw.Text('Rp $totalLunas', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text('PPN 11%: Rp $ppnLunas', style: const pw.TextStyle(fontSize: 6)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.orange300), color: PdfColors.orange50),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL PIUTANG', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                        pw.Text('Rp $totalPotensiTunggakan', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red300), color: PdfColors.red50),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PENGELUARAN', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                        pw.Text('Rp $totalPengeluaran', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text('1. RINCIAN PEMASUKAN PELANGGAN (LUNAS)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 4),
            rincianPemasukanLunas.isEmpty
                ? pw.Text('Belum ada transaksi pemasukan lunas.', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic))
                : pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Pelanggan (ID)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Paket', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Metode & Admin', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Nominal', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                        ],
                      ),
                      ...rincianPemasukanLunas.map((p) => pw.TableRow(
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${p['nama']} (${p['idpel']})', style: const pw.TextStyle(fontSize: 7))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(p['paket'], style: const pw.TextStyle(fontSize: 7))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${p['metode']} / ${p['petugas']}', style: const pw.TextStyle(fontSize: 7))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Rp ${p['nominal']}', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right)),
                        ],
                      )),
                    ],
                  ),
            pw.SizedBox(height: 12),
            pw.Text('2. RINCIAN PENGURANGAN / PEMAKAIAN MATERIAL & PERANGKAT', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 4),
            rincianPenguranganMaterial.isEmpty
                ? pw.Text('Tidak ada riwayat pengurangan material pada periode ini.', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic))
                : pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Pelanggan', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Material / Perangkat Terpakai', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Teknisi Bertugas', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                        ],
                      ),
                      ...rincianPenguranganMaterial.map((m) => pw.TableRow(
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m['pelanggan'], style: const pw.TextStyle(fontSize: 7))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m['material'], style: const pw.TextStyle(fontSize: 7))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m['teknisi'], style: const pw.TextStyle(fontSize: 7))),
                        ],
                      )),
                    ],
                  ),
            pw.SizedBox(height: 12),
            pw.Text('3. REKAP PENGELUARAN OPERASIONAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Kategori Pengeluaran', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Nominal', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  ],
                ),
                ...rekapKategoriPengeluaran.entries.map((e) => pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 7))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Rp ${e.value}', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right)),
                  ],
                )),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Text('LABA / RUGI BERSIH: Rp $labaBersih', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Laporan_Keuangan_Lengkap_BMNetwork.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalPemasukanLunas = 0;
    int totalTunggakanPelanggan = 0;
    int totalPengeluaran = 0;

    for (var item in widget.pelanggan) {
      if ((item['status'] ?? '').toString().toLowerCase() == 'lunas') {
        totalPemasukanLunas += _parseNominal(item['total_tunggakan']);
      } else {
        totalTunggakanPelanggan += _parseNominal(item['total_tunggakan']);
      }
    }

    for (var item in widget.pengeluaran) {
      totalPengeluaran += _parseNominal(item['nominal']);
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
                    const Text('Periode Rekap:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  label: Text('Cetak Laporan Lengkap $selectedPeriode (PDF)', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        Text('Total Piutang/Tunggakan: Rp $totalTunggakanPelanggan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
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
