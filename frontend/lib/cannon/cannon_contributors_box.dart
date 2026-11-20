import 'package:flutter/material.dart';
import 'cannon_models.dart';

String _contributionFormat(int value) {
  final raw = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
    out.write(raw[i]);
  }
  return out.toString();
}

class CannonContributorsBox extends StatelessWidget {
  final List<CannonContributor> contributors;
  final bool loading;
  final bool unavailable;
  const CannonContributorsBox({
    super.key,
    required this.contributors,
    this.loading = false,
    this.unavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF07164D).withOpacity(0.92),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF328BFF), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('أكبر المساهمين في إطلاق المدفع',
            style: TextStyle(color: Color(0xFFFFD66B), fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF52C7FF)),
            )
          else if (unavailable)
            const Text('تعذر تحميل قائمة المساهمين', style: TextStyle(color: Colors.white70, fontSize: 12))
          else if (contributors.isEmpty)
            const Text('لا توجد مساهمات مسجلة لهذا الإطلاق', style: TextStyle(color: Colors.white70, fontSize: 12))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: contributors.length,
                separatorBuilder: (_, __) => const Divider(height: 8, color: Color(0x332F83D9)),
                itemBuilder: (context, index) {
                  final person = contributors[index];
                  return Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('#${index + 1}', textAlign: TextAlign.center,
                          style: TextStyle(color: index == 0 ? const Color(0xFFFFD66B) : Colors.white60,
                            fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 7),
                      ClipOval(
                        child: person.avatarUrl.isEmpty
                          ? Container(width: 34, height: 34, color: const Color(0xFF173B83),
                              child: const Icon(Icons.person, color: Colors.white70, size: 20))
                          : Image.network(person.avatarUrl, width: 34, height: 34, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 34, height: 34,
                                color: const Color(0xFF173B83), child: const Icon(Icons.person, color: Colors.white70, size: 20))),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(person.userName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(_contributionFormat(person.contribution),
                        style: const TextStyle(color: Color(0xFF72E5B1), fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 3),
                      const Icon(Icons.bolt, color: Color(0xFF42D990), size: 15),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
