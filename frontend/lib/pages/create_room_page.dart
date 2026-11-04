import 'package:flutter/material.dart';

class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({super.key});

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  static const _background = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _gold = Color(0xFFE8C477);
  static const _purple = Color(0xFF9B63D9);
  static const _muted = Color(0xFFAAA2B5);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPrivate = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تجهيز بيانات الغرفة، وسيتم ربط الحفظ بالخادم في الخطوة التالية'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    prefixIcon: Icon(icon, color: _gold),
    filled: true,
    fillColor: const Color(0xFF100E15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0x665F4775)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0x665F4775)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: _gold, width: 1.2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF17121F),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'إنشاء غرفة حفلة',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x665F4775)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.groups_rounded, color: _gold, size: 42),
                      SizedBox(height: 10),
                      Text(
                        'أنشئ غرفتك واجمع أصدقاءك',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'أدخل تفاصيل الغرفة قبل إنشائها',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _nameController,
                  maxLength: 30,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('اسم الغرفة', Icons.meeting_room_outlined),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'اكتب اسم الغرفة'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 120,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('وصف الغرفة (اختياري)', Icons.edit_note_rounded),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0x665F4775)),
                  ),
                  child: SwitchListTile(
                    value: _isPrivate,
                    onChanged: (value) => setState(() => _isPrivate = value),
                    activeColor: _purple,
                    title: const Text('غرفة خاصة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      _isPrivate ? 'الغرفة خاصة' : 'الغرفة متاحة للجميع',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    secondary: const Icon(Icons.lock_outline_rounded, color: _gold),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إنشاء الغرفة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
