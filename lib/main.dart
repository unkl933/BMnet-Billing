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
import 'package:url_launcher/url_launcher.dart';

// ------------------------------------------------------------
//  KONFIGURASI  (ubah sesuai data perusahaan)
// ------------------------------------------------------------
class Cfg {
  static const scriptUrl = 'https://script.google.com/macros/s/AKfycbwkQ4HbMaBlE4tVxlIUIfhNTgXgkgmzz-kWF-CHmuMMs1BB95okkMvuntsCFwx_F0M/exec';
  static const company = 'BM Network';
  static const tagline = 'Internet Solution';
  static const address = 'Jl.Kiarajangkung No 04, Sukahening TSM, Jawa Barat ID ';
  static const wa = '+62895-1988-5966';
  static const bank = 'BCA 2801971611';
  static const ewallet = '083827777207 (DANA)';
  static const atasNama = 'IRSYAM AUFAR ZUHDAN';
  static const ppn = 0.11;
  static const kategori = ['Belanja Aset', 'Operasional', 'Gaji Karyawan', 'Hutang', 'Maintenance'];
  static const jenisBarang = ['ONT', 'OLT', 'Mikrotik', 'FO', 'Patchcore', 'STB', 'Selongsong', 'Aksesoris'];
  static const metodeBayar = ['Tunai', 'Transfer BCA', 'QRIS', 'DANA'];
  static const metodePasang = ['Belum Dibayar', 'Tunai', 'QRIS', 'DANA'];
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

// ---- Tiket gangguan: helper ----
String statusTiket(Rec g) => g.s('status').isEmpty ? 'Sudah Diperbaiki' : g.s('status');
bool isOpenTicket(Rec g) => statusTiket(g) == 'Belum Diperbaiki';
String tipeTiket(Rec g) => g.s('tipe').isEmpty ? 'Pelanggan' : g.s('tipe');

/// Pemakaian stok sebuah tiket: {id stok: jumlah}
Map<String, num> matMap(String ont, String fo, num m, String patch, num pc) => {
      if (ont.isNotEmpty) ont: 1,
      if (fo.isNotEmpty && m > 0) fo: m,
      if (patch.isNotEmpty && pc > 0) patch: pc,
    };

/// No tiket otomatis: TKP-20261102-001 (pelanggan) / TKJ-20261102-001 (jalur)
String nextTiket(String tipe) {
  final key = '${tipe == 'Jalur' ? 'TKJ' : 'TKP'}-${DateFormat('yyyyMMdd').format(DateTime.now())}-';
  var mx = 0;
  for (final g in store.gangguan) {
    final n = g.s('no_tiket');
    if (n.startsWith(key)) mx = max(mx, int.tryParse(n.substring(key.length)) ?? 0);
  }
  return '$key${(mx + 1).toString().padLeft(3, '0')}';
}

Future<void> tiketBaru(BuildContext c) async {
  final t = await showModalBottomSheet<String>(
    context: c,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.person, color: C.cyan),
          title: const Text('Gangguan Pelanggan'),
          onTap: () => Navigator.pop(ctx, 'Pelanggan'),
        ),
        ListTile(
          leading: const Icon(Icons.cable, color: C.amber),
          title: const Text('Gangguan Jalur'),
          onTap: () => Navigator.pop(ctx, 'Jalur'),
        ),
      ]),
    ),
  );
  if (t == null || !c.mounted) return;
  final r = await sheet(c, TiketForm(tipe: t));
  if (r is String && c.mounted) toast(c, 'Tiket $r diterbitkan');
}

String paketLabel(Rec p) => p.s('kecepatan').isEmpty ? p.s('nama') : '${p.s('nama')} ${p.s('kecepatan')} Mbps';
String stokName(Rec s) => s.s('merk').isNotEmpty ? s.s('merk') : s.s('nama');
String alamat(Rec c) =>
    '${c.s('kampung')}, RT/RW ${c.s('rtrw')}, Kec. ${c.s('kecamatan')}, ${c.s('kabupaten')}';

Map<String, String> lst(List<String> l) => {for (final x in l) x: x};

Map<String, String> stokItems(String jenis, {bool onlyAvail = true, String? keep}) => {
      for (final s in store.stok)
        if (s.s('jenis').toLowerCase() == jenis.toLowerCase() && (!onlyAvail || s.n('jumlah') > 0 || s.s('id') == keep))
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

class AuthSession {
  static final ValueNotifier<bool> changed = ValueNotifier<bool>(false);
  static String? token;
  static Map<String, dynamic>? user;
  static String? activeRole;
  static List<String> get roles {
    final raw = user?['roles'];
    final values = raw is List ? raw : (user?['role'] == null ? <dynamic>[] : [user!['role']]);
    final out = <String>[];
    for (final value in values) {
      final r = '$value'.trim().toLowerCase();
      if (r.isNotEmpty && !out.contains(r)) out.add(r);
    }
    if (out.isEmpty && user?['role'] != null) out.add('${user!['role']}'.toLowerCase());
    return out;
  }
  static String get role => (activeRole != null && roles.contains(activeRole) ? activeRole! : (roles.isNotEmpty ? roles.first : '')).toLowerCase();
  static String get nama => '${user?['nama'] ?? ''}';
  static bool get loggedIn => token != null && user != null;
  static bool get owner => role == 'owner';
  static bool get admin => role == 'admin';
  static bool get sales => role == 'sales';
  static bool get teknisi => role == 'teknisi';
  static bool get pkl => role == 'pkl';
  static bool get canManageUsers => owner || admin;
  static void setMode(String value) { if (roles.contains(value.toLowerCase())) { activeRole = value.toLowerCase(); changed.value = !changed.value; } }
  static void clear() { token = null; user = null; activeRole = null; changed.value = false; }
}

class Api {
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final r = await post({'action': 'login', 'username': username, 'password': password});
    if (r['ok'] == true) {
      AuthSession.token = '${r['session']}';
      AuthSession.user = Map<String, dynamic>.from(r['user'] as Map);
      AuthSession.activeRole = '${AuthSession.user?['active_role'] ?? (AuthSession.roles.isNotEmpty ? AuthSession.roles.first : '')}'.toLowerCase();
      AuthSession.changed.value = true;
    }
    return r;
  }

  static Future<Map<String, dynamic>> get() async {
    if (!AuthSession.loggedIn) throw 'Silakan login terlebih dahulu.';
    final r = await http.get(Uri.parse('${Cfg.scriptUrl}?action=all&session=${Uri.encodeComponent(AuthSession.token!)}&active_role=${Uri.encodeComponent(AuthSession.role)}'))
        .timeout(const Duration(seconds: 40));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> post(Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(Cfg.scriptUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode({...body, if (AuthSession.loggedIn && body['action'] != 'login') 'active_role': AuthSession.role});
      var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 40)));
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers['location'] != null) {
        res = await http.get(Uri.parse(res.headers['location']!));
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } finally { client.close(); }
  }

  static Future<Map<String, dynamic>> createUser(Map<String, dynamic> user) =>
      post({'action': 'createUser', 'session': AuthSession.token, 'user': user});
  static Future<Map<String, dynamic>> listUsers() =>
      post({'action': 'listUsers', 'session': AuthSession.token});
  static Future<Map<String, dynamic>> setUserStatus(String id, String status) =>
      post({'action': 'setUserStatus', 'session': AuthSession.token, 'user': {'user_id': id, 'status': status}});
  static Future<Map<String, dynamic>> updateUserRoles(String id, List<String> roles) =>
      post({'action': 'updateUserRoles', 'session': AuthSession.token, 'user': {'user_id': id, 'roles': roles}});
  static Future<void> logout() async {
    if (AuthSession.token != null) {
      try { await post({'action': 'logout', 'session': AuthSession.token}); } catch (_) {}
    }
    AuthSession.clear();
  }
}

class Store extends ChangeNotifier {
  List<Rec> pelanggan = [], pengeluaran = [], stok = [], paket = [], transaksi = [], material = [], gangguan = [], penarikan = [];
  bool loading = false;
  String? error;

