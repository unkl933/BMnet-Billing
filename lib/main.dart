// ============================================================
//  BM Network Ops - Modul Billing  (lib/main.dart)
//  Backend: Google Apps Script + Google Spreadsheet
//  Aset   : assets/images/logo.png , assets/images/qris.png
// ============================================================
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ------------------------------------------------------------
//  KONFIGURASI  (ubah sesuai data perusahaan)
// ------------------------------------------------------------
class Cfg {
  static const scriptUrl = 'https://script.google.com/macros/s/AKfycbwkQ4HbMaBlE4tVxlIUIfhNTgXgkgmzz-kWF-CHmuMMs1BB95okkMvuntsCFwx_F0M/exec';
  static const token = '331933'; // samakan dengan TOKEN di Code.gs (boleh kosong)
  static const company = 'BM Network';
  static const tagline = 'Internet Solution';
  static const address = 'Jl. Kiarajangkung RT/RW : 02/04 Desa Kiarajangkung No. 88';
  static const wa = '0812-3456-7890';
  static const bank = 'BCA 1234567890';
  static const ewallet = '0812-3456-7890 (DANA / OVO / GoPay / ShopeePay)';
  static const atasNama = 'BM Network';
  static const ppn = 0.11;
  static const kategori = ['Belanja Aset', 'Operasional', 'Gaji Karyawan', 'Hutang', 'Maintenance'];
  static const jenisBarang = ['ONT', 'OLT', 'Mikrotik', 'FO', 'Patchcore', 'STB', 'Selongsong', 'Aksesoris'];
  static const metodeBayar = ['Tunai', 'Transfer BCA', 'QRIS', 'DANA', 'OVO', 'GoPay', 'ShopeePay'];
  static const metodePasang = ['Belum Dibayar', 'Tunai', 'QRIS', 'DANA', 'OVO', 'GoPay', 'ShopeePay'];
}

class C {
  static const bg = Color(0xFF0B1220);
  static const card = Color(0xFF16213A);
  static const emerald = Color(0xFF10B981);
  static const rose = Color(0xFFF43F5E);
  static const cyan = Color(0xFF22D3EE);
  static const slate = Color(0xFF8A99B5);
  static const amber = Color(0xFFF59E0B);
}

// ------------------------------------------------------------
//  HELPER UMUM
// ------------------------------------------------------------
const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const monFull = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

String rpf(num v) => 'Rp ${NumberFormat('#,##0', 'id_ID').format(v.round())}';
String fmtN(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String dmy(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? s : DateFormat('dd/MM/yyyy').format(d);
}

String newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch}';
String nk(String k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
TextEditingController _c([String s = '']) => TextEditingController(text: s);
num pn(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Satu baris data. Kunci dinormalisasi (huruf kecil, tanpa simbol) sehingga
/// "Nama", "NAMA", "nama_pelanggan" dsb dibaca dengan aman (anti column shift).
class Rec {
  final Map<String, String> m;
  Rec(Map raw) : m = {for (final e in raw.entries) nk('${e.key}'): '${e.value ?? ''}'};
  String s(String k, [List<String> alt = const []]) {
    for (final x in [k, ...alt]) {
      final v = m[nk(x)];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  num n(String k, [List<String> alt = const []]) => num.tryParse(s(k, alt)) ?? 0;
  int i(String k, [List<String> alt = const []]) => n(k, alt).toInt();
}

Rec? find(List<Rec> l, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final r in l) {
    if (r.s('id') == id) return r;
  }
  return null;
}

String paketLabel(Rec p) => p.s('kecepatan').isEmpty ? p.s('nama') : '${p.s('nama')} ${p.s('kecepatan')} Mbps';
String stokName(Rec s) => s.s('merk').isNotEmpty ? s.s('merk') : s.s('nama');
String alamat(Rec c) =>
    '${c.s('kampung')}, RT/RW ${c.s('rtrw')}, Kec. ${c.s('kecamatan')}, ${c.s('kabupaten')}';

Map<String, String> lst(List<String> l) => {for (final x in l) x: x};

Map<String, String> stokItems(String jenis, {bool onlyAvail = true}) => {
      for (final s in store.stok)
        if (s.s('jenis').toLowerCase() == jenis.toLowerCase() && (!onlyAvail || s.n('jumlah') > 0))
          s.s('id'): '${stokName(s)} (sisa ${fmtN(s.n('jumlah'))} ${s.s('satuan')})'
    };

String nextCustId() {
  var mx = 0;
  for (final c in store.pelanggan) {
    final mm = RegExp(r'^BM(\d+)$').firstMatch(c.s('id'));
    if (mm != null) mx = max(mx, int.parse(mm.group(1)!));
  }
  return 'BM${(mx + 1).toString().padLeft(3, '0')}';
}

String nextDoc(String p) {
  final d = DateTime.now();
  return '$p/BM/${d.year}/${d.month.toString().padLeft(2, '0')}/${(store.transaksi.length + 1).toString().padLeft(3, '0')}';
}

// ------------------------------------------------------------
//  API (Google Apps Script)
// ------------------------------------------------------------
Map<String, dynamic> dual(Map<String, dynamic> d) => {
      ...d,
      for (final e in d.entries) e.key.toUpperCase(): e.value, // Dual-Key Payload
    };
Map<String, dynamic> op(String sheet, String o, Map<String, dynamic> d) =>
    {'sheet': sheet, 'op': o, 'data': dual(d)};
Map<String, dynamic> adj(String id, num delta) => op('Stok', 'adjust', {'id': id, 'delta': delta});

class Api {
    static Future<Map<String, dynamic>> get() async {
    if (Cfg.scriptUrl.startsWith('PASTE')) throw 'Isi Cfg.scriptUrl dengan URL Web App Apps Script';
    
    final client = http.Client();
    try {
      // Menambahkan cache-buster (cb) menggunakan timestamp agar Google membaca data terbaru
      final url = '${Cfg.scriptUrl}?action=all&token=${Uri.encodeComponent(Cfg.token)}&cb=${DateTime.now().millisecondsSinceEpoch}';
      
      final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
      var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 40)));
      
      // Menangani HTTP 302 Redirect secara eksplisit seperti pada method POST
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers['location'] != null) {
        res = await http.get(Uri.parse(res.headers['location']!));
      }
      
      return jsonDecode(res.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }


  static Future<Map<String, dynamic>> post(Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(Cfg.scriptUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode(body);
      var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 40)));
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers['location'] != null) {
        res = await http.get(Uri.parse(res.headers['location']!));
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}

class Store extends ChangeNotifier {
  List<Rec> pelanggan = [], pengeluaran = [], stok = [], paket = [], transaksi = [], material = [], gangguan = [], penarikan = [];
  bool loading = false;
  String? error;

  List<Rec> _l(Map d, String k) {
    final key = d.keys.firstWhere(
      (element) => element.toString().toLowerCase() == k.toLowerCase(),
      orElse: () => null,
   );
    final v = key != null ? d[key] : null;
    return v is List ? v.map((e) => Rec(e as Map)).toList() : <Rec>[];
   }
  
  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final d = await Api.get();
      if (d['error'] != null) throw '${d['error']}';
      pelanggan = _l(d, 'Pelanggan');
      pengeluaran = _l(d, 'Pengeluaran');
      stok = _l(d, 'Stok');
      paket = _l(d, 'Paket');
      transaksi = _l(d, 'Transaksi');
      material = _l(d, 'Material');
      gangguan = _l(d, 'Gangguan');
      penarikan = _l(d, 'Penarikan');
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  /// Kirim beberapa operasi sekaligus (atomik di server), lalu sinkron ulang.
  Future<String?> run(List<Map<String, dynamic>> ops) async {
    try {
      final r = await Api.post({'action': 'batch', 'token': Cfg.token, 'ops': ops});
      if (r['ok'] != true) return '${r['error'] ?? 'Gagal menyimpan'}';
      await refresh();
      return error;
    } catch (e) {
      return '$e';
    }
  }
}

final store = Store();

Future<void> exec(BuildContext c, List<Map<String, dynamic>> ops, {String ok = 'Berhasil'}) async {
  final err = await store.run(ops);
  if (c.mounted) toast(c, err ?? ok);
}

// ------------------------------------------------------------
//  UI KECIL
// ------------------------------------------------------------
class Panel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Panel({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Material(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      );
}

Widget tag(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );

class Metric extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const Metric(this.label, this.value, this.color, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          Text(label, style: const TextStyle(color: C.slate, fontSize: 12)),
        ]),
      );
}

Widget tf(TextEditingController c, String l,
        {TextInputType? kb, bool en = true, int lines = 1, ValueChanged<String>? ch, String? hint}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: kb,
        enabled: en,
        maxLines: lines,
        onChanged: ch,
        decoration: InputDecoration(labelText: l, hintText: hint, border: const OutlineInputBorder()),
      ),
    );

const numKb = TextInputType.numberWithOptions(decimal: true);

Widget dd(String l, String? v, Map<String, String> items, ValueChanged<String?> f, {bool en = true}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: items.containsKey(v) ? v : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: en ? f : null,
      ),
    );

