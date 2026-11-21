import 'package:flutter/material.dart';
import '../models/mic_layout.dart';
import 'mic_layout_preview.dart';

Future<String?> showMicCountSheet(BuildContext context, {required String currentId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: MicCountSheet(currentId: currentId),
    ),
  );
}

class MicCountSheet extends StatefulWidget {
  final String currentId;
  const MicCountSheet({super.key, required this.currentId});

  @override
  State<MicCountSheet> createState() => _MicCountSheetState();
}

class _MicCountSheetState extends State<MicCountSheet> {
  late String _selected = micLayoutById(widget.currentId).id;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Container(
      height: height * .68,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, 22, 16, MediaQuery.paddingOf(context).bottom + 14),
      child: Column(children: [
        const Text('عدد المقاعد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
        const SizedBox(height: 16),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsetsDirectional.only(end: 8),
              itemCount: kMicLayouts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 8,
                childAspectRatio: .84,
              ),
              itemBuilder: (_, index) {
                final layout = kMicLayouts[index];
                final selected = layout.id == _selected;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = layout.id),
                  child: Column(children: [
                    Expanded(child: MicLayoutPreview(layout: layout, selected: selected)),
                    const SizedBox(height: 5),
                    Text('${layout.count}',
                      style: TextStyle(fontSize: 17, color: selected ? kTeal : const Color(0xFF8E8E93), fontWeight: FontWeight.w600)),
                  ]),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected),
            style: ElevatedButton.styleFrom(
              backgroundColor: kTeal,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const StadiumBorder(side: BorderSide(color: Color(0xFFD4AF37), width: 2)),
            ),
            child: const Text('حسنا', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