  List<Rec> _l(Map d, String k) {
    final v = d[k] ?? d[k.toLowerCase()];
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
      final r = await Api.post({'action': 'batch', 'session': AuthSession.token, 'ops': ops});
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
  if (['DANA'].contains(m)) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('$m: ${Cfg.ewallet} a.n. ${Cfg.atasNama}'));
  }
  return const SizedBox.shrink();
}

/// Buka Google Maps ke titik koordinat pelanggan (atau alamat bila koordinat kosong).
Future<void> openMaps(BuildContext c, Rec p) async {
  final raw = p.s('koordinat');
  final koor = raw.replaceAll(RegExp(r'\s'), '');
  Uri uri;
  if (raw.startsWith('http')) {
    uri = Uri.parse(raw); // link Google Maps yang ditempel langsung
  } else {
    final valid = RegExp(r'^-?\d+(\.\d+)?,-?\d+(\.\d+)?$').hasMatch(koor);
    final q = valid
        ? koor
        : Uri.encodeComponent(
            '${p.s('kampung')} ${p.s('kecamatan')} ${p.s('kabupaten')}'.trim().isEmpty
                ? p.s('alamat')
                : '${p.s('kampung')} ${p.s('kecamatan')} ${p.s('kabupaten')}'.trim());
    uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && c.mounted) toast(c, 'Tidak bisa membuka Google Maps');
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
        title: 'BM Network',
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
        home: const AuthGate(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int section = 0, tab = 0;
  static const titles = ['Dashboard', 'Pelanggan', 'Gangguan', 'Pengeluaran', 'Stok Gudang', 'Paket Internet', 'Keuangan', 'Sales'];
  List<int> get visibleTabs => AuthSession.owner || AuthSession.admin ? [0,1,2,3,4,5,6,7] : AuthSession.sales ? [0,1,7] : AuthSession.teknisi ? [0,1,2] : [0,1,2];

  @override
  void initState() {
    super.initState();
    store.refresh();
  }

  Widget? fab(BuildContext c) {
    if (!(AuthSession.owner || AuthSession.admin || AuthSession.sales)) return null;
    switch (tab) {
      case 1:
        return FloatingActionButton.extended(
            onPressed: () => openPasangBaru(c), icon: const Icon(Icons.person_add), label: const Text('Pasang Baru'));
      case 2:
        return FloatingActionButton.extended(
            onPressed: () => tiketBaru(c), icon: const Icon(Icons.add_alert), label: const Text('Tiket Baru'));
      case 3:
        return FloatingActionButton.extended(
            onPressed: () => sheet(c, const ExpenseForm()), icon: const Icon(Icons.add), label: const Text('Pengeluaran'));
      case 4:
        return FloatingActionButton.extended(
            onPressed: () => sheet(c, const StokForm()), icon: const Icon(Icons.add), label: const Text('Stok'));
      case 5:
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
        if (!visibleTabs.contains(tab)) tab = visibleTabs.first;
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
                    if (AuthSession.canManageUsers) IconButton(tooltip: 'Manajemen akun', icon: const Icon(Icons.manage_accounts), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementPage()))),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'logout') { await Api.logout(); if (mounted) setState(() { tab = 0; }); }
                        else if (v.startsWith('mode:')) { AuthSession.setMode(v.substring(5)); if (mounted) setState(() { tab = 0; }); await store.refresh(); }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'profile', enabled: false, child: Text('${AuthSession.nama} • ${AuthSession.roles.join(' + ')}')),
                        if (AuthSession.roles.length > 1) const PopupMenuDivider(),
                        if (AuthSession.roles.length > 1) const PopupMenuItem(value: 'mode_label', enabled: false, child: Text('Ganti mode kerja')),
                        if (AuthSession.roles.length > 1) ...AuthSession.roles.map((r) => PopupMenuItem(value: 'mode:$r', child: Row(children: [Icon(AuthSession.role == r ? Icons.radio_button_checked : Icons.radio_button_off, size: 18), const SizedBox(width: 8), Text(r.toUpperCase())]))),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'logout', child: Text('Logout')),
                      ]),
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
                    const Text('BM Network', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text('Internet Solution', style: TextStyle(color: C.slate)),
                    Text('${AuthSession.nama} • ${AuthSession.roles.join(' + ')} (mode ${AuthSession.role.toUpperCase()})', style: const TextStyle(color: C.emerald, fontSize: 12)),
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
                if (AuthSession.canManageUsers) ListTile(leading: const Icon(Icons.manage_accounts), title: const Text('Manajemen Akun'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementPage())); }),
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
                      // JANGAN pakai const: tab harus ikut rebuild saat store berubah
                      PelangganTab(key: const ValueKey('pel')),
                      GangguanTab(key: const ValueKey('ggn')),
                      PengeluaranTab(key: const ValueKey('peng')),
                      StokTab(key: const ValueKey('stok')),
                      PaketTab(key: const ValueKey('paket')),
                      KeuTab(key: const ValueKey('keu')),
                      SalesTab(key: const ValueKey('sales')),
                    ]),
                  ),
                ]),
          floatingActionButton: billing ? fab(context) : null,
          bottomNavigationBar: billing
              ? BottomNav(
                  index: tab,
                  visibleIndices: visibleTabs,
                  alerts: store.gangguan.where(isOpenTicket).length,
                  onTap: (i) => setState(() => tab = i),
                )
              : null,
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  @override Widget build(BuildContext context) => ValueListenableBuilder<bool>(valueListenable: AuthSession.changed, builder: (context, loggedIn, _) => loggedIn && AuthSession.loggedIn
      ? Shell(key: ValueKey(AuthSession.user?['user_id']))
      : LoginPage(onLogin: () => setState(() {})));
}