Widget payHint(String m) {
  if (m == 'QRIS') return Center(child: Image.asset('assets/images/qris.png', height: 220));
  if (m == 'Transfer BCA') {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Rekening: ${Cfg.bank} a.n. ${Cfg.atasNama}'));
  }
  if (['DANA', 'OVO', 'GoPay', 'ShopeePay'].contains(m)) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('$m: ${Cfg.ewallet} a.n. ${Cfg.atasNama}'));
  }
  return const SizedBox.shrink();
}

Future<T?> sheet<T>(BuildContext c, Widget w) => showModalBottomSheet<T>(
      context: c,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: w),
    );

Future<bool> confirm(BuildContext c, String title, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, lanjutkan'),
          ),
        ],
      ),
    ) ??
    false;

/// Mixin untuk form bottom-sheet: tombol simpan + kirim operasi ke server.
mixin Submit<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> go(List<Map<String, dynamic>> ops, [Object? result]) async {
    setState(() => busy = true);
    final err = await store.run(ops);
    if (!mounted) return;
    if (err != null) {
      setState(() => busy = false);
      toast(context, err);
    } else {
      Navigator.pop(context, result ?? true);
    }
  }

  Widget btn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : onTap,
            child: busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label),
          ),
        ),
      );

  Widget body(String title, List<Widget> ch) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ...ch,
        ]),
      );
}

void previewPdf(BuildContext c, String name, Future<Uint8List> Function() build) {
  Navigator.push(
    c,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: PdfPreview(
          build: (_) => build(),
          pdfFileName: '$name.pdf',
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          actions: [
            PdfPreviewAction(
              icon: const Icon(Icons.chat),
              onPressed: (ctx, b, f) async {
                await Printing.sharePdf(bytes: await b(f), filename: '$name.pdf'); // pilih WhatsApp
              },
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------
//  MAIN & SHELL
// ------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BMApp());
}

class BMApp extends StatelessWidget {
  const BMApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BM Network Ops',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: C.emerald, brightness: Brightness.dark, surface: C.bg)
              .copyWith(secondary: C.cyan, error: C.rose),
          scaffoldBackgroundColor: C.bg,
          appBarTheme: const AppBarTheme(backgroundColor: C.bg, surfaceTintColor: Colors.transparent),
          bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.card),
          navigationBarTheme: const NavigationBarThemeData(backgroundColor: C.card),
        ),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int section = 0, tab = 0;
  static const titles = ['Dashboard', 'Pelanggan', 'Pengeluaran', 'Stok Gudang', 'Paket Internet', 'Keuangan'];

  @override
  void initState() {
    super.initState();
    store.refresh();
  }

  Widget? fab(BuildContext c) {
    switch (tab) {
      case 1:
        return FloatingActionButton.extended(
            onPressed: () => openPasangBaru(c), icon: const Icon(Icons.person_add), label: const Text('Pasang Baru'));
      case 2:
        return FloatingActionButton.extended(
            onPressed: () => sheet(c, const ExpenseForm()), icon: const Icon(Icons.add), label: const Text('Pengeluaran'));
      case 3:
        return FloatingActionButton.extended(
            onPressed: () => sheet(c, const StokForm()), icon: const Icon(Icons.add), label: const Text('Stok'));
      case 4:
        return FloatingActionButton.extended(
            onPressed: () => sheet(c, const PaketForm()), icon: const Icon(Icons.add), label: const Text('Paket'));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final billing = section == 0;
        return Scaffold(
          appBar: AppBar(
            title: Text(billing ? 'Billing - ${titles[tab]}' : 'Tentang Aplikasi'),
            actions: billing
                ? [
                    store.loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(tooltip: 'Refresh data', icon: const Icon(Icons.refresh), onPressed: store.refresh),
                  ]
                : null,
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Image.asset('assets/images/logo.png', height: 72),
                    const SizedBox(height: 10),
                    const Text('BM Network Ops', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text('Internet Solution', style: TextStyle(color: C.slate)),
                  ]),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: const Text('Billing'),
                  selected: section == 0,
                  onTap: () {
                    setState(() => section = 0);
                    Navigator.pop(context);
                  },
                ),
                const ListTile(enabled: false, leading: Icon(Icons.hub), title: Text('PPPoE'), subtitle: Text('Segera hadir')),
                const ListTile(
                    enabled: false, leading: Icon(Icons.confirmation_number), title: Text('Voucher'), subtitle: Text('Segera hadir')),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Tentang Aplikasi'),
                  selected: section == 1,
                  onTap: () {
                    setState(() => section = 1);
                    Navigator.pop(context);
                  },
                ),
              ]),
            ),
          ),
          body: !billing
              ? const AboutPage()
              : Column(children: [
                  if (store.error != null)
                    Container(
                      width: double.infinity,
                      color: C.rose.withValues(alpha: .18),
                      padding: const EdgeInsets.all(10),
                      child: Text('Gagal sinkron: ${store.error}', style: const TextStyle(color: C.rose, fontSize: 12)),
                    ),
                  Expanded(
                    child: IndexedStack(index: tab, children: [
                      DashTab(onGo: (i) => setState(() => tab = i)),
                      const PelangganTab(),
                      const PengeluaranTab(),
                      const StokTab(),
                      const PaketTab(),
                      const KeuTab(),
                    ]),
                  ),
                ]),
          floatingActionButton: billing ? fab(context) : null,
          bottomNavigationBar: billing
              ? NavigationBar(
                  selectedIndex: tab,
                  labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
                    NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Pelanggan'),
                    NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Pengeluaran'),
                    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stok'),
                    NavigationDestination(icon: Icon(Icons.router_outlined), selectedIcon: Icon(Icons.router), label: 'Paket'),
                    NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance), label: 'Keuangan'),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Image.asset('assets/images/logo.png', height: 110)),
        const SizedBox(height: 12),
        const Center(child: Text('BM Network Ops', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const Center(child: Text('Versi 1.0.0', style: TextStyle(color: C.slate))),
        const SizedBox(height: 20),
        const Text(
          'Aplikasi manajemen operasional ISP BM Network. Modul saat ini: Billing '
          '(pelanggan, penagihan, pengeluaran, stok gudang, paket internet, dan laporan keuangan). '
          'Modul PPPoE dan Voucher akan ditambahkan pada versi berikutnya.',
        ),
        const SizedBox(height: 16),
        const Text('Data tersimpan di Google Spreadsheet melalui Google Apps Script.', style: TextStyle(color: C.slate)),
        const SizedBox(height: 16),
        Text('${Cfg.address}\nWA Support: ${Cfg.wa}', style: const TextStyle(color: C.slate)),
      ]);
}

