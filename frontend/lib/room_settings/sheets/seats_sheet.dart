import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

const _options = <SeatOption>[
  SeatOption(8),
];

Future<int?> showSeatsSheet(BuildContext context, {required int current}) => showModalBottomSheet<int>(
  context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
  builder: (_) => _SeatsSheet(current: current),
);

class _SeatsSheet extends StatefulWidget {
  final int current;
  const _SeatsSheet({required this.current});
  @override
  State<_SeatsSheet> createState() => _SeatsSheetState();
}

class _SeatsSheetState extends State<_SeatsSheet> {
  late int selected = _options.indexWhere((o) => o.count == widget.current && !o.locked);
  final ScrollController _ctrl = ScrollController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (selected < 0) selected = 0;
    final opt = _options[selected];
    return Container(
      height: MediaQuery.of(context).size.height * .62,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      child: SafeArea(top: false, child: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('عدد المقاعد', style: TextStyle(color: RS.text, fontSize: 16, fontWeight: FontWeight.w900))),
        Expanded(child: Scrollbar(controller: _ctrl, child: GridView.builder(
          controller: _ctrl, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .9),
          itemCount: _options.length,
          itemBuilder: (_, i) => _SeatCard(option: _options[i], selected: i == selected, onTap: () => setState(() => selected = i)),
        ))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: opt.locked
          ? PrimaryButton(label: 'رفع مستوى', subtitle: 'الغرفة ≥Lv.50 أو ≥قصر', onTap: () => Navigator.pop(context))
          : PrimaryButton(label: 'حسنا', onTap: () => Navigator.pop(context, opt.count))),
      ])),
    );
  }
}

class _SeatCard extends StatelessWidget {
  final SeatOption option;
  final bool selected;
  final VoidCallback onTap;
  const _SeatCard({required this.option, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Expanded(child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? RS.primary : Colors.transparent, width: 2)),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _SeatPainter(option.count)),
          if (selected) Positioned(left: 8, top: 8, child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: RS.primary, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 16))),
          if (option.vip) Positioned(right: 8, top: 6, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(6)), child: const Text('👑', style: TextStyle(fontSize: 11)))),
        ])),
      )),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${option.count}', style: TextStyle(color: selected ? RS.primaryDark : RS.gray, fontSize: 16, fontWeight: FontWeight.w700)),
        if (option.locked) ...[const SizedBox(width: 3), Icon(Icons.lock, size: 11, color: selected ? RS.primaryDark : RS.lightGray)],
      ]),
    ]),
  );
}

class _SeatPainter extends CustomPainter {
  final int count;
  _SeatPainter(this.count);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E8C99), Color(0xFF0A4F63)]).createShader(rect));
    final cols = count <= 16 ? 4 : 6;
    final rows = (count / cols).ceil();
    final r = (size.width / (cols + 1)) * .3;
    final fill = Paint()..color = const Color(0x99062C3A);
    final ring = Paint()..color = const Color(0x55FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final row = i ~/ cols, col = i % cols;
      final cx = size.width * (col + 1) / (cols + 1);
      final cy = size.height * .16 + (size.height * .76) * (row + .5) / rows;
      canvas.drawCircle(Offset(cx, cy), r, fill);
      canvas.drawCircle(Offset(cx, cy), r, ring);
    }
  }
  @override
  bool shouldRepaint(covariant _SeatPainter old) => old.count != count;
}