class LoginPage extends StatefulWidget {
  final VoidCallback onLogin;
  const LoginPage({super.key, required this.onLogin});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(), password = TextEditingController();
  bool busy = false, obscure = true;
  Future<void> submit() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) { toast(context, 'Username dan password wajib diisi'); return; }
    setState(() => busy = true);
    try {
      final r = await Api.login(username.text.trim(), password.text);
      if (r['ok'] == true) { widget.onLogin(); }
      else if (mounted) toast(context, '${r['error'] ?? 'Login gagal'}');
    } catch (e) { if (mounted) toast(context, 'Gagal login: $e'); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { username.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/images/logo.png', height: 92), const SizedBox(height: 18),
        const Text('BM Network', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const Text('Login ke akun operasional', style: TextStyle(color: C.slate)), const SizedBox(height: 28),
        TextField(controller: username, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
        const SizedBox(height: 12), TextField(controller: password, obscureText: obscure, onSubmitted: (_) => submit(), decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)))),
        const SizedBox(height: 18), SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit, child: busy ? const CircularProgressIndicator() : const Text('LOGIN'))),
      ])))));
}

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override State<UserManagementPage> createState() => _UserManagementPageState();
}
class _UserManagementPageState extends State<UserManagementPage> {
  List users = []; bool loading = true;
  static const allRoles = ['Owner','Admin','Sales','Teknisi','PKL'];
  Future<void> load() async {
    setState(() => loading = true);
    try { final r = await Api.listUsers(); if (r['ok'] == true) users = r['users'] as List; else if (mounted) toast(context, '${r['error']}'); }
    catch(e) { if(mounted) toast(context, '$e'); }
    if(mounted) setState(() => loading = false);
  }
  @override void initState() { super.initState(); load(); }
  Future<List<String>?> chooseRoles({List<String> initial = const ['Sales']}) async {
    final picked = initial.map((e) => e.toLowerCase()).toSet();
    return showDialog<List<String>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setD) => AlertDialog(
      title: const Text('Pilih Multi Role'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [for (final role in allRoles.where((r) => AuthSession.owner || r != 'Owner')) CheckboxListTile(
        dense: true, contentPadding: EdgeInsets.zero, title: Text(role), value: picked.contains(role.toLowerCase()),
        onChanged: (v) => setD(() { if (v == true) picked.add(role.toLowerCase()); else picked.remove(role.toLowerCase()); }),
      )]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')), FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, allRoles.where((r) => picked.contains(r.toLowerCase())).toList()), child: const Text('Simpan Role'))],
    )));
  }
  Future<void> add() async {
    final n=TextEditingController(),u=TextEditingController(),p=TextEditingController();
    final roles = await chooseRoles();
    if (roles == null) { n.dispose();u.dispose();p.dispose(); return; }
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Buat akun pengguna'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[tf(n,'Nama lengkap'),tf(u,'Username'),tf(p,'Password (minimal 8 karakter)'),const SizedBox(height:8),Text('Role: ${roles.join(' + ')}')])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'nama':n.text.trim(),'username':u.text.trim(),'password':p.text,'roles':roles}),child:const Text('Buat akun'))]));
    n.dispose();u.dispose();p.dispose(); if(result==null)return;
    final r=await Api.createUser(result); if(!mounted)return; toast(context,r['ok']==true?'Akun berhasil dibuat':'${r['error']??'Gagal membuat akun'}'); if(r['ok']==true)load();
  }
  Future<void> editRoles(Map u) async {
    final raw = u['roles'];
    final initial = raw is List ? raw.map((e)=>'$e').toList() : ['${u['role'] ?? 'Sales'}'];
    final roles = await chooseRoles(initial: initial);
    if (roles == null) return;
    final r = await Api.updateUserRoles('${u['user_id']}', roles);
    if (!mounted) return;
    toast(context, r['ok']==true ? 'Role pengguna diperbarui' : '${r['error'] ?? 'Gagal memperbarui role'}');
    if (r['ok']==true) load();
  }
  Future<void> toggle(Map u) async {
    final next='${u['status']}'=='Aktif'?'Nonaktif':'Aktif';
    final r=await Api.setUserStatus('${u['user_id']}',next);
    if(!mounted)return;toast(context,r['ok']==true?'Status akun diubah':'${r['error']}');if(r['ok']==true)load();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Manajemen Akun')),
    floatingActionButton:FloatingActionButton.extended(onPressed:add,icon:const Icon(Icons.person_add),label:const Text('Buat Akun')),
    body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.only(bottom:90),children:[
      for(final x in users) Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),child:ListTile(
        leading:CircleAvatar(child:Text('${x['nama']??'?'}'.isNotEmpty?'${x['nama']}'.substring(0,1).toUpperCase():'?')),
        title:Text('${x['nama']}'),
        subtitle:Text('@${x['username']} • ${((x['roles'] is List) ? (x['roles'] as List).join(' + ') : x['role'])} • ${x['status']}'),
        trailing:Wrap(spacing:0, children:[
          IconButton(tooltip:'Atur role',icon:const Icon(Icons.tune),onPressed:()=>editRoles(Map<String,dynamic>.from(x))),
          if (AuthSession.owner || '${x['role']}'.toLowerCase()!='owner') IconButton(tooltip:'Aktif/nonaktif',icon:Icon('${x['status']}'=='Aktif'?Icons.block:Icons.check_circle_outline),onPressed:()=>toggle(Map<String,dynamic>.from(x))),
        ]),
      ))
    ])));
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Image.asset('assets/images/logo.png', height: 110)),
        const SizedBox(height: 12),
        const Center(child: Text('BM Network', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
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
    final gOpen = store.gangguan.where(isOpenTicket).length;
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
      (Icons.report_problem, 'Gangguan', C.rose, () => onGo(2)),
      (Icons.payments, 'Pengeluaran', C.rose, () => onGo(3)),
      (Icons.inventory_2, 'Stok Gudang', C.amber, () => onGo(4)),
      (Icons.router, 'Paket', C.cyan, () => onGo(5)),
      (Icons.account_balance, 'Keuangan', C.emerald, () => onGo(6)),
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
        Row(children: [
          Expanded(child: Metric('Gangguan Belum Diperbaiki', '$gOpen', gOpen > 0 ? C.rose : C.emerald, Icons.report_problem)),
          Expanded(child: Metric('Total Tiket Gangguan', '${store.gangguan.length}', C.cyan, Icons.confirmation_number)),
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
      case 'tagih':
        previewPdf(context, 'Tagihan_${c.s('id')}', () => buildTagihan(c));
        break;
      case 'wa':
        await kirimWa(context, c);
        break;
      case 'detail':
        {
          final res = await sheet(context, PelangganDetail(c));
          if (res is String && mounted) await act(res, c);
          break;
        }
      case 'edit':
        await sheet(context, EditPelangganForm(c));
        break;
      case 'maps':
        await openMaps(context, c);
        break;
      case 'hapus':
        {
          final yes = await confirm(context, 'Hapus pelanggan?',
              '${c.s('nama')} (${c.s('id')}) akan dihapus dari daftar. Stok perangkat TIDAK dikembalikan otomatis. '
              'Gunakan "Berhenti Berlangganan" bila perangkat akan ditarik. Riwayat transaksi tetap tersimpan.');
          if (!yes || !mounted) return;
          await exec(context, [op('Pelanggan', 'delete', {'id': c.s('id')})], ok: 'Pelanggan dihapus');
          break;
        }
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
        {
          final r = await sheet(context, TiketForm(tipe: 'Pelanggan', cust: c));
          if (r is String && mounted) toast(context, 'Tiket $r diterbitkan');
          break;
        }
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
    final adaGangguan = store.gangguan.any((g) => g.s('pelanggan_id') == c.s('id') && isOpenTicket(g));
    return Panel(
      onTap: () => act('detail', c),
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
            GestureDetector(
              onTap: () => openMaps(context, c),
              child: Text.rich(TextSpan(children: [
                const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.place, size: 13, color: C.cyan))),
                TextSpan(text: alamat(c), style: const TextStyle(color: C.slate, fontSize: 12)),
              ])),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              tag(c.s('paket').isEmpty ? '-' : c.s('paket'), C.cyan),
              tag(lunas ? 'Lunas' : 'Belum Lunas', lunas ? C.emerald : C.rose),
              if (!lunas) tag('Tunggakan ${rpf(bulan * c.n('harga'))}', C.rose),
              if (c.s('sales').isNotEmpty) tag('Sales: ${c.s('sales')}', C.emerald),
              if (menunggu) tag('Menunggu penarikan', C.amber),
              if (adaGangguan) tag('Gangguan aktif', C.rose),
            ]),
            if (!lunas && !menunggu)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: C.amber, visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Kirim Nota Penagihan'),
                  onPressed: () => act('tagih', c),
                ),
              ),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (a) => act(a, c),
          itemBuilder: (_) => menunggu
              ? const [
                  PopupMenuItem(value: 'ambil', child: Text('Konfirmasi material diambil')),
                  PopupMenuItem(value: 'detail', child: Text('Info Pelanggan')),
                  PopupMenuItem(value: 'edit', child: Text('Edit Data')),
                  PopupMenuItem(value: 'hapus', child: Text('Hapus Pelanggan')),
                ]
              : [
                  const PopupMenuItem(value: 'detail', child: Text('Info Pelanggan')),
                  const PopupMenuItem(value: 'maps', child: Text('Buka di Google Maps')),
                  PopupMenuItem(value: 'edit', child: Text('Edit Data')),
                  const PopupMenuItem(value: 'bayar', child: Text('Pelunasan / Bayar')),
                  if (!lunas) const PopupMenuItem(value: 'tagih', child: Text('Kirim Nota Penagihan')),
                  if (!lunas) const PopupMenuItem(value: 'wa', child: Text('Kirim Pengingat WhatsApp')),
                  PopupMenuItem(value: 'nota', child: Text('Nota Tagihan Pasang Baru')),
                  PopupMenuItem(value: 'upgrade', child: Text('Ganti Paket / Ubah Tagihan')),
                  PopupMenuItem(value: 'gangguan', child: Text('Terbitkan Tiket Gangguan')),
                  PopupMenuItem(value: 'berhenti', child: Text('Berhenti Berlangganan')),
                  PopupMenuItem(value: 'hapus', child: Text('Hapus Pelanggan')),
                ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = store.pelanggan.where((c) {
      final hit = '${c.s('id')} ${c.s('nama')} ${c.s('kampung')} ${c.s('hp')} ${c.s('sales')}'.toLowerCase().contains(q.toLowerCase());
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

// ---------- Info Pelanggan ----------
class PelangganDetail extends StatelessWidget {
  final Rec c;
  const PelangganDetail(this.c, {super.key});

  Widget row(String k, String v, {VoidCallback? onTap}) {
    final link = onTap != null && v.isNotEmpty;
    return InkWell(
      onTap: link ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 105, child: Text(k, style: const TextStyle(color: C.slate))),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: link ? C.cyan : null,
                decoration: link ? TextDecoration.underline : null,
                decorationColor: C.cyan,
              ),
            ),
          ),
          if (link) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.map, size: 18, color: C.cyan)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bulan = c.i('bulan_tunggak');
    void maps() => openMaps(context, c);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Info Pelanggan', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Ketuk nama, alamat, atau koordinat untuk membuka Google Maps.',
            style: TextStyle(color: C.slate, fontSize: 12)),
        const SizedBox(height: 10),
        row('ID Pelanggan', c.s('id')),
        row('Nama', c.s('nama'), onTap: maps),
        row('Alamat', alamat(c), onTap: maps),
        row('Koordinat', c.s('koordinat'), onTap: maps),
        row('NIK', c.s('nik')),
        row('No HP / WA', c.s('hp')),
        const Divider(),
        row('Paket', c.s('paket')),
        row('Status', bulan == 0 ? 'Lunas' : 'Belum lunas - $bulan bulan (${rpf(bulan * c.n('harga'))})'),
        row('Tgl pasang', dmy(c.s('tgl_pasang'))),
        row('ONT', c.s('ont')),
        row('SN ONT', c.s('ont_sn')),
        row('Dropcore', '${fmtN(c.n('dropcore'))} m'),
        row('Patchcore', '${c.i('patchcore')} pcs'),
        if (c.s('stb').isNotEmpty) row('STB', c.s('stb')),
        row('Teknisi', c.s('teknisi')),
        row('Nama Sales', c.s('sales')),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
              onPressed: () => Navigator.pop(context, 'edit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: C.rose),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus'),
              onPressed: () => Navigator.pop(context, 'hapus'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.payments),
            label: const Text('Pelunasan / Bayar'),
            onPressed: () => Navigator.pop(context, 'bayar'),
          ),
        ),
        if (bulan > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Kirim Nota Penagihan'),
              onPressed: () => Navigator.pop(context, 'tagih'),
            ),
          ),
        ],
      ]),
    );
  }
}