// ------------------------------------------------------------
//  TAB 0 : DASHBOARD
// ------------------------------------------------------------
class DashTab extends StatelessWidget {
  final ValueChanged<int> onGo;
  const DashTab({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool sameMonth(DateTime? d, DateTime t) => d != null && d.year == t.year && d.month == t.month;
    final baru = store.pelanggan.where((c) => sameMonth(DateTime.tryParse(c.s('tgl_pasang')), now)).length;
    final belum = store.pelanggan.where((c) => c.i('bulan_tunggak') > 0).length;
    final inc = store.transaksi
        .where((t) => sameMonth(DateTime.tryParse(t.s('tgl')), now))
        .fold<num>(0, (a, t) => a + t.n('nominal'));
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    final vals = [
      for (final m in months) store.pelanggan.where((c) => sameMonth(DateTime.tryParse(c.s('tgl_pasang')), m)).length
    ];
    final mx = vals.fold<int>(1, (a, b) => b > a ? b : a);

    final quick = <(IconData, String, Color, VoidCallback)>[
      (Icons.person_add, 'Pasang Baru', C.emerald, () => openPasangBaru(context)),
      (Icons.people, 'Pelanggan', C.cyan, () => onGo(1)),
      (Icons.payments, 'Pengeluaran', C.rose, () => onGo(2)),
      (Icons.inventory_2, 'Stok Gudang', C.amber, () => onGo(3)),
      (Icons.router, 'Paket', C.cyan, () => onGo(4)),
      (Icons.account_balance, 'Keuangan', C.emerald, () => onGo(5)),
    ];

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(7, 8, 7, 24), children: [
        Row(children: [
          Expanded(child: Metric('Total Pelanggan', '${store.pelanggan.length}', C.cyan, Icons.people)),
          Expanded(child: Metric('User Baru ${mon[now.month - 1]}', '$baru', C.emerald, Icons.person_add)),
        ]),
        Row(children: [
          Expanded(child: Metric('Belum Lunas', '$belum', C.rose, Icons.warning_amber)),
          Expanded(child: Metric('Pemasukan Bulan Ini', rpf(inc), C.amber, Icons.trending_up)),
        ]),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pelanggan Baru (6 bulan terakhir)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 190,
              child: BarChart(BarChartData(
                maxY: (mx + 1).toDouble(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: max(1, (mx / 4).ceil()).toDouble(),
                      getTitlesWidget: (v, meta) =>
                          Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: C.slate)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(mon[months[v.toInt()].month - 1], style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < vals.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: vals[i].toDouble(),
                        width: 20,
                        color: i == vals.length - 1 ? C.emerald : C.cyan,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]),
                ],
              )),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 14, 12, 4),
          child: Text('Akses Cepat', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          childAspectRatio: 1.05,
          children: [
            for (final q in quick)
              Container(
                margin: const EdgeInsets.all(5),
                child: Material(
                  color: C.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: q.$4,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(q.$1, color: q.$3, size: 28),
                      const SizedBox(height: 8),
                      Text(q.$2, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------
//  TAB 1 : PELANGGAN
// ------------------------------------------------------------
Future<void> openPasangBaru(BuildContext c) async {
  final r = await sheet(c, const PasangBaruForm());
  if (r is Map<String, dynamic> && c.mounted) {
    previewPdf(c, 'Nota_${r['id']}', () => buildNota(Rec(r['cust']), r['paid'] as num, '${r['metode']}'));
  }
}

class PelangganTab extends StatefulWidget {
  const PelangganTab({super.key});
  @override
  State<PelangganTab> createState() => _PelState();
}

class _PelState extends State<PelangganTab> {
  String q = '', f = 'Semua';

  Future<void> act(String a, Rec c) async {
    switch (a) {
      case 'bayar':
        final r = await sheet(context, BayarForm(c));
        if (r is Map<String, dynamic> && mounted) {
          previewPdf(context, 'Kwitansi_${c.s('id')}', () => buildKwitansi(Rec(r['trx']), c));
        }
        break;
      case 'nota':
        final trx = store.transaksi.where((t) => t.s('pelanggan_id') == c.s('id') && t.s('jenis') == 'Pasang Baru');
        final paid = trx.fold<num>(0, (a, t) => a + t.n('nominal'));
        final metode = trx.isEmpty ? 'Belum Dibayar' : trx.first.s('metode');
        previewPdf(context, 'Nota_${c.s('id')}', () => buildNota(c, paid, metode));
        break;
      case 'upgrade':
        await sheet(context, UpgradeForm(c));
        break;
      case 'gangguan':
        await sheet(context, GangguanForm(c));
        break;
      case 'berhenti':
        await sheet(context, BerhentiForm(c));
        break;
      case 'ambil':
        final yes = await confirm(context, 'Material sudah diambil?',
            'ONT, STB dan dropcore akan dikembalikan ke stok gudang, lalu data pelanggan ${c.s('nama')} dihapus.');
        if (!yes || !mounted) return;
        final ops = <Map<String, dynamic>>[];
        if (c.s('ont_id').isNotEmpty) ops.add(adj(c.s('ont_id'), 1));
        if (c.s('stb_id').isNotEmpty) ops.add(adj(c.s('stb_id'), 1));
        if (c.s('fo_id').isNotEmpty && c.n('dropcore') > 0) ops.add(adj(c.s('fo_id'), c.n('dropcore')));
        final pen = store.penarikan
            .where((p) => p.s('pelanggan_id') == c.s('id') && p.s('status') == 'Dijadwalkan')
            .firstOrNull;
        if (pen != null) ops.add(op('Penarikan', 'upsert', {'id': pen.s('id'), 'status': 'Selesai'}));
        ops.add(op('Pelanggan', 'delete', {'id': c.s('id')}));
        await exec(context, ops, ok: 'Material dikembalikan ke stok');
        break;
    }
  }

  Widget card(Rec c) {
    final bulan = c.i('bulan_tunggak');
    final lunas = bulan == 0;
    final menunggu = c.s('aktif') == 'Menunggu Penarikan';
    return Panel(
      onTap: () => act('bayar', c),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          backgroundColor: (lunas ? C.emerald : C.rose).withValues(alpha: .18),
          child: Icon(lunas ? Icons.check : Icons.priority_high, color: lunas ? C.emerald : C.rose),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.s('nama')}  (${c.s('id')})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(alamat(c), style: const TextStyle(color: C.slate, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              tag(c.s('paket').isEmpty ? '-' : c.s('paket'), C.cyan),
              tag(lunas ? 'Lunas' : 'Belum Lunas', lunas ? C.emerald : C.rose),
              if (!lunas) tag('Tunggakan ${rpf(bulan * c.n('harga'))}', C.rose),
              if (menunggu) tag('Menunggu penarikan', C.amber),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (a) => act(a, c),
          itemBuilder: (_) => menunggu
              ? const [PopupMenuItem(value: 'ambil', child: Text('Konfirmasi material diambil'))]
              : const [
                  PopupMenuItem(value: 'bayar', child: Text('Pelunasan / Bayar')),
                  PopupMenuItem(value: 'nota', child: Text('Nota Tagihan Pasang Baru')),
                  PopupMenuItem(value: 'upgrade', child: Text('Ganti Paket / Ubah Tagihan')),
                  PopupMenuItem(value: 'gangguan', child: Text('Gangguan / Perbaikan')),
                  PopupMenuItem(value: 'berhenti', child: Text('Berhenti Berlangganan')),
                ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = store.pelanggan.where((c) {
      final hit = '${c.s('id')} ${c.s('nama')} ${c.s('kampung')} ${c.s('hp')}'.toLowerCase().contains(q.toLowerCase());
      final lunas = c.i('bulan_tunggak') == 0;
      return hit && (f == 'Semua' || (f == 'Lunas') == lunas);
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => q = v),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Cari nama / ID / kampung', border: OutlineInputBorder()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final x in ['Semua', 'Belum Lunas', 'Lunas'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(x), selected: f == x, onSelected: (_) => setState(() => f = x)),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: list.isEmpty
              ? ListView(children: const [SizedBox(height: 180), Center(child: Text('Belum ada data pelanggan'))])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: list.length,
                  itemBuilder: (_, i) => card(list[i]),
                ),
        ),
      ),
    ]);
  }
}

// ---------- Form Pasang Baru ----------
class PasangBaruForm extends StatefulWidget {
  const PasangBaruForm({super.key});
  @override
  State<PasangBaruForm> createState() => _PBState();
}

class _PBState extends State<PasangBaruForm> with Submit<PasangBaruForm> {
  final t = {
    for (final k in ['id', 'nama', 'nik', 'hp', 'rtrw', 'kampung', 'kec', 'kab', 'koor', 'sn', 'teknisi', 'admin'])
      k: _c(),
  }..addAll({'drop': _c('0'), 'patch': _c('0'), 'biaya': _c('0'), 'bulan': _c('1')});
  String? paketId, ontId, foId, stbId;
  String metode = 'Belum Dibayar';

  @override
  void dispose() {
    for (final c in t.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    final p = find(store.paket, paketId);
    if (t['nama']!.text.trim().isEmpty || p == null) {
      toast(context, 'Nama dan paket wajib diisi');
      return;
    }
    final id = t['id']!.text.trim().isEmpty ? nextCustId() : t['id']!.text.trim();
    if (find(store.pelanggan, id) != null) {
      toast(context, 'ID pelanggan $id sudah dipakai');
      return;
    }
    final m = pn(t['drop']!);
    final pc = pn(t['patch']!).toInt();
    final bulan = pn(t['bulan']!).toInt();
    final biaya = pn(t['biaya']!);
    final fo = find(store.stok, foId);
    final ont = find(store.stok, ontId);
    final stb = p.s('bundling') == 'Ya' ? find(store.stok, stbId) : null;
    if (m > 0 && (fo == null || fo.n('jumlah') < m)) {
      toast(context, 'Stok kabel FO tidak cukup / belum dipilih');
      return;
    }
    Rec? pat;
    if (pc > 0) {
      pat = store.stok.where((s) => s.s('jenis').toLowerCase() == 'patchcore' && s.n('jumlah') >= pc).firstOrNull;
      if (pat == null) {
        toast(context, 'Stok patchcore tidak cukup');
        return;
      }
    }
    final now = ymd(DateTime.now());
    final cust = <String, dynamic>{
      'id': id,
      'nama': t['nama']!.text.trim(),
      'nik': t['nik']!.text.trim(),
      'hp': t['hp']!.text.trim(),
      'rtrw': t['rtrw']!.text.trim(),
      'kampung': t['kampung']!.text.trim(),
      'kecamatan': t['kec']!.text.trim(),
      'kabupaten': t['kab']!.text.trim(),
      'koordinat': t['koor']!.text.trim(),
      'paket': paketLabel(p),
      'paket_id': p.s('id'),
      'harga': p.n('harga'),
      'ont': ont == null ? '' : stokName(ont),
      'ont_id': ont?.s('id') ?? '',
      'ont_sn': t['sn']!.text.trim(),
      'dropcore': m,
      'fo_id': fo?.s('id') ?? '',
      'patchcore': pc,
      'stb': stb == null ? '' : stokName(stb),
      'stb_id': stb?.s('id') ?? '',
      'teknisi': t['teknisi']!.text.trim(),
      'biaya_pasang': biaya,
      'metode_pasang': metode,
      'tgl_pasang': now,
      'bulan_tunggak': bulan,
      'tunggakan': bulan * p.n('harga'),
      'status': bulan == 0 ? 'Lunas' : 'Belum Lunas',
      'aktif': 'Aktif',
    };
    final ops = <Map<String, dynamic>>[op('Pelanggan', 'upsert', cust)];
    if (ont != null) ops.add(adj(ont.s('id'), -1));
    if (m > 0) ops.add(adj(fo!.s('id'), -m));
    if (pat != null) ops.add(adj(pat.s('id'), -pc));
    if (stb != null) ops.add(adj(stb.s('id'), -1));
    ops.add(op('Material', 'upsert', {
      'id': newId('M'),
      'tgl': now,
      'pelanggan_id': id,
      'nama': cust['nama'],
      'ont': cust['ont'],
      'ont_sn': cust['ont_sn'],
      'dropcore': m,
      'patchcore': pc,
      'stb': cust['stb'],
      'teknisi': cust['teknisi'],
      'jenis': 'Pasang Baru',
    }));
    num paid = 0;
    if (metode != 'Belum Dibayar' && biaya > 0) {
      paid = biaya;
      ops.add(op('Transaksi', 'upsert', {
        'id': newId('T'),
        'tgl': now,
        'no_dokumen': nextDoc('NT'),
        'pelanggan_id': id,
        'nama': cust['nama'],
        'paket': cust['paket'],
        'bulan': 0,
        'metode': metode,
        'admin': t['admin']!.text.trim(),
        'nominal': biaya,
        'jenis': 'Pasang Baru',
        'sisa_tunggakan': 0,
      }));
    }
    go(ops, <String, dynamic>{'id': id, 'cust': cust, 'paid': paid, 'metode': metode});
  }

  @override
  Widget build(BuildContext context) {
    final p = find(store.paket, paketId);
    return body('Pasang Baru', [
      tf(t['id']!, 'ID Pelanggan (kosongkan = otomatis)'),
      tf(t['nama']!, 'Nama'),
      tf(t['nik']!, 'NIK', kb: TextInputType.number),
      tf(t['hp']!, 'No HP / WhatsApp', kb: TextInputType.phone),
      tf(t['rtrw']!, 'RT/RW', hint: '001/002'),
      tf(t['kampung']!, 'Kampung'),
      tf(t['kec']!, 'Kecamatan'),
      tf(t['kab']!, 'Kabupaten'),
      tf(t['koor']!, 'Titik koordinat', hint: '-7.3274, 108.2207'),
      dd('Paket internet', paketId, {for (final x in store.paket) x.s('id'): '${paketLabel(x)} - ${rpf(x.n('harga'))}'},
          (v) => setState(() => paketId = v)),
      tf(t['bulan']!, 'Jumlah bulan tagihan awal', kb: TextInputType.number),
      dd('Perangkat ONT (dari stok)', ontId, stokItems('ONT'), (v) => setState(() => ontId = v)),
      tf(t['sn']!, 'Serial No ONT'),
      dd('Kabel Dropcore / FO (dari stok)', foId, stokItems('FO'), (v) => setState(() => foId = v)),
      tf(t['drop']!, 'Pemakaian Dropcore (meter)', kb: numKb),
      tf(t['patch']!, 'Pemakaian Patchcore (pcs)', kb: TextInputType.number),
      if (p != null && p.s('bundling') == 'Ya')
        dd('STB (paket bundling)', stbId, stokItems('STB'), (v) => setState(() => stbId = v)),
      tf(t['teknisi']!, 'Nama teknisi'),
      tf(t['biaya']!, 'Biaya pasang baru (Rp)', kb: numKb),
      dd('Metode pembayaran', metode, lst(Cfg.metodePasang), (v) => setState(() => metode = v!)),
      payHint(metode),
      if (metode != 'Belum Dibayar') tf(t['admin']!, 'Petugas penerima pembayaran'),
      btn('Simpan & Buat Nota', save),
    ]);
  }
}

// ---------- Form Pelunasan ----------
class BayarForm extends StatefulWidget {
  final Rec c;
  const BayarForm(this.c, {super.key});
  @override
  State<BayarForm> createState() => _BayarState();
}

class _BayarState extends State<BayarForm> with Submit<BayarForm> {
  int bulan = 1;
  String metode = 'Tunai';
  final admin = _c();

  @override
  void dispose() {
    admin.dispose();
    super.dispose();
  }

  void save() {
    final c = widget.c;
    final tung = c.i('bulan_tunggak');
    final harga = c.n('harga');
    final sisa = tung - bulan;
    final trx = <String, dynamic>{
      'id': newId('T'),
      'tgl': ymd(DateTime.now()),
      'no_dokumen': nextDoc('KW'),
      'pelanggan_id': c.s('id'),
      'nama': c.s('nama'),
      'paket': c.s('paket'),
      'bulan': bulan,
      'metode': metode,
      'admin': admin.text.trim(),
      'nominal': harga * bulan,
      'jenis': 'Pelunasan',
      'sisa_tunggakan': sisa * harga,
    };
    go([
      op('Pelanggan', 'upsert', {
        'id': c.s('id'),
        'bulan_tunggak': sisa,
        'tunggakan': sisa * harga,
        'status': sisa == 0 ? 'Lunas' : 'Belum Lunas',
      }),
      op('Transaksi', 'upsert', trx),
    ], <String, dynamic>{'trx': trx});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tung = c.i('bulan_tunggak');
    final harga = c.n('harga');
    return body('Pelunasan - ${c.s('nama')}', [
      Text('ID ${c.s('id')} | ${c.s('paket')}\nTunggakan: $tung bulan (${rpf(tung * harga)})'),
      const SizedBox(height: 14),
      if (tung == 0)
        const Text('Pelanggan ini tidak memiliki tunggakan.', style: TextStyle(color: C.emerald))
      else ...[
        dd('Jumlah bulan dibayar', '$bulan', {for (var i = 1; i <= tung; i++) '$i': '$i bulan'},
            (v) => setState(() => bulan = int.parse(v!))),
        dd('Metode bayar', metode, lst(Cfg.metodeBayar), (v) => setState(() => metode = v!)),
        payHint(metode),
        tf(admin, 'Nama petugas / kasir penerima'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Total bayar: ${rpf(harga * bulan)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: C.emerald)),
        ),
        btn('Konfirmasi Pelunasan', save),
      ],
    ]);
  }
}

// ---------- Ganti Paket / Ubah Tagihan ----------
class UpgradeForm extends StatefulWidget {
  final Rec c;
  const UpgradeForm(this.c, {super.key});
  @override
  State<UpgradeForm> createState() => _UpState();
}

class _UpState extends State<UpgradeForm> with Submit<UpgradeForm> {
  String? paketId;
  final bulan = _c();
  bool lunas = false;

  @override
  void initState() {
    super.initState();
    final c = widget.c;
    paketId = find(store.paket, c.s('paket_id'))?.s('id') ??
        store.paket.where((p) => paketLabel(p) == c.s('paket')).firstOrNull?.s('id');
    bulan.text = '${c.i('bulan_tunggak')}';
  }

  @override
  void dispose() {
    bulan.dispose();
    super.dispose();
  }

  void save() {
    final p = find(store.paket, paketId);
    if (p == null) {
      toast(context, 'Pilih paket');
      return;
    }
    final b = lunas ? 0 : pn(bulan).toInt();
    go([
      op('Pelanggan', 'upsert', {
        'id': widget.c.s('id'),
        'paket': paketLabel(p),
        'paket_id': p.s('id'),
        'harga': p.n('harga'),
        'bulan_tunggak': b,
        'tunggakan': b * p.n('harga'),
        'status': b == 0 ? 'Lunas' : 'Belum Lunas',
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => body('Ganti Paket / Ubah Tagihan', [
        Text('${widget.c.s('nama')} (${widget.c.s('id')})'),
        const SizedBox(height: 12),
        dd('Paket', paketId, {for (final x in store.paket) x.s('id'): '${paketLabel(x)} - ${rpf(x.n('harga'))}'},
            (v) => setState(() => paketId = v)),
        tf(bulan, 'Jumlah bulan tunggakan', kb: TextInputType.number, en: !lunas),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tandai Lunas (tunggakan 0)'),
          value: lunas,
          onChanged: (v) => setState(() => lunas = v),
        ),
        btn('Simpan', save),
      ]);
}

// ---------- Gangguan / Perbaikan ----------
class GangguanForm extends StatefulWidget {
  final Rec c;
  const GangguanForm(this.c, {super.key});
  @override
  State<GangguanForm> createState() => _GgState();
}

class _GgState extends State<GangguanForm> with Submit<GangguanForm> {
  late final sn = _c(widget.c.s('ont_sn'));
  final teknisi = _c(), catatan = _c(), drop = _c('0'), patch = _c('0');
  String jenis = 'Redaman';
  String? ontId, foId;

  @override
  void dispose() {
    for (final c in [sn, teknisi, catatan, drop, patch]) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    final c = widget.c;
    final m = pn(drop);
    final pc = pn(patch).toInt();
    final fo = find(store.stok, foId);
    final ont = find(store.stok, ontId);
    if (teknisi.text.trim().isEmpty) {
      toast(context, 'Isi nama teknisi');
      return;
    }
    if (m > 0 && (fo == null || fo.n('jumlah') < m)) {
      toast(context, 'Stok kabel FO tidak cukup / belum dipilih');
      return;
    }
    Rec? pat;
    if (pc > 0) {
      pat = store.stok.where((s) => s.s('jenis').toLowerCase() == 'patchcore' && s.n('jumlah') >= pc).firstOrNull;
      if (pat == null) {
        toast(context, 'Stok patchcore tidak cukup');
        return;
      }
    }
    final now = ymd(DateTime.now());
    final ops = <Map<String, dynamic>>[
      op('Gangguan', 'upsert', {
        'id': newId('G'),
        'tgl': now,
        'pelanggan_id': c.s('id'),
        'nama': c.s('nama'),
        'sn_ont': sn.text.trim(),
        'jenis': jenis,
        'teknisi': teknisi.text.trim(),
        'ganti_ont': ont == null ? '' : stokName(ont),
        'catatan': catatan.text.trim(),
      }),
      op('Material', 'upsert', {
        'id': newId('M'),
        'tgl': now,
        'pelanggan_id': c.s('id'),
        'nama': c.s('nama'),
        'ont': ont == null ? '' : stokName(ont),
        'ont_sn': sn.text.trim(),
        'dropcore': m,
        'patchcore': pc,
        'stb': '',
        'teknisi': teknisi.text.trim(),
        'jenis': 'Perbaikan',
      }),
    ];
    if (ont != null) {
      ops.add(adj(ont.s('id'), -1));
      ops.add(op('Pelanggan', 'upsert',
          {'id': c.s('id'), 'ont': stokName(ont), 'ont_id': ont.s('id'), 'ont_sn': sn.text.trim()}));
    } else {
      ops.add(op('Pelanggan', 'upsert', {'id': c.s('id'), 'ont_sn': sn.text.trim()}));
    }
    if (m > 0) ops.add(adj(fo!.s('id'), -m));
    if (pat != null) ops.add(adj(pat.s('id'), -pc));
    go(ops);
  }

  @override
  Widget build(BuildContext context) => body('Gangguan - ${widget.c.s('nama')}', [
        tf(sn, 'Serial Number (SN) ONT', hint: 'isi SN baru bila ONT diganti'),
        dd('Jenis gangguan', jenis, lst(['Redaman', 'LOS', 'Lainnya']), (v) => setState(() => jenis = v!)),
        tf(teknisi, 'Teknisi penanggung jawab'),
        tf(catatan, 'Catatan', lines: 2),
        const Divider(),
        const Text('Penggantian material (opsional, memotong stok)', style: TextStyle(color: C.slate)),
        const SizedBox(height: 10),
        dd('Ganti ONT dengan', ontId, stokItems('ONT'), (v) => setState(() => ontId = v)),
        dd('Kabel FO tambahan', foId, stokItems('FO'), (v) => setState(() => foId = v)),
        tf(drop, 'Dropcore terpakai (meter)', kb: numKb),
        tf(patch, 'Patchcore terpakai (pcs)', kb: TextInputType.number),
        btn('Simpan Laporan Gangguan', save),
      ]);
}

// ---------- Berhenti Berlangganan ----------
class BerhentiForm extends StatefulWidget {
  final Rec c;
  const BerhentiForm(this.c, {super.key});
  @override
  State<BerhentiForm> createState() => _BhState();
}

class _BhState extends State<BerhentiForm> with Submit<BerhentiForm> {
  final petugas = _c();
  DateTime tgl = DateTime.now().add(const Duration(days: 1));

  @override
  void dispose() {
    petugas.dispose();
    super.dispose();
  }

  void save() {
    final c = widget.c;
    if (petugas.text.trim().isEmpty) {
      toast(context, 'Pilih / isi nama petugas penarikan');
      return;
    }
    go([
      op('Pelanggan', 'upsert', {'id': c.s('id'), 'aktif': 'Menunggu Penarikan'}),
      op('Penarikan', 'upsert', {
        'id': newId('P'),
        'tgl_jadwal': ymd(tgl),
        'pelanggan_id': c.s('id'),
        'nama': c.s('nama'),
        'ont': c.s('ont'),
        'ont_sn': c.s('ont_sn'),
        'stb': c.s('stb'),
        'dropcore': c.n('dropcore'),
        'petugas': petugas.text.trim(),
        'tunggakan': c.i('bulan_tunggak') * c.n('harga'),
        'status': 'Dijadwalkan',
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tung = c.i('bulan_tunggak') * c.n('harga');
    return body('Berhenti Berlangganan', [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.s('nama')} (${c.s('id')})', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('ONT: ${c.s('ont').isEmpty ? '-' : c.s('ont')}  SN: ${c.s('ont_sn').isEmpty ? '-' : c.s('ont_sn')}'),
          if (c.s('stb').isNotEmpty) Text('STB: ${c.s('stb')}'),
          Text('Dropcore terpasang: ${fmtN(c.n('dropcore'))} m'),
          const SizedBox(height: 6),
          Text('Sisa tunggakan: ${rpf(tung)}', style: TextStyle(color: tung > 0 ? C.rose : C.emerald, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 12),
      tf(petugas, 'Petugas yang mengambil material'),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Jadwal penarikan: ${dmy(ymd(tgl))}'),
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: tgl,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) setState(() => tgl = d);
        },
      ),
      const SizedBox(height: 12),
      const Text('Setelah material diambil, pilih menu "Konfirmasi material diambil" pada pelanggan ini '
          'untuk mengembalikan ONT, STB dan dropcore ke stok.',
          style: TextStyle(color: C.slate, fontSize: 12)),
      const SizedBox(height: 12),
      btn('Jadwalkan Penarikan', save),
    ]);
  }
}

// ------------------------------------------------------------
//  TAB 2 : PENGELUARAN
// ------------------------------------------------------------
class PengeluaranTab extends StatelessWidget {
  const PengeluaranTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = [...store.pengeluaran]..sort((a, b) => b.s('tgl').compareTo(a.s('tgl')));
    final total = l.fold<num>(0, (a, e) => a + e.n('total'));
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        Row(children: [
          Expanded(child: Metric('Total Pengeluaran (semua)', rpf(total), C.rose, Icons.payments)),
          Expanded(child: Metric('Jumlah Transaksi', '${l.length}', C.cyan, Icons.receipt)),
        ]),
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Belum ada pengeluaran'))),
        for (final e in l)
          Panel(
            onTap: () => sheet(context, ExpenseForm(e: e)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.s('keterangan').isEmpty ? e.s('kategori') : e.s('keterangan'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    tag(e.s('kategori'), C.amber),
                    if (e.s('jenis_barang').isNotEmpty) tag(e.s('jenis_barang'), C.cyan),
                    Text(dmy(e.s('tgl')), style: const TextStyle(color: C.slate, fontSize: 12)),
                  ]),
                ]),
              ),
              Text(rpf(e.n('total')), style: const TextStyle(color: C.rose, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: C.slate),
                onPressed: () async {
                  final stokId = e.s('stok_id');
                  final yes = await confirm(context, 'Hapus pengeluaran?',
                      'Data akan dihapus dari Spreadsheet.${stokId.isNotEmpty ? ' Stok hasil pembelian ini ikut dikurangi.' : ''}');
                  if (!yes || !context.mounted) return;
                  await exec(context, [
                    if (stokId.isNotEmpty && e.n('qty_stok') > 0) adj(stokId, -e.n('qty_stok')),
                    op('Pengeluaran', 'delete', {'id': e.s('id')}),
                  ], ok: 'Pengeluaran dihapus');
                },
              ),
            ]),
          ),
      ]),
    );
  }
}

class ExpenseForm extends StatefulWidget {
  final Rec? e;
  const ExpenseForm({this.e, super.key});
  @override
  State<ExpenseForm> createState() => _ExpState();
}

class _ExpState extends State<ExpenseForm> with Submit<ExpenseForm> {
  late DateTime tgl;
  String kat = Cfg.kategori.first, jenis = 'ONT';
  final ket = _c(), merk = _c(), harga = _c(), jml = _c('1'), core = _c('12'), roll = _c('1'), meter = _c('1000'), nominal = _c();

