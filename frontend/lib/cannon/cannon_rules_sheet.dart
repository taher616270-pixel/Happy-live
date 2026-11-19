import 'package:flutter/material.dart';

Future<void> showCannonRulesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: _RulesSheet()),
  );
}

InlineSpan _bolt() => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Container(
    width: 18, height: 18, margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: const BoxDecoration(color: Color(0xFF1FD27A), shape: BoxShape.circle),
    child: const Icon(Icons.bolt, size: 13, color: Colors.white),
  ),
);

class _RulesSheet extends StatelessWidget {
  const _RulesSheet();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final rules = <List<InlineSpan>>[
      [const TextSpan(text: 'اجمع '), _bolt(), const TextSpan(text: ' عن طريق إرسال هدايا من العملات الذهبية في الغرفة وأطلق المدفع. عندما يكون شريط التقدم ممتلئًا، سيتم إطلاق المدفع تلقائيًا.')],
      [const TextSpan(text: 'عند إطلاق المدفع، تتاح لكل شخص في الغرفة فرصة الحصول على هدايا. كلما زادت المساهمات '), _bolt(), const TextSpan(text: '، زادت احتمالية الحصول على هدايا متقدمة. يتم تحديث المكافآت من وقت لآخر.')],
      [const TextSpan(text: 'ربما يأخذ النظام بعض الوقت لإرسال الهدايا إلى حسابك.')],
      [const TextSpan(text: 'سيتم إعادة تعيين التقدم كل يوم الساعة 00:00:00 بتوقيت المملكة العربية السعودية.')],
    ];
    return Container(
      height: h * 0.62,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF05053F), Color(0xFF020220)]),
      ),
      child: Column(children: [
        SizedBox(height: 58, child: Stack(children: [
          const Center(child: Text('مدفع الغرفة', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
          Align(alignment: Alignment.centerRight, child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_right, color: Color(0xFF3AA8FF), size: 30),
          )),
        ])),
        Expanded(child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          itemCount: rules.length,
          separatorBuilder: (_, __) => const SizedBox(height: 18),
          itemBuilder: (_, i) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 8, left: 10), child: Icon(Icons.arrow_left, size: 14, color: Color(0xFF9FE7FF))),
            Expanded(child: Text.rich(
              TextSpan(children: [TextSpan(text: '${i + 1}. '), ...rules[i]]),
              style: const TextStyle(color: Color(0xFF9AA6D8), fontSize: 15, height: 1.7),
            )),
          ]),
        )),
      ]),
    );
  }
}