// ---------- Edit Data Pelanggan ----------
class EditPelangganForm extends StatefulWidget {
  final Rec c;
  const EditPelangganForm(this.c, {super.key});
  @override
  State<EditPelangganForm> createState() => _EdPelState();
}

class _EdPelState extends State<EditPelangganForm> with Submit<EditPelangganForm> {
  static const keys = ['nama', 'nik', 'hp', 'rtrw', 'kampung', 'kecamatan', 'kabupaten', 'koordinat', 'ont_sn', 'teknisi', 'sales', 'tgl_pasang'];
  late final Map<String, TextEditingController> t = {for (final k in keys) k: _c(widget.c.s(k))};

  @override
  void dispose() {
    for (final c in t.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    if (t['nama']!.text.trim().isEmpty) {
      toast(context, 'Nama wajib diisi');
      return;
    }
    final tgl = t['tgl_pasang']!.text.trim();
    if (tgl.isNotEmpty && DateTime.tryParse(tgl) == null) {
      toast(context, 'Format tanggal pasang harus yyyy-MM-dd, contoh 2026-11-02');
      return;
    }
    go([
      op('Pelanggan', 'upsert', {
        'id': widget.c.s('id'),
        for (final k in keys) k: t[k]!.text.trim(),
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => body('Edit Pelanggan (${widget.c.s('id')})', [
        tf(t['nama']!, 'Nama'),
        tf(t['nik']!, 'NIK', kb: TextInputType.number),
        tf(t['hp']!, 'No HP / WhatsApp', kb: TextInputType.phone),
        tf(t['rtrw']!, 'RT/RW', hint: '001/002'),
        tf(t['kampung']!, 'Kampung'),
        tf(t['kecamatan']!, 'Kecamatan'),
        tf(t['kabupaten']!, 'Kabupaten'),
        tf(t['koordinat']!, 'Titik koordinat', hint: '-7.3274, 108.2207 (atau link Google Maps)'),
        tf(t['ont_sn']!, 'Serial No ONT'),
        tf(t['teknisi']!, 'Nama teknisi'),
        tf(t['sales']!, 'Nama Sales'),
        tf(t['tgl_pasang']!, 'Tanggal pasang (yyyy-MM-dd)'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Untuk ganti paket / tunggakan gunakan menu "Ganti Paket / Ubah Tagihan". '
              'Perangkat dan stok tidak berubah dari form ini.',
              style: TextStyle(color: C.slate, fontSize: 12)),
        ),
        btn('Simpan Perubahan', save),
      ]);
}

// ---------- Form Pasang Baru ----------
class PasangBaruForm extends StatefulWidget {
  const PasangBaruForm({super.key});
  @override
  State<PasangBaruForm> createState() => _PBState();
}

class _PBState extends State<PasangBaruForm> with Submit<PasangBaruForm> {
  final t = {
    for (final k in ['id', 'nama', 'nik', 'hp', 'rtrw', 'kampung', 'kec', 'kab', 'koor', 'sn', 'teknisi', 'sales', 'admin'])
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
      'sales': t['sales']!.text.trim(),
      'jam_pasang': DateFormat('HH:mm:ss').format(DateTime.now()),
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
      tf(t['sales']!, 'Nama Sales'),
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

// ---------- Tiket Gangguan: form terbit / edit ----------
class TiketForm extends StatefulWidget {
  final String tipe; // 'Pelanggan' | 'Jalur'
  final Rec? cust, edit;
  const TiketForm({super.key, this.tipe = 'Pelanggan', this.cust, this.edit});
  @override
  State<TiketForm> createState() => _TiketState();
}

class _TiketState extends State<TiketForm> with Submit<TiketForm> {
  static const jenisList = ['Redaman', 'LOS', 'Kabel Putus', 'Perangkat Rusak', 'Lainnya'];
  late final String tipe = widget.edit != null ? tipeTiket(widget.edit!) : widget.tipe;
  final jalur = _c(), ket = _c(), teknisi = _c(), sn = _c(), fom = _c('0'), pcs = _c('0');
  String jenis = 'Redaman', custId = '', ontId = '', foId = '', patchId = '';

  Rec? get cust => find(store.pelanggan, custId);

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      custId = e.s('pelanggan_id');
      if (e.s('jenis').isNotEmpty) jenis = e.s('jenis');
      jalur.text = e.s('jalur');
      ket.text = e.s('keterangan').isNotEmpty ? e.s('keterangan') : e.s('catatan');
      teknisi.text = e.s('teknisi');
      sn.text = e.s('sn_ont');
      ontId = e.s('ont_id');
      foId = e.s('fo_id');
      patchId = e.s('patch_id');
      if (e.n('fo_m') > 0) fom.text = fmtN(e.n('fo_m'));
      if (e.n('patch_pcs') > 0) pcs.text = '${e.i('patch_pcs')}';
    } else if (widget.cust != null) {
      custId = widget.cust!.s('id');
      sn.text = widget.cust!.s('ont_sn');
    }
  }

  @override
  void dispose() {
    for (final c in [jalur, ket, teknisi, sn, fom, pcs]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> opt(Map<String, String> m) => {'': '- Tidak pakai -', ...m};

  void save() {
    final e = widget.edit;
    final c = cust;
    final isP = tipe == 'Pelanggan';
    if (isP && c == null && e == null) {
      toast(context, 'Pilih pelanggan terlebih dahulu');
      return;
    }
    if (!isP && jalur.text.trim().isEmpty) {
      toast(context, 'Isi jalur yang mengalami gangguan');
      return;
    }
    if (teknisi.text.trim().isEmpty) {
      toast(context, 'Isi nama teknisi yang ditugaskan');
      return;
    }
    final m = pn(fom);
    final pc = pn(pcs).toInt();
    if (m > 0 && foId.isEmpty) {
      toast(context, 'Pilih kabel FO yang dipakai');
      return;
    }
    if (pc > 0 && patchId.isEmpty) {
      toast(context, 'Pilih patchcore yang dipakai');
      return;
    }
    final oldM = e == null
        ? <String, num>{}
        : matMap(e.s('ont_id'), e.s('fo_id'), e.n('fo_m'), e.s('patch_id'), e.n('patch_pcs'));
    final newM = matMap(ontId, foId, m, patchId, pc);
    // validasi stok: stok sekarang + material versi lama yang dikembalikan
    for (final k in newM.keys) {
      final s = find(store.stok, k);
      if (s == null || s.n('jumlah') + (oldM[k] ?? 0) < newM[k]!) {
        toast(context, 'Stok ${s == null ? 'tidak ditemukan' : stokName(s)} tidak cukup');
        return;
      }
    }
    final ops = <Map<String, dynamic>>[];
    for (final k in {...oldM.keys, ...newM.keys}) {
      final d = (oldM[k] ?? 0) - (newM[k] ?? 0); // positif = kembali ke stok
      if (d != 0) ops.add(adj(k, d));
    }

    final ont = find(store.stok, ontId);
    final id = e?.s('id') ?? newId('G');
    final oldNo = e?.s('no_tiket') ?? '';
    final no = oldNo.isNotEmpty ? oldNo : nextTiket(tipe);
    final tgl = (e != null && e.s('tgl').isNotEmpty) ? e.s('tgl') : ymd(DateTime.now());
    final nama = isP ? (c?.s('nama') ?? e?.s('nama') ?? '') : '';
    final pid = isP ? (c?.s('id') ?? e?.s('pelanggan_id') ?? '') : '';
    final status = e == null ? 'Belum Diperbaiki' : statusTiket(e);

    ops.add(op('Gangguan', 'upsert', {
      'id': id,
      'no_tiket': no,
      'tgl': tgl,
      'tipe': tipe,
      'pelanggan_id': pid,
      'nama': nama,
      'jenis': isP ? jenis : 'Gangguan Jalur',
      'keterangan': ket.text.trim(),
      'alamat': isP ? (c != null ? alamat(c) : (e?.s('alamat') ?? '')) : '',
      'koordinat': isP ? (c?.s('koordinat') ?? e?.s('koordinat') ?? '') : '',
      'hp': isP ? (c?.s('hp') ?? e?.s('hp') ?? '') : '',
      'jalur': isP ? '' : jalur.text.trim(),
      'sn_ont': sn.text.trim(),
      'teknisi': teknisi.text.trim(),
      'ont_id': ontId,
      'ont': ont == null ? '' : stokName(ont),
      'fo_id': foId,
      'fo_m': m,
      'patch_id': patchId,
      'patch_pcs': pc,
      'status': status,
    }));

    // catatan pemakaian material (untuk laporan keuangan)
    final matId = 'MT-$id';
    if (newM.isNotEmpty) {
      ops.add(op('Material', 'upsert', {
        'id': matId,
        'tgl': tgl,
        'pelanggan_id': pid,
        'nama': isP ? nama : 'Jalur: ${jalur.text.trim()}',
        'ont': ont == null ? '' : stokName(ont),
        'ont_sn': sn.text.trim(),
        'dropcore': m,
        'patchcore': pc,
        'stb': '',
        'teknisi': teknisi.text.trim(),
        'jenis': 'Perbaikan',
      }));
    } else if (e != null) {
      ops.add(op('Material', 'delete', {'id': matId}));
    }

    // tiket yang sudah selesai lalu diedit: sinkronkan modem baru ke data pelanggan
    if (e != null && isP && ont != null && status == 'Sudah Diperbaiki' && find(store.pelanggan, pid) != null) {
      ops.add(op('Pelanggan', 'upsert', {'id': pid, 'ont': stokName(ont), 'ont_id': ontId, 'ont_sn': sn.text.trim()}));
    }
    go(ops, e == null ? no : null);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.edit;
    final c = cust;
    final isP = tipe == 'Pelanggan';
    final nama = c?.s('nama') ?? e?.s('nama') ?? '';
    final pid = c?.s('id') ?? e?.s('pelanggan_id') ?? '';
    final almt = c != null ? alamat(c) : (e?.s('alamat') ?? '');
    final koor = c?.s('koordinat') ?? e?.s('koordinat') ?? '';
    return body(
      e == null ? 'Terbitkan Tiket Gangguan ${isP ? 'Pelanggan' : 'Jalur'}' : 'Edit Tiket ${e.s('no_tiket')}',
      [
        if (isP && e == null && widget.cust == null)
          dd('Pilih pelanggan', custId, {for (final p in store.pelanggan) p.s('id'): '${p.s('nama')} (${p.s('id')})'}, (v) {
            setState(() {
              custId = v ?? '';
              sn.text = find(store.pelanggan, v)?.s('ont_sn') ?? '';
            });
          }),
        if (isP && (c != null || e != null))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$nama ($pid)', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(almt, style: const TextStyle(color: C.slate, fontSize: 12)),
              if (koor.isNotEmpty) Text('Koordinat: $koor', style: const TextStyle(color: C.slate, fontSize: 12)),
            ]),
          ),
        if (isP)
          dd('Jenis gangguan', jenis, lst(jenisList), (v) => setState(() => jenis = v!))
        else
          tf(jalur, 'Jalur yang mengalami gangguan', hint: 'contoh: Jalur ODP-03 Kp. Sirnamanah'),
        tf(ket, 'Keterangan gangguan', lines: 3),
        tf(teknisi, 'Teknisi yang ditugaskan'),
        if (isP) tf(sn, 'Serial Number (SN) ONT'),
        const Divider(),
        const Padding(
          padding: EdgeInsets.only(bottom: 10, top: 4),
          child: Text('Material yang dipakai (opsional, otomatis memotong stok gudang)',
              style: TextStyle(color: C.slate, fontSize: 12)),
        ),
        dd('Modem / ONT', ontId, opt(stokItems('ONT', keep: ontId)), (v) => setState(() => ontId = v ?? '')),
        dd('Kabel FO', foId, opt(stokItems('FO', keep: foId)), (v) => setState(() => foId = v ?? '')),
        tf(fom, 'FO terpakai (meter)', kb: numKb),
        dd('Patchcore', patchId, opt(stokItems('Patchcore', keep: patchId)), (v) => setState(() => patchId = v ?? '')),
        tf(pcs, 'Patchcore terpakai (pcs)', kb: TextInputType.number),
        btn(e == null ? 'Terbitkan Tiket Gangguan' : 'Simpan Perubahan', save),
      ],
    );
  }
}

// ---------- Tandai berhasil diperbaiki ----------
class SelesaiForm extends StatefulWidget {
  final Rec t;
  const SelesaiForm(this.t, {super.key});
  @override
  State<SelesaiForm> createState() => _SelState();
}

class _SelState extends State<SelesaiForm> with Submit<SelesaiForm> {
  final cat = _c();

  @override
  void dispose() {
    cat.dispose();
    super.dispose();
  }

  void save() {
    final t = widget.t;
    final ops = <Map<String, dynamic>>[
      op('Gangguan', 'upsert', {
        'id': t.s('id'),
        'status': 'Sudah Diperbaiki',
        'tgl_selesai': ymd(DateTime.now()),
        'catatan_selesai': cat.text.trim(),
      }),
    ];
    // modem pengganti tercatat pada data pelanggan setelah perbaikan selesai
    if (tipeTiket(t) == 'Pelanggan' && t.s('ont_id').isNotEmpty && find(store.pelanggan, t.s('pelanggan_id')) != null) {
      ops.add(op('Pelanggan', 'upsert', {
        'id': t.s('pelanggan_id'),
        'ont': t.s('ont'),
        'ont_id': t.s('ont_id'),
        'ont_sn': t.s('sn_ont'),
      }));
    }
    go(ops);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final who = tipeTiket(t) == 'Pelanggan' ? '${t.s('nama')} (${t.s('pelanggan_id')})' : 'Jalur ${t.s('jalur')}';
    return body('Berhasil Diperbaiki', [
      Text('${t.s('no_tiket')}\n$who\nTeknisi: ${t.s('teknisi')}'),
      const SizedBox(height: 14),
      tf(cat, 'Catatan hasil perbaikan (opsional)', lines: 3),
      btn('Tandai Sudah Diperbaiki', save),
    ]);
  }
}

// ---------- Tab Gangguan ----------
class GangguanTab extends StatefulWidget {
  const GangguanTab({super.key});
  @override
  State<GangguanTab> createState() => _GgTabState();
}

class _GgTabState extends State<GangguanTab> {
  String tipeF = 'Semua', statF = 'Semua';

  Future<void> act(String a, Rec g) async {
    switch (a) {
      case 'selesai':
        await sheet(context, SelesaiForm(g));
        break;
      case 'edit':
        await sheet(context, TiketForm(edit: g));
        break;
      case 'maps':
        await openMaps(context, g);
        break;
      case 'buka':
        {
          await exec(context, [
            op('Gangguan', 'upsert', {'id': g.s('id'), 'status': 'Belum Diperbaiki', 'tgl_selesai': '', 'catatan_selesai': ''}),
          ], ok: 'Tiket dibuka kembali');
          break;
        }
      case 'hapus':
        {
          final open = isOpenTicket(g);
          final yes = await confirm(
            context,
            'Hapus tiket ${g.s('no_tiket')}?',
            open
                ? 'Tiket dihapus dan material yang sudah dipotong dikembalikan ke stok.'
                : 'Tiket dihapus. Material tidak dikembalikan ke stok karena sudah terpakai.',
          );
          if (!yes || !mounted) return;
          final ops = <Map<String, dynamic>>[];
          if (open) {
            matMap(g.s('ont_id'), g.s('fo_id'), g.n('fo_m'), g.s('patch_id'), g.n('patch_pcs'))
                .forEach((k, v) => ops.add(adj(k, v)));
            ops.add(op('Material', 'delete', {'id': 'MT-${g.s('id')}'}));
          }
          ops.add(op('Gangguan', 'delete', {'id': g.s('id')}));
          await exec(context, ops, ok: 'Tiket dihapus');
          break;
        }
    }
  }

  Widget dot(bool red) {
    final col = red ? C.rose : C.emerald;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: col.withValues(alpha: .6), blurRadius: 6)],
      ),
    );
  }