  @override
  void initState() {
    super.initState();
    final e = widget.e;
    tgl = DateTime.tryParse(e?.s('tgl') ?? '') ?? DateTime.now();
    if (e != null) {
      kat = Cfg.kategori.contains(e.s('kategori')) ? e.s('kategori') : Cfg.kategori.first;
      jenis = Cfg.jenisBarang.contains(e.s('jenis_barang')) ? e.s('jenis_barang') : 'ONT';
      ket.text = e.s('keterangan');
      merk.text = e.s('merk');
      harga.text = e.s('harga');
      if (e.s('jumlah').isNotEmpty) jml.text = e.s('jumlah');
      if (e.s('core').isNotEmpty) core.text = e.s('core');
      if (e.s('roll').isNotEmpty) roll.text = e.s('roll');
      if (e.s('meter_roll').isNotEmpty) meter.text = e.s('meter_roll');
      nominal.text = e.s('total');
    }
  }

  @override
  void dispose() {
    for (final c in [ket, merk, harga, jml, core, roll, meter, nominal]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get isAset => kat == 'Belanja Aset';
  bool get isFo => isAset && jenis == 'FO';
  num get total => isFo ? pn(harga) * pn(roll) : (isAset ? pn(harga) * pn(jml) : pn(nominal));

  void save() {
    if (total <= 0) {
      toast(context, 'Nominal harus lebih dari 0');
      return;
    }
    final e = widget.e;
    final ops = <Map<String, dynamic>>[];
    String stokId = '';
    num qty = 0;
    String mk = merk.text.trim();
    if (isAset) {
      qty = isFo ? pn(roll) * pn(meter) : pn(jml);
      mk = isFo ? '${pn(core).toInt()} Core' : mk;
      if (e == null || e.s('stok_id').isEmpty) {
        final ex = store.stok
            .where((s) => s.s('jenis').toLowerCase() == jenis.toLowerCase() && s.s('merk').toLowerCase() == mk.toLowerCase())
            .firstOrNull;
        if (ex != null) {
          stokId = ex.s('id');
          ops.add(adj(stokId, qty));
        } else {
          stokId = newId('S');
          ops.add(op('Stok', 'upsert', {
            'id': stokId,
            'nama': isFo ? 'Kabel FO $mk' : '$jenis $mk'.trim(),
            'jenis': jenis,
            'merk': mk,
            'jumlah': qty,
            'satuan': isFo ? 'm' : 'pcs',
            'harga': isFo ? (pn(meter) > 0 ? pn(harga) / pn(meter) : 0) : pn(harga),
          }));
        }
      } else {
        stokId = e.s('stok_id');
        final delta = qty - e.n('qty_stok');
        if (delta != 0) ops.add(adj(stokId, delta));
      }
    }
    ops.add(op('Pengeluaran', 'upsert', {
      'id': e?.s('id') ?? newId('E'),
      'tgl': ymd(tgl),
      'kategori': kat,
      'keterangan': ket.text.trim().isEmpty && isAset ? 'Pembelian $jenis $mk'.trim() : ket.text.trim(),
      'jenis_barang': isAset ? jenis : '',
      'merk': isAset ? mk : '',
      'harga': isAset ? pn(harga) : 0,
      'jumlah': isAset ? (isFo ? pn(roll) : pn(jml)) : 0,
      'core': isFo ? pn(core) : '',
      'roll': isFo ? pn(roll) : '',
      'meter_roll': isFo ? pn(meter) : '',
      'total': total,
      'stok_id': stokId,
      'qty_stok': qty,
    }));
    go(ops);
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.e != null && widget.e!.s('stok_id').isNotEmpty;
    return body(widget.e == null ? 'Tambah Pengeluaran' : 'Edit Pengeluaran', [
      OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today),
        label: Text('Tanggal: ${dmy(ymd(tgl))}'),
        onPressed: () async {
          final d = await showDatePicker(
              context: context, initialDate: tgl, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) setState(() => tgl = d);
        },
      ),
      const SizedBox(height: 12),
      dd('Kategori', kat, lst(Cfg.kategori), (v) => setState(() => kat = v!), en: !locked),
      tf(ket, 'Keterangan'),
      if (isAset) ...[
        dd('Jenis barang', jenis, lst(Cfg.jenisBarang), (v) => setState(() => jenis = v!), en: !locked),
        if (isFo)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kalkulator Pembelian Kabel Fiber Optik (FO)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              tf(core, 'Banyak core', kb: TextInputType.number, ch: (_) => setState(() {})),
              tf(roll, 'Jumlah roll', kb: TextInputType.number, ch: (_) => setState(() {})),
              tf(meter, 'Meter per roll', kb: numKb, ch: (_) => setState(() {})),
              tf(harga, 'Harga per roll (Rp)', kb: numKb, ch: (_) => setState(() {})),
              Text('Total panjang masuk stok: ${fmtN(pn(roll) * pn(meter))} meter',
                  style: const TextStyle(color: C.cyan, fontWeight: FontWeight.w600)),
            ]),
          )
        else ...[
          tf(merk, jenis == 'ONT' ? 'Merk ONT' : 'Merk / Tipe $jenis', en: !locked),
          tf(harga, 'Harga satuan (Rp)', kb: numKb, ch: (_) => setState(() {})),
          tf(jml, 'Jumlah $jenis', kb: TextInputType.number, ch: (_) => setState(() {})),
        ],
      ] else
        tf(nominal, 'Nominal (Rp)', kb: numKb, ch: (_) => setState(() {})),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Total: ${rpf(total)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: C.rose)),
      ),
      if (isAset)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Belanja Aset otomatis menambah / membuat item di Stok Gudang.',
              style: TextStyle(color: C.slate, fontSize: 12)),
        ),
      btn('Simpan', save),
    ]);
  }
}

