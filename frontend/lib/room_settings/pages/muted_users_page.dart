import 'package:flutter/material.dart';
import '../room_settings_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class MutedUsersPage extends StatelessWidget {
  final RoomSettingsController c;
  const MutedUsersPage({super.key, required this.c});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: RsAppBar(
              title: 'قائمة الكتم',
              actions: [
                IconButton(
                  onPressed: c.refreshModeration,
                  icon: const Icon(Icons.refresh, color: RS.text),
                  tooltip: 'تحديث',
                ),
              ],
            ),
            body: c.moderationLoading
                ? const Center(child: CircularProgressIndicator(color: RS.primary))
                : c.muted.isEmpty
                    ? const EmptyState('لا يوجد مستخدمون مكتومون')
                    : ListView.separated(
                        itemCount: c.muted.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: RS.divider),
                        itemBuilder: (context, index) {
                          final row = c.muted[index];
                          final userId = (row['user_id'] ?? '').toString();
                          final name = (row['display_name'] ?? 'مستخدم').toString();
                          final publicId = (row['public_id'] ?? '').toString();
                          return ListTile(
                            title: Text(name, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                            subtitle: Text('ID: $publicId', style: const TextStyle(color: RS.gray, fontSize: 12)),
                            trailing: TextButton(
                              onPressed: userId.isEmpty ? null : () async {
                                try {
                                  await c.moderate('unmute', userId);
                                  if (context.mounted) showRsToast(context, 'تم إلغاء الكتم');
                                } catch (e) {
                                  if (context.mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', ''));
                                }
                              },
                              child: const Text('إلغاء الكتم', style: TextStyle(color: Color(0xFF168F79), fontWeight: FontWeight.w700)),
                            ),
                          );
                        },
                      ),
          );
        },
      );
}