  Widget chips(List<String> opts, String cur, ValueChanged<String> on) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final x in opts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(x), selected: cur == x, onSelected: (_) => on(x)),
            ),
        ]),
      );

  Widget card(Rec g) {
    final open = isOpenTicket(g);
    final isP = tipeTiket(g) == 'Pelanggan';
    final ket = g.s('keterangan').isNotEmpty ? g.s('keterangan') : g.s('catatan');
    final mats = <String>[
      if (g.s('ont').isNotEmpty) 'Modem: ${g.s('ont')}',
      if (g.n('fo_m') > 0) 'FO: ${fmtN(g.n('fo_m'))} m',
      if (g.n('patch_pcs') > 0) 'Patchcore: ${g.i('patch_pcs')} pcs',
    ];
    return Panel(
      onTap: () => act('edit', g),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 4), child: dot(open)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(g.s('no_tiket').isEmpty ? '-' : g.s('no_tiket'), style: const TextStyle(fontWeight: FontWeight.bold)),
              tag(isP ? 'Pelanggan' : 'Jalur', isP ? C.cyan : C.amber),
              tag(open ? 'Belum diperbaiki' : 'Sudah diperbaiki', open ? C.rose : C.emerald),
            ]),
            const SizedBox(height: 6),
            if (isP) ...[
              Text('${g.s('nama')} (${g.s('pelanggan_id')})', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Jenis gangguan: ${g.s('jenis')}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => openMaps(context, g),
                child: Text.rich(TextSpan(children: [
                  const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.place, size: 13, color: C.cyan))),
                  TextSpan(text: g.s('alamat').isEmpty ? '-' : g.s('alamat'), style: const TextStyle(color: C.slate, fontSize: 12)),
                ])),
              ),
              if (g.s('koordinat').isNotEmpty)
                Text('Koordinat: ${g.s('koordinat')}', style: const TextStyle(color: C.slate, fontSize: 12)),
            ] else
              Text('Jalur: ${g.s('jalur')}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (ket.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Keterangan: $ket', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 4),
            Text('Teknisi: ${g.s('teknisi').isEmpty ? '-' : g.s('teknisi')}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            if (mats.isEmpty)
              const Text('Material: -', style: TextStyle(color: C.slate, fontSize: 12))
            else
              Wrap(spacing: 6, runSpacing: 4, children: [for (final m in mats) tag(m, C.cyan)]),
            const SizedBox(height: 4),
            Text('Tiket: ${dmy(g.s('tgl'))}', style: const TextStyle(color: C.slate, fontSize: 11)),
            if (!open)
              Text(
                'Selesai ${dmy(g.s('tgl_selesai'))}${g.s('catatan_selesai').isEmpty ? '' : ' - ${g.s('catatan_selesai')}'}',
                style: const TextStyle(color: C.emerald, fontSize: 12),
              ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: C.emerald, foregroundColor: Colors.white),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Berhasil Diperbaiki'),
                  onPressed: () => act('selesai', g),
                ),
              ),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (a) => act(a, g),
          itemBuilder: (_) => [
            if (open) const PopupMenuItem(value: 'selesai', child: Text('Berhasil Diperbaiki')),
            const PopupMenuItem(value: 'edit', child: Text('Edit Tiket')),
            if (isP || g.s('koordinat').isNotEmpty) const PopupMenuItem(value: 'maps', child: Text('Buka di Google Maps')),
            if (!open) const PopupMenuItem(value: 'buka', child: Text('Buka Kembali Tiket')),
            const PopupMenuItem(value: 'hapus', child: Text('Hapus Tiket')),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nOpen = store.gangguan.where(isOpenTicket).length;
    final nDone = store.gangguan.length - nOpen;
    final list = store.gangguan.where((g) {
      final okT = tipeF == 'Semua' || tipeTiket(g) == tipeF;
      final okS = statF == 'Semua' || (statF == 'Belum diperbaiki') == isOpenTicket(g);
      return okT && okS;
    }).toList()
      ..sort((a, b) {
        final oa = isOpenTicket(a) ? 0 : 1, ob = isOpenTicket(b) ? 0 : 1;
        if (oa != ob) return oa - ob;
        final d = b.s('tgl').compareTo(a.s('tgl'));
        return d != 0 ? d : b.s('no_tiket').compareTo(a.s('no_tiket'));
      });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 0),
        child: Row(children: [
          Expanded(child: Metric('Belum Diperbaiki', '$nOpen', nOpen > 0 ? C.rose : C.emerald, Icons.report_problem)),
          Expanded(child: Metric('Sudah Diperbaiki', '$nDone', C.emerald, Icons.check_circle)),
        ]),
      ),
      chips(['Semua', 'Pelanggan', 'Jalur'], tipeF, (v) => setState(() => tipeF = v)),
      const SizedBox(height: 4),
      chips(['Semua', 'Belum diperbaiki', 'Sudah diperbaiki'], statF, (v) => setState(() => statF = v)),
      Expanded(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: list.isEmpty
              ? ListView(children: const [SizedBox(height: 160), Center(child: Text('Belum ada tiket gangguan'))])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90, top: 4),
                  itemCount: list.length,
                  itemBuilder: (_, i) => card(list[i]),
                ),
        ),
      ),
    ]);
  }
}