// ------------------------------------------------------------
//  TAB 3 : STOK GUDANG
// ------------------------------------------------------------
class StokTab extends StatelessWidget {
  const StokTab({super.key});
  @override
  Widget build(BuildContext context) {
    final l = [...store.stok]..sort((a, b) => a.s('jenis').compareTo(b.s('jenis')));
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Stok masih kosong'))),
        for (final s in l)
          Builder(builder: (context) {
            final low = s.n('jumlah') <= (s.s('satuan') == 'm' ? 100 : 3);
            return Panel(
              onTap: () => sheet(context, StokForm(e: s)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.s('nama').isEmpty ? stokName(s) : s.s('nama'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [
                      tag(s.s('jenis'), C.cyan),
                      if (s.s('merk').isNotEmpty) tag(s.s('merk'), C.slate),
                      if (low) tag('Stok menipis', C.rose),
                    ]),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtN(s.n('jumlah')),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: low ? C.rose : C.emerald)),
                  Text(s.s('satuan'), style: const TextStyle(color: C.slate, fontSize: 12)),
                ]),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: C.slate),
                  onPressed: () async {
                    final yes = await confirm(context, 'Hapus item stok?', '${s.s('nama')} akan dihapus dari daftar stok.');
                    if (yes && context.mounted) {
                      await exec(context, [op('Stok', 'delete', {'id': s.s('id')})], ok: 'Item stok dihapus');
                    }
                  },
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

class StokForm extends StatefulWidget {
  final Rec? e;
  const StokForm({this.e, super.key});
  @override
  State<StokForm> createState() => _StokState();
}

class _StokState extends State<StokForm> with Submit<StokForm> {
  String jenis = 'ONT';
  final nama = _c(), merk = _c(), jml = _c('0'), sat = _c('pcs'), harga = _c('0');

