import 'package:flutter/material.dart';

class HappyProfilePage extends StatelessWidget {
  const HappyProfilePage({
    super.key,
    required this.name,
    required this.email,
    required this.initial,
    required this.onLogout,
    required this.onSoon,
  });

  final String name;
  final String email;
  final String initial;
  final VoidCallback onLogout;
  final ValueChanged<String> onSoon;

  static const Color _background = Color(0xFF09080D);
  static const Color _surface = Color(0xFF17131F);
  static const Color _gold = Color(0xFFE8C477);
  static const Color _muted = Color(0xFFAAA2B5);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
        children: [
          const Text(
            'الملف الشخصي',
            style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF38234B), Color(0xFF17121F)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              border: Border.all(color: const Color(0x665F4775)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _gold, width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x449B63D9), blurRadius: 18)],
                  ),
                  child: CircleAvatar(
                    radius: 43,
                    backgroundColor: const Color(0xFF241B2D),
                    child: Text(initial, style: const TextStyle(color: _gold, fontSize: 32, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 13),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(email, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => onSoon('تعديل الملف الشخصي'),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('تعديل الملف الشخصي'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: const BorderSide(color: _gold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ProfileAction(
            icon: Icons.shield_outlined,
            title: 'الخصوصية والأمان',
            subtitle: 'إعدادات الحساب والحماية',
            onTap: () => onSoon('إعدادات الخصوصية'),
          ),
          const SizedBox(height: 10),
          _ProfileAction(
            icon: Icons.help_outline_rounded,
            title: 'المساعدة والدعم',
            subtitle: 'نحن هنا لمساعدتك',
            onTap: () => onSoon('الدعم'),
          ),
          const SizedBox(height: 10),
          _ProfileAction(
            icon: Icons.logout_rounded,
            title: 'تسجيل الخروج',
            subtitle: 'الخروج من هذا الجهاز',
            onTap: onLogout,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF7777) : const Color(0xFFE8C477);
    return Material(
      color: const Color(0xFF17131F),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x665F4775)),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(color: const Color(0xFF352541), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: danger ? color : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Color(0xFFAAA2B5), fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Color(0xFFAAA2B5)),
            ],
          ),
        ),
      ),
    );
  }
}