// ---------- Navigasi bawah (7 menu, titik merah di Gangguan bila ada tiket aktif) ----------
class BottomNav extends StatelessWidget {
  final int index, alerts;
  final List<int> visibleIndices;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.index, required this.alerts, required this.visibleIndices, required this.onTap});

  static const items = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Beranda'),
    (Icons.people_outline, Icons.people, 'Pelanggan'),
    (Icons.report_problem_outlined, Icons.report_problem, 'Gangguan'),
    (Icons.payments_outlined, Icons.payments, 'Biaya'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Stok'),
    (Icons.router_outlined, Icons.router, 'Paket'),
    (Icons.account_balance_outlined, Icons.account_balance, 'Keuangan'),
    (Icons.badge_outlined, Icons.badge, 'Sales'),
  ];

  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(children: [
              for (final i in visibleIndices)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(index == i ? items[i].$2 : items[i].$1, size: 24, color: index == i ? C.emerald : C.slate),
                        if (i == 2 && alerts > 0)
                          Positioned(
                            right: -3,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: C.rose, shape: BoxShape.circle),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(items[i].$3,
                              style: TextStyle(fontSize: 10, color: index == i ? C.emerald : C.slate)),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
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

// ---- Pengingat tagihan via WhatsApp (membuka chat pelanggan dengan pesan siap kirim) ----
Future<void> kirimWa(BuildContext c, Rec p) async {
  var no = p.s('hp').replaceAll(RegExp(r'[^0-9]'), '');
  if (no.isEmpty) {
    toast(c, 'Nomor WhatsApp pelanggan belum diisi');
    return;
  }
  if (no.startsWith('0')) no = '62${no.substring(1)}';
  final bulan = p.i('bulan_tunggak');
  final msg = 'Yth. ${p.s('nama')} (ID ${p.s('id')}),\n'
      'Tagihan internet ${p.s('paket')} sebesar ${rpf(bulan * p.n('harga'))} ($bulan bulan) belum kami terima.\n\n'
      'Pembayaran dapat melalui:\n'
      '- Transfer ${Cfg.bank} a.n. ${Cfg.atasNama}\n'
      '- E-Wallet ${Cfg.ewallet}\n'
      '- QRIS (terlampir pada nota)\n\n'
      'Mohon cantumkan ID Pelanggan saat membayar. Terima kasih.\n${Cfg.company}';
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse('https://wa.me/$no?text=${Uri.encodeComponent(msg)}'),
        mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && c.mounted) toast(c, 'Tidak bisa membuka WhatsApp');
}

// ---- Nota / Struk Penagihan (tunggakan pelanggan) ----
Future<Uint8List> buildTagihan(Rec c) async {
  final logo = await _img('assets/images/logo.png');
  final qris = await _img('assets/images/qris.png');
  final now = DateTime.now();
  final harga = c.n('harga');
  final bln = c.i('bulan_tunggak');
  final total = bln * harga;
  final dpp = total / (1 + Cfg.ppn);
  final dppBln = harga / (1 + Cfg.ppn);
  final rows = <List<String>>[];
  if (bln <= 12) {
    // satu baris per bulan, dihitung mundur dari bulan berjalan
    for (var i = bln - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      rows.add([
        '${rows.length + 1}',
        'Langganan ${c.s('paket')}\nPeriode ${monFull[d.month - 1]} ${d.year}',
        '1 Bln',
        rpf(dppBln),
        rpf(dppBln),
      ]);
    }
  } else {
    rows.add(['1', 'Langganan ${c.s('paket')}\nTunggakan $bln bulan', '$bln Bln', rpf(dppBln), rpf(dpp)]);
  }
  final noDok = 'TG/BM/${now.year}/${now.month.toString().padLeft(2, '0')}/${c.s('id')}';
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      _hdr(logo),
      pw.SizedBox(height: 12),
      pw.Center(child: pw.Text('NOTA PENAGIHAN', style: _b(15, _blue))),
      pw.Center(child: pw.Text('No. Dokumen: $noDok   |   Tanggal: ${now.day} ${monFull[now.month - 1]} ${now.year}', style: _n(9))),
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
          child: _box('RINCIAN TAGIHAN', [
            _kv('Paket', c.s('paket')),
            _kv('Tunggakan', '$bln Bulan'),
            _kv('Status', 'BELUM LUNAS'),
            _kv('Total Tagihan', rpf(total)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      ..._items(rows),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red700, width: 2)),
          child: pw.Text('BELUM LUNAS', style: _b(16, PdfColors.red700)),
        ),
        pw.SizedBox(
          width: 230,
          child: pw.Column(children: [
            _tot('Subtotal (Excl. PPN)', rpf(dpp)),
            _tot('PPN 11%', rpf(total - dpp)),
            pw.Divider(),
            _tot('TOTAL TAGIHAN', rpf(total), big: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _box('INFORMASI PEMBAYARAN', [
            pw.Text('Transfer Bank: ${Cfg.bank}', style: _n(9)),
            pw.Text('E-Wallet: ${Cfg.ewallet}', style: _n(9)),
            pw.Text('Atas Nama: ${Cfg.atasNama}', style: _b(9)),
            pw.SizedBox(height: 4),
            pw.Text('Mohon cantumkan ID Pelanggan ${c.s('id')} saat membayar.', style: _n(8, PdfColors.grey700)),
            pw.Text('Segera lakukan pembayaran agar layanan tetap aktif.', style: _n(8, PdfColors.grey700)),
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
        _sig('Petugas Billing,', Cfg.company),
      ]),
      _footer('${Cfg.company} Billing System - Nota Penagihan Otomatis'),
    ],
  ));
  return doc.save();
}


// ============================================================
//  MODUL SALES - dikelompokkan langsung dari data Pelanggan
// ============================================================
// ---------- SALES (data diambil dari kolom "sales" pada daftar pelanggan) ----------
DateTime? tglPasang(Rec c) => DateTime.tryParse(c.s('tgl_pasang'));

String tglJam(Rec c) {
  final d = tglPasang(c);
  if (d == null) return '-';
  final base = DateFormat('dd/MM/yyyy').format(d);
  final j = c.s('jam_pasang');
  return j.isEmpty ? base : '$base $j';
}

class SalesInfo {
  final String nama;
  final List<Rec> pel;
  SalesInfo(this.nama, this.pel);
  int get total => pel.length;
  int get bulanIni {
    final n = DateTime.now();
    return pel.where((c) {
      final d = tglPasang(c);
      return d != null && d.year == n.year && d.month == n.month;
    }).length;
  }
}

/// Kelompokkan pelanggan per nama sales (huruf besar/kecil dianggap sama).
List<SalesInfo> salesList() {
  final names = <String, String>{};
  final groups = <String, List<Rec>>{};
  for (final c in store.pelanggan) {
    final n = c.s('sales');
    if (n.isEmpty) continue;
    final k = n.toLowerCase();
    names.putIfAbsent(k, () => n);
    groups.putIfAbsent(k, () => []).add(c);
  }
  final l = [for (final e in groups.entries) SalesInfo(names[e.key]!, e.value)];
  l.sort((a, b) {
    final d = b.bulanIni - a.bulanIni;
    if (d != 0) return d;
    final t = b.total - a.total;
    return t != 0 ? t : a.nama.compareTo(b.nama);
  });
  return l;
}

SalesInfo? findSales(String nama) {
  for (final s in salesList()) {
    if (s.nama.toLowerCase() == nama.toLowerCase()) return s;
  }
  return null;
}

List<String> salesNames() => salesList().map((s) => s.nama).toList();

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});
  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  String q = '';

  Future<void> act(String a, String nama) async {
    switch (a) {
      case 'detail':
        {
          final r = await sheet(context, SalesDetail(nama));
          if (r is String && mounted) await act(r, nama);
          break;
        }
      case 'edit':
        await sheet(context, SalesEditForm(nama));
        break;
      case 'hapus':
        {
          final s = findSales(nama);
          if (s == null) return;
          final yes = await confirm(
            context,
            'Hapus sales ${s.nama}?',
            '${s.total} pelanggan tetap ada di daftar pelanggan. Hanya kolom Nama Sales pada pelanggan tersebut yang dikosongkan.',
          );
          if (!yes || !mounted) return;
          await exec(context, [
            for (final c in s.pel) op('Pelanggan', 'upsert', {'id': c.s('id'), 'sales': ''}),
          ], ok: 'Sales dihapus');
          break;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = salesList();
    final list = all.where((s) => s.nama.toLowerCase().contains(q.toLowerCase())).toList();
    final totalBulan = all.fold<int>(0, (a, s) => a + s.bulanIni);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 0),
        child: Row(children: [
          Expanded(child: Metric('Total Sales', '${all.length}', C.cyan, Icons.badge)),
          Expanded(child: Metric('Pelanggan Baru Bulan Ini', '$totalBulan', C.emerald, Icons.person_add)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => q = v),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Cari nama sales', border: OutlineInputBorder()),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Center(
                      child: Text(
                        'Belum ada data sales.\nIsi "Nama Sales" saat pasang baru atau lewat Edit Data pelanggan.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return Panel(
                      onTap: () => act('detail', s.nama),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: C.emerald.withValues(alpha: .18),
                          child: Text(s.nama.characters.first.toUpperCase(), style: const TextStyle(color: C.emerald)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('Total pelanggan: ${s.total}', style: const TextStyle(color: C.slate, fontSize: 12)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${s.bulanIni}',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold, color: s.bulanIni > 0 ? C.emerald : C.slate)),
                          const Text('bulan ini', style: TextStyle(color: C.slate, fontSize: 11)),
                        ]),
                        PopupMenuButton<String>(
                          onSelected: (a) => act(a, s.nama),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'detail', child: Text('Lihat Pelanggan')),
                            PopupMenuItem(value: 'edit', child: Text('Edit Data Sales')),
                            PopupMenuItem(value: 'hapus', child: Text('Hapus Sales')),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}

// ---------- Detail sales: daftar pelanggan + tanggal/waktu ----------
class SalesDetail extends StatefulWidget {
  final String nama;
  const SalesDetail(this.nama, {super.key});
  @override
  State<SalesDetail> createState() => _SalesDetailState();
}

class _SalesDetailState extends State<SalesDetail> {
  bool onlyMonth = false;

  @override
  Widget build(BuildContext context) {
    final s = findSales(widget.nama);
    if (s == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('Data sales tidak ditemukan'));
    }
    final now = DateTime.now();
    final list = s.pel.where((c) {
      if (!onlyMonth) return true;
      final d = tglPasang(c);
      return d != null && d.year == now.year && d.month == now.month;
    }).toList()
      ..sort((a, b) {
        final d = (tglPasang(b) ?? DateTime(2000)).compareTo(tglPasang(a) ?? DateTime(2000));
        return d != 0 ? d : b.s('jam_pasang').compareTo(a.s('jam_pasang'));
      });
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sales: ${s.nama}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Metric('Pelanggan Bulan Ini', '${s.bulanIni}', C.emerald, Icons.calendar_month)),
          Expanded(child: Metric('Total Pelanggan', '${s.total}', C.cyan, Icons.people)),
        ]),
        Row(children: [
          ChoiceChip(label: const Text('Semua'), selected: !onlyMonth, onSelected: (_) => setState(() => onlyMonth = false)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Bulan ini'), selected: onlyMonth, onSelected: (_) => setState(() => onlyMonth = true)),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Tidak ada pelanggan pada periode ini')))
        else
          for (final c in list)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.s('nama')} (${c.s('id')})', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(c.s('paket').isEmpty ? '-' : c.s('paket'), style: const TextStyle(color: C.slate, fontSize: 12)),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Icon(Icons.event, size: 14, color: C.cyan),
                  Text(tglJam(c), style: const TextStyle(fontSize: 12)),
                ]),
              ]),
            ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Edit Sales'),
              onPressed: () => Navigator.pop(context, 'edit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: C.rose),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus Sales'),
              onPressed: () => Navigator.pop(context, 'hapus'),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------- Edit data sales: nama sales, deretan pelanggan, dan tanggalnya ----------