  @override
  void initState() {
    super.initState();
    final e = widget.e;
    if (e != null) {
      jenis = Cfg.jenisBarang.contains(e.s('jenis')) ? e.s('jenis') : 'Aksesoris';
      nama.text = e.s('nama');
      merk.text = e.s('merk');
      jml.text = e.s('jumlah');
      sat.text = e.s('satuan');
      harga.text = e.s('harga');
    }
  }

  @override
  void dispose() {
    for (final c in [nama, merk, jml, sat, harga]) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    final n = nama.text.trim().isEmpty ? '$jenis ${merk.text.trim()}'.trim() : nama.text.trim();
    go([
      op('Stok', 'upsert', {
        'id': widget.e?.s('id') ?? newId('S'),
        'nama': n,
        'jenis': jenis,
        'merk': merk.text.trim(),
        'jumlah': pn(jml),
        'satuan': sat.text.trim().isEmpty ? 'pcs' : sat.text.trim(),
        'harga': pn(harga),
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => body(widget.e == null ? 'Tambah Stok' : 'Edit Stok', [
        dd('Jenis barang', jenis, lst(Cfg.jenisBarang), (v) {
          setState(() {
            jenis = v!;
            if (widget.e == null) sat.text = jenis == 'FO' ? 'm' : 'pcs';
          });
        }),
        tf(merk, 'Merk / Tipe'),
        tf(nama, 'Nama barang (opsional)'),
        tf(jml, 'Jumlah', kb: numKb),
        tf(sat, 'Satuan (pcs / m)'),
        tf(harga, 'Harga satuan (Rp)', kb: numKb),
        btn('Simpan', save),
      ]);
}

// ------------------------------------------------------------
//  TAB 4 : PAKET INTERNET
// ------------------------------------------------------------
class PaketTab extends StatelessWidget {
  const PaketTab({super.key});
  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(padding: const EdgeInsets.only(bottom: 90, top: 6), children: [
          if (store.paket.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Belum ada paket'))),
          for (final p in store.paket)
            Panel(
              onTap: () => sheet(context, PaketForm(e: p)),
              child: Row(children: [
                const CircleAvatar(backgroundColor: Color(0x2622D3EE), child: Icon(Icons.wifi, color: C.cyan)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(paketLabel(p), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [
                      tag(rpf(p.n('harga')), C.emerald),
                      if (p.s('bundling') == 'Ya') tag('Bundling STB', C.amber),
                    ]),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: C.slate),
                  onPressed: () async {
                    final yes = await confirm(context, 'Hapus paket?', '${paketLabel(p)} akan dihapus dari daftar paket.');
                    if (yes && context.mounted) {
                      await exec(context, [op('Paket', 'delete', {'id': p.s('id')})], ok: 'Paket dihapus');
                    }
                  },
                ),
              ]),
            ),
        ]),
      );
}

class PaketForm extends StatefulWidget {
  final Rec? e;
  const PaketForm({this.e, super.key});
  @override
  State<PaketForm> createState() => _PaketState();
}

class _PaketState extends State<PaketForm> with Submit<PaketForm> {
  final nama = _c(), kec = _c(), harga = _c();
  String bundling = 'Tidak';

  @override
  void initState() {
    super.initState();
    final e = widget.e;
    if (e != null) {
      nama.text = e.s('nama');
      kec.text = e.s('kecepatan');
      harga.text = e.s('harga');
      bundling = e.s('bundling') == 'Ya' ? 'Ya' : 'Tidak';
    }
  }

  @override
  void dispose() {
    for (final c in [nama, kec, harga]) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    if (nama.text.trim().isEmpty || pn(harga) <= 0) {
      toast(context, 'Nama paket dan harga wajib diisi');
      return;
    }
    go([
      op('Paket', 'upsert', {
        'id': widget.e?.s('id') ?? newId('PK'),
        'nama': nama.text.trim(),
        'kecepatan': kec.text.trim(),
        'harga': pn(harga),
        'bundling': bundling,
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => body(widget.e == null ? 'Tambah Paket' : 'Edit Paket', [
        tf(nama, 'Nama paket', hint: 'LITE / BASIC'),
        tf(kec, 'Kecepatan (Mbps)', kb: TextInputType.number),
        tf(harga, 'Harga per bulan (Rp, sudah termasuk PPN)', kb: numKb),
        dd('Bundling STB', bundling, lst(['Ya', 'Tidak']), (v) => setState(() => bundling = v!)),
        btn('Simpan', save),
      ]);
}

// ------------------------------------------------------------
//  TAB 5 : KEUANGAN
// ------------------------------------------------------------
class Fin {
  final List<Rec> trx, mat, exp;
  final num income, ppn, piutang, expense;
  Fin(this.trx, this.mat, this.exp, this.income, this.ppn, this.piutang, this.expense);
  num get laba => income - expense;
  Map<String, num> get byKat {
    final r = <String, num>{};
    for (final e in exp) {
      final k = e.s('kategori').isEmpty ? 'Lainnya' : e.s('kategori');
      r[k] = (r[k] ?? 0) + e.n('total');
    }
    return r;
  }
}

Fin calc(bool yearly, int y, int m) {
  bool ok(String t) {
    final d = DateTime.tryParse(t);
    return d != null && d.year == y && (yearly || d.month == m);
  }

  final trx = store.transaksi.where((r) => ok(r.s('tgl'))).toList();
  final mat = store.material.where((r) => ok(r.s('tgl'))).toList();
  final exp = store.pengeluaran.where((r) => ok(r.s('tgl'))).toList();
  final income = trx.fold<num>(0, (a, r) => a + r.n('nominal'));
  final piutang = store.pelanggan.fold<num>(0, (a, c) => a + c.i('bulan_tunggak') * c.n('harga'));
  final expense = exp.fold<num>(0, (a, r) => a + r.n('total'));
  return Fin(trx, mat, exp, income, income * Cfg.ppn / (1 + Cfg.ppn), piutang, expense);
}

class KeuTab extends StatefulWidget {
  const KeuTab({super.key});
  @override
  State<KeuTab> createState() => _KeuState();
}

class _KeuState extends State<KeuTab> {
  bool yearly = false;
  int y = DateTime.now().year, m = DateTime.now().month;

  String get periode => yearly ? 'Tahunan $y' : '${monFull[m - 1]} $y';

  @override
  Widget build(BuildContext context) {
    final f = calc(yearly, y, m);
    final nowY = DateTime.now().year;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(7, 8, 7, 30), children: [
        Panel(
          child: Column(children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Bulanan')),
                ButtonSegment(value: true, label: Text('Tahunan')),
              ],
              selected: {yearly},
              onSelectionChanged: (s) => setState(() => yearly = s.first),
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (!yearly) ...[
                Expanded(
                  child: dd('Bulan', '$m', {for (var i = 1; i <= 12; i++) '$i': monFull[i - 1]},
                      (v) => setState(() => m = int.parse(v!))),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: dd('Tahun', '$y', {for (var i = nowY - 4; i <= nowY + 1; i++) '$i': '$i'},
                    (v) => setState(() => y = int.parse(v!))),
              ),
            ]),
          ]),
        ),
        Row(children: [
          Expanded(child: Metric('Pemasukan Lunas', rpf(f.income), C.emerald, Icons.trending_up)),
          Expanded(child: Metric('Total Piutang', rpf(f.piutang), C.amber, Icons.hourglass_bottom)),
        ]),
        Row(children: [
          Expanded(child: Metric('Pengeluaran', rpf(f.expense), C.rose, Icons.trending_down)),
          Expanded(child: Metric('PPN 11% (dari pemasukan)', rpf(f.ppn), C.cyan, Icons.percent)),
        ]),
        Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: (f.laba >= 0 ? C.emerald : C.rose).withValues(alpha: .15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: f.laba >= 0 ? C.emerald : C.rose),
          ),
          child: Column(children: [
            Text(f.laba >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', style: const TextStyle(color: C.slate)),
            const SizedBox(height: 4),
            Text(rpf(f.laba),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: f.laba >= 0 ? C.emerald : C.rose)),
            Text(periode, style: const TextStyle(color: C.slate, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(5),
          child: FilledButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Cetak / Simpan Laporan PDF'),
            onPressed: () => previewPdf(context, 'Laporan_Keuangan_$periode'.replaceAll(' ', '_'),
                () => buildLaporan(calc(yearly, y, m), yearly, periode)),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------
//  PDF  (Nota, Kwitansi, Laporan)
// ------------------------------------------------------------
const _blue = PdfColor(0.043, 0.435, 0.643);

pw.TextStyle _b([double s = 10, PdfColor? c]) => pw.TextStyle(fontSize: s, fontWeight: pw.FontWeight.bold, color: c);
pw.TextStyle _n([double s = 10, PdfColor? c]) => pw.TextStyle(fontSize: s, color: c);

Future<pw.MemoryImage> _img(String p) async => pw.MemoryImage((await rootBundle.load(p)).buffer.asUint8List());

pw.Widget _hdr(pw.MemoryImage logo) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 2))),
      child: pw.Row(children: [
        pw.Image(logo, width: 48, height: 48),
        pw.SizedBox(width: 10),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(Cfg.company, style: _b(18, _blue)),
          pw.Text(Cfg.tagline, style: _n(9, PdfColors.grey700)),
          pw.Text('${Cfg.address} | WA Support: ${Cfg.wa}', style: _n(8, PdfColors.grey700)),
        ]),
      ]),
    );

pw.Widget _kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 95, child: pw.Text(k, style: _n(9, PdfColors.grey700))),
        pw.Text(': ', style: _n(9)),
        pw.Expanded(child: pw.Text(v.isEmpty ? '-' : v, style: _b(9))),
      ]),
    );

pw.Widget _box(String title, List<pw.Widget> ch) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: _b(10, _blue)),
        pw.SizedBox(height: 4),
        ...ch,
      ]),
    );

