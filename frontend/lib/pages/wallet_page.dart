import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.apiBase, required this.accessToken});

  final String apiBase;
  final String accessToken;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const _gold = Color(0xFFE8C477);
  static const _surface = Color(0xFF17131F);
  static const _muted = Color(0xFFAAA2B5);

  bool _loading = true;
  String? _error;
  int _balance = 0;
  String _userCode = '';
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(
        Uri.parse('${widget.apiBase}/wallet'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 20));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['ok'] != true) {
        throw Exception((payload['message'] ?? payload['error'] ?? 'تعذر تحميل المحفظة').toString());
      }
      final raw = payload['transactions'];
      final items = raw is List
          ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _balance = (payload['balance'] as num?)?.toInt() ?? 0;
        _userCode = (payload['userCode'] ?? '').toString();
        _transactions = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString());
    if (parsed == null) return '—';
    final d = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  String _label(Map<String, dynamic> item) {
    final description = (item['description'] ?? '').toString().trim();
    if (description.isNotEmpty) return description;
    switch ((item['type'] ?? '').toString()) {
      case 'room_upgrade': return 'ترقية غرفة';
      case 'admin_credit': return 'إضافة رصيد';
      default: return 'حركة رصيد';
    }
  }

  void _showRechargeInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('شحن العملات', style: TextStyle(color: _gold, fontWeight: FontWeight.w800)),
        content: const Text(
          'الشحن الإلكتروني وبوابات الدفع لم يتم ربطها بعد. سيظهر خيار الشحن عند تفعيل وسيلة دفع معتمدة.',
          style: TextStyle(color: Colors.white70, height: 1.6),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: const Color(0xFF09080D),
          foregroundColor: _gold,
          elevation: 0,
          centerTitle: true,
          title: const Text('المحفظة', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: RefreshIndicator(
          color: _gold,
          onRefresh: _loadWallet,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF34253D), Color(0xFF17131F), Color(0xFF100E17)],
                  ),
                  border: Border.all(color: _gold.withOpacity(.55)),
                  boxShadow: const [BoxShadow(color: Color(0x332D1B3D), blurRadius: 22, offset: Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.account_balance_wallet_rounded, color: _gold, size: 22),
                      SizedBox(width: 9),
                      Text('رصيد العملات', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 13),
                    if (_loading && _transactions.isEmpty)
                      const SizedBox(height: 42, child: Align(alignment: Alignment.centerRight, child: CircularProgressIndicator(color: _gold, strokeWidth: 2)))
                    else
                      Row(children: [
                        Text(_balance.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ','),
                          style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 9),
                        const Icon(Icons.monetization_on_rounded, color: _gold, size: 27),
                      ]),
                    if (_userCode.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('معرّف الحساب: $_userCode', style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 17),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showRechargeInfo,
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                        label: const Text('شحن العملات'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: const BorderSide(color: _gold),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('سجل الحركات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900))),
                IconButton(onPressed: _loadWallet, icon: const Icon(Icons.refresh_rounded, color: _gold), tooltip: 'تحديث'),
              ]),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.redAccent.withOpacity(.4))),
                  child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _loadWallet, child: const Text('إعادة المحاولة')),
                  ]),
                )
              else if (_loading && _transactions.isEmpty)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: _gold)))
              else if (_transactions.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
                  decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF30263A))),
                  child: const Column(children: [
                    Icon(Icons.receipt_long_rounded, color: _gold, size: 34),
                    SizedBox(height: 10),
                    Text('لا توجد حركات حتى الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    SizedBox(height: 5),
                    Text('ستظهر هنا عمليات إضافة العملات واستخدامها.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
                  ]),
                )
              else
                ..._transactions.map((item) {
                  final amount = (item['amount'] as num?)?.toInt() ?? 0;
                  final positive = amount >= 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF30263A))),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: _gold.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(positive ? Icons.south_west_rounded : Icons.north_east_rounded, color: _gold, size: 20),
                      ),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_label(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(_date(item['createdAt']), style: const TextStyle(color: _muted, fontSize: 10)),
                      ])),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${positive ? '+' : ''}${amount.toString()}', style: TextStyle(color: positive ? const Color(0xFF63CEBA) : const Color(0xFFFF7185), fontWeight: FontWeight.w900, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('الرصيد ${(item['balanceAfter'] as num?)?.toInt() ?? 0}', style: const TextStyle(color: _muted, fontSize: 10)),
                      ]),
                    ]),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