class SalesEditForm extends StatefulWidget {
  final String nama;
  const SalesEditForm(this.nama, {super.key});
  @override
  State<SalesEditForm> createState() => _SalesEditState();
}

class _SalesEditState extends State<SalesEditForm> with Submit<SalesEditForm> {
  late final TextEditingController nameC = _c(widget.nama);
  late final List<Rec> orig = findSales(widget.nama)?.pel ?? <Rec>[];
  final Map<String, DateTime> dates = {};
  final Set<String> removed = {};
  final List<String> added = [];

  @override
  void dispose() {
    nameC.dispose();
    super.dispose();
  }

  List<Rec> get current => [
        ...orig.where((c) => !removed.contains(c.s('id'))),
        ...added.map((id) => find(store.pelanggan, id)).whereType<Rec>(),
      ];

  DateTime? dateOf(Rec c) => dates[c.s('id')] ?? tglPasang(c);

  Future<void> pick(Rec c) async {
    final first = DateTime(2015);
    final last = DateTime.now().add(const Duration(days: 365));
    var init = dateOf(c) ?? DateTime.now();
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
    if (d != null) setState(() => dates[c.s('id')] = d);
  }

  void save() {
    final newName = nameC.text.trim();
    if (newName.isEmpty) {
      toast(context, 'Nama sales wajib diisi');
      return;
    }
    final ops = <Map<String, dynamic>>[];
    for (final c in orig) {
      final id = c.s('id');
      if (removed.contains(id)) {
        ops.add(op('Pelanggan', 'upsert', {'id': id, 'sales': ''}));
        continue;
      }
      final d = dates[id];
      final dateChanged = d != null && ymd(d) != c.s('tgl_pasang');
      final nameChanged = newName != c.s('sales');
      if (nameChanged || dateChanged) {
        ops.add(op('Pelanggan', 'upsert', {
          'id': id,
          if (nameChanged) 'sales': newName,
          if (dateChanged) 'tgl_pasang': ymd(d),
        }));
      }
    }
    for (final id in added) {
      final d = dates[id];
      ops.add(op('Pelanggan', 'upsert', {
        'id': id,
        'sales': newName,
        if (d != null) 'tgl_pasang': ymd(d),
      }));
    }
    if (ops.isEmpty) {
      Navigator.pop(context);
      return;
    }
    go(ops);
  }