pw.Widget _tot(String k, String v, {bool big = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(k, style: big ? _b(11) : _n(10)),
        pw.Text(v, style: big ? _b(12, _blue) : _b(10)),
      ]),
    );

pw.Widget _table(List<String> headers, List<List<String>> rows, {Map<int, pw.Alignment>? align, Map<int, pw.TableColumnWidth>? widths}) =>
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows.isEmpty ? [List.filled(headers.length, '-')] : rows,
      headerStyle: _b(9, PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _blue),
      cellStyle: _n(9),
      cellAlignments: align,
      columnWidths: widths,
      cellPadding: const pw.EdgeInsets.all(5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
    );

pw.Widget _sig(String role, String name) => pw.Column(children: [
      pw.Text(role, style: _n(9)),
      pw.SizedBox(height: 42),
      pw.Text(name.isEmpty ? '-' : name, style: _b(9)),
    ]);

pw.Widget _footer(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Center(child: pw.Text(t, style: _n(8, PdfColors.grey600))),
    );

List<pw.Widget> _items(List<List<String>> rows) => [
      _table(['No', 'Deskripsi Layanan', 'Qty', 'Harga Dasar', 'Subtotal'], rows, align: {
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      }, widths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FixedColumnWidth(48),
        3: const pw.FlexColumnWidth(1.6),
        4: const pw.FlexColumnWidth(1.6),
      }),
    ];

