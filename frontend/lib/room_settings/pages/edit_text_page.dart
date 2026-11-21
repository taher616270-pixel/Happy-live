import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class EditTextPage extends StatefulWidget {
  final String title;
  final String initial;
  final int maxLength;
  final Future<void> Function(String) onSave;
  const EditTextPage({super.key, required this.title, required this.initial, required this.maxLength, required this.onSave});
  @override
  State<EditTextPage> createState() => _EditTextPageState();
}

class _EditTextPageState extends State<EditTextPage> {
  late final TextEditingController t = TextEditingController(text: widget.initial);
  bool saving = false;
  @override
  void dispose() { t.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: RsAppBar(title: widget.title),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), decoration: BoxDecoration(color: RS.bg, borderRadius: BorderRadius.circular(12)), child: Column(children: [
        TextField(controller: t, maxLength: widget.maxLength, minLines: 3, maxLines: 5, onChanged: (_) => setState(() {}), style: const TextStyle(color: RS.text, fontSize: 14, fontWeight: FontWeight.w700), decoration: const InputDecoration(border: InputBorder.none, counterText: '')),
        Align(alignment: Alignment.centerLeft, child: Text('${t.text.runes.length}/${widget.maxLength}', style: const TextStyle(color: RS.lightGray, fontSize: 11))),
      ])),
      const SizedBox(height: 22),
      PrimaryButton(label: saving ? 'جارٍ الحفظ' : 'حفظ', backgroundColor: const Color(0xFFD4AF37), textColor: Colors.white, onTap: t.text.trim().isEmpty || saving ? null : () async {
        setState(() => saving = true);
        try { await widget.onSave(t.text.trim()); if (context.mounted) { Navigator.pop(context); showRsToast(context, 'تم بنجاح'); } }
        catch (e) { if (context.mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', '')); }
        finally { if (mounted) setState(() => saving = false); }
      }),
    ])),
  );
}