  @override
  Widget build(BuildContext context) {
    final cur = current;
    final candidates = {
      for (final p in store.pelanggan)
        if (p.s('sales').isEmpty && !added.contains(p.s('id'))) p.s('id'): '${p.s('nama')} (${p.s('id')})',
    };
    return body('Edit Data Sales', [
      tf(nameC, 'Nama sales'),
      Text('Pelanggan (${cur.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('Ketuk tanggal untuk mengubahnya. Ikon tempat sampah melepas pelanggan dari sales ini.',
          style: TextStyle(color: C.slate, fontSize: 12)),
      const SizedBox(height: 8),
      if (cur.isEmpty)
        const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Belum ada pelanggan', style: TextStyle(color: C.slate))),
      for (final c in cur)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Text('${c.s('nama')} (${c.s('id')})', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.event, size: 16),
              label: Text(dateOf(c) == null ? '-' : DateFormat('dd/MM/yyyy').format(dateOf(c)!)),
              onPressed: () => pick(c),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: C.rose),
              onPressed: () => setState(() {
                final id = c.s('id');
                if (added.contains(id)) {
                  added.remove(id);
                } else {
                  removed.add(id);
                }
              }),
            ),
          ]),
        ),
      const SizedBox(height: 8),
      if (candidates.isNotEmpty)
        KeyedSubtree(
          key: ValueKey('add${added.length}'),
          child: dd('Tambah pelanggan (yang belum punya sales)', '', candidates, (v) {
            if (v != null && v.isNotEmpty) setState(() => added.add(v));
          }),
        ),
      btn('Simpan Perubahan', save),
    ]);
  }
}