// ---- Kwitansi Pelunasan ----
Future<Uint8List> buildKwitansi(Rec t, Rec c) async {
  final logo = await _img('assets/images/logo.png');
  final total = t.n('nominal');
  final dpp = total / (1 + Cfg.ppn);
  final bln = max(t.i('bulan'), 1);
  final d = DateTime.tryParse(t.s('tgl')) ?? DateTime.now();
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      _hdr(logo),
      pw.SizedBox(height: 12),
      pw.Center(child: pw.Text('KWITANSI PELUNASAN', style: _b(15, _blue))),
      pw.Center(child: pw.Text('No. Dokumen: ${t.s('no_dokumen')}   |   Tanggal: ${d.day} ${monFull[d.month - 1]} ${d.year}', style: _n(9))),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _box('DATA PELANGGAN', [
            _kv('ID Pelanggan', c.s('id')),
            _kv('Nama', c.s('nama')),
            _kv('Alamat', alamat(c)),
            _kv('No WhatsApp', c.s('hp')),
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _box('INFORMASI PELUNASAN', [
            _kv('Metode Bayar', t.s('metode')),
            _kv('Diterima Oleh', t.s('admin')),
            _kv('Sisa Tunggakan', rpf(t.n('sisa_tunggakan'))),
            _kv('Jumlah Bulan', '$bln Bulan'),
            _kv('Status', 'LUNAS'),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      ..._items([
        ['1', '${t.s('paket')}\nLangganan Akses Internet Unlimited Periode ${monFull[d.month - 1]} ${d.year}', '$bln Bln', rpf(dpp / bln), rpf(dpp)],
      ]),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green700, width: 2)),
          child: pw.Text('LUNAS', style: _b(18, PdfColors.green700)),
        ),
        pw.SizedBox(
          width: 230,
          child: pw.Column(children: [
            _tot('Subtotal (Excl. PPN)', rpf(dpp)),
            _tot('PPN 11%', rpf(total - dpp)),
            pw.Divider(),
            _tot('TOTAL DIBAYAR', rpf(total), big: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 28),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _sig('Pelanggan,', c.s('nama')),
        _sig('Finance / Petugas Billing,', t.s('admin')),
      ]),
      _footer('${Cfg.company} Billing System - Nota & Struk Resmi Otomatis'),
    ],
  ));
  return doc.save();
}

// ---- Nota Tagihan Pasang Baru ----
Future<Uint8List> buildNota(Rec c, num paid, String metode) async {
  final logo = await _img('assets/images/logo.png');
  final qris = await _img('assets/images/qris.png');
  final harga = c.n('harga');
  final bln = c.i('bulan_tunggak');
  final biaya = c.n('biaya_pasang');
  final total = biaya + bln * harga;
  final dpp = total / (1 + Cfg.ppn);
  final rows = <List<String>>[];
  if (biaya > 0) {
    rows.add(['${rows.length + 1}', 'Biaya Pemasangan Baru (instalasi)', '1', rpf(biaya / (1 + Cfg.ppn)), rpf(biaya / (1 + Cfg.ppn))]);
  }
  if (bln > 0) {
    rows.add(['${rows.length + 1}', 'Langganan ${c.s('paket')}', '$bln Bln', rpf(harga / (1 + Cfg.ppn)), rpf(bln * harga / (1 + Cfg.ppn))]);
  }
  final d = DateTime.tryParse(c.s('tgl_pasang')) ?? DateTime.now();
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      _hdr(logo),
      pw.SizedBox(height: 12),
      pw.Center(child: pw.Text('NOTA TAGIHAN PEMASANGAN BARU', style: _b(15, _blue))),
      pw.Center(child: pw.Text('Tanggal: ${d.day} ${monFull[d.month - 1]} ${d.year}', style: _n(9))),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _box('DATA PELANGGAN', [
            _kv('ID Pelanggan', c.s('id')),
            _kv('Nama', c.s('nama')),
            _kv('Alamat', alamat(c)),
            _kv('No WhatsApp', c.s('hp')),
            _kv('Koordinat', c.s('koordinat')),
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _box('DETAIL PEMASANGAN', [
            _kv('Paket', c.s('paket')),
            _kv('ONT', c.s('ont')),
            _kv('SN ONT', c.s('ont_sn')),
            _kv('Dropcore', '${fmtN(c.n('dropcore'))} m'),
            _kv('Patchcore', '${c.i('patchcore')} pcs'),
            if (c.s('stb').isNotEmpty) _kv('STB', c.s('stb')),
            _kv('Teknisi', c.s('teknisi')),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      ..._items(rows),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 240,
          child: pw.Column(children: [
            _tot('DPP (Excl. PPN)', rpf(dpp)),
            _tot('PPN 11%', rpf(total - dpp)),
            pw.Divider(),
            _tot('TOTAL TAGIHAN', rpf(total), big: true),
            _tot('Sudah dibayar ($metode)', rpf(paid)),
            _tot('Sisa tagihan', rpf(max(total - paid, 0))),
          ]),
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _box('INFORMASI PEMBAYARAN', [
            pw.Text('Transfer Bank: ${Cfg.bank}', style: _n(9)),
            pw.Text('E-Wallet: ${Cfg.ewallet}', style: _n(9)),
            pw.Text('Atas Nama: ${Cfg.atasNama}', style: _b(9)),
            pw.SizedBox(height: 4),
            pw.Text('Mohon cantumkan ID Pelanggan ${c.s('id')} saat transfer.', style: _n(8, PdfColors.grey700)),
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Column(children: [
          pw.Image(qris, width: 100, height: 100),
          pw.Text('Scan QRIS', style: _n(8)),
        ]),
      ]),
      pw.SizedBox(height: 24),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _sig('Pelanggan,', c.s('nama')),
        _sig('Teknisi / Petugas,', c.s('teknisi')),
      ]),
      _footer('${Cfg.company} Billing System - Nota Otomatis'),
    ],
  ));
  return doc.save();
}

// ---- Laporan Keuangan ----
Future<Uint8List> buildLaporan(Fin f, bool yearly, String periode) async {
  final logo = await _img('assets/images/logo.png');
  final now = DateTime.now();
  pw.Widget sum(String k, String v, String sub, PdfColor col) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: col), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(k, style: _n(8, PdfColors.grey700)),
            pw.Text(v, style: _b(12, col)),
            pw.Text(sub, style: _n(8, PdfColors.grey700)),
          ]),
        ),
      );
  pw.Widget sec(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 5), child: pw.Text(t, style: _b(10, _blue)));

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      _hdr(logo),
      pw.SizedBox(height: 10),
      pw.Text('LAPORAN KEUANGAN & REKAP ${yearly ? 'TAHUNAN' : 'BULANAN'}', style: _b(14, _blue)),
      pw.Text('Periode: $periode | Tanggal Cetak: ${DateFormat('dd/MM/yyyy').format(now)}', style: _n(9)),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        sum('PEMASUKAN (LUNAS)', rpf(f.income), 'PPN 11%: ${rpf(f.ppn)}', PdfColors.green700),
        sum('TOTAL PIUTANG', rpf(f.piutang), 'Tunggakan pelanggan', PdfColors.orange700),
        sum('PENGELUARAN', rpf(f.expense), 'Operasional & aset', PdfColors.red700),
      ]),
      sec('1. RINCIAN PEMASUKAN PELANGGAN (LUNAS)'),
      _table(
        ['Pelanggan (ID)', 'Paket', 'Metode & Admin', 'Nominal'],
        [
          for (final t in f.trx)
            [
              '${t.s('nama')} (${t.s('pelanggan_id')})',
              t.s('paket'),
              '${t.s('metode').isEmpty ? '-' : t.s('metode')} / ${t.s('admin').isEmpty ? '-' : t.s('admin')}',
              rpf(t.n('nominal')),
            ],
        ],
        align: {3: pw.Alignment.centerRight},
      ),
      sec('2. RINCIAN PENGURANGAN / PEMAKAIAN MATERIAL & PERANGKAT'),
      _table(
        ['Pelanggan', 'Material / Perangkat Terpakai', 'Teknisi Bertugas'],
        [
          for (final m in f.mat)
            [
              m.s('nama'),
              'ONT: ${m.s('ont').isEmpty ? '-' : m.s('ont')}, Dropcore: ${fmtN(m.n('dropcore'))}m, Patchcore: ${m.i('patchcore')}pcs'
                  '${m.s('stb').isEmpty ? '' : ', STB: ${m.s('stb')}'}',
              m.s('teknisi'),
            ],
        ],
      ),
      sec('3. REKAP PENGELUARAN OPERASIONAL'),
      _table(
        ['Kategori Pengeluaran', 'Nominal'],
        [for (final e in f.byKat.entries) [e.key, rpf(e.value)]],
        align: {1: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
        child: _tot(f.laba >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', rpf(f.laba), big: true),
      ),
      _footer('${Cfg.company} Billing System - Laporan Otomatis'),
    ],
  ));
  return doc.save();
}
