import 'package:flutter/material.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import '../room_settings_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class MutedUsersPage extends StatefulWidget {
  final RoomSettingsController c;
  const MutedUsersPage({super.key, required this.c});

  @override
  State<MutedUsersPage> createState() => _MutedUsersPageState();
}

class _MutedUsersPageState extends State<MutedUsersPage> {
  String query = '';
  bool searchVisible = false;
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.c,
        builder: (context, _) {
          final items = widget.c.muted.where((row) {
            final name = (row['display_name'] ?? '').toString();
            final id = (row['public_id'] ?? '').toString();
            final q = query.trim().toLowerCase();
            return name.toLowerCase().contains(q) || id.toLowerCase().contains(q);
          }).toList();
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: RsAppBar(
              title: 'قائمة الكتم',
              actions: [
                IconButton(
                  tooltip: searchVisible ? 'إغلاق البحث' : 'بحث',
                  onPressed: () => setState(() {
                    searchVisible = !searchVisible;
                    if (!searchVisible) {
                      query = '';
                      searchController.clear();
                    }
                  }),
                  icon: Icon(
                    searchVisible ? Icons.close_rounded : Icons.search_rounded,
                    color: const Color(0xFFD4AF37),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                if (searchVisible) Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: (value) => setState(() => query = value),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو ID',
                      hintStyle: const TextStyle(color: RS.gray),
                      prefixIcon: const Icon(Icons.search, color: RS.gray),
                      filled: true,
                      fillColor: const Color(0xFFF6F7F8),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (widget.c.moderationError != null) HintBar(widget.c.moderationError!),
                Expanded(
                  child: widget.c.moderationLoading
                      ? const Center(child: CircularProgressIndicator(color: RS.primary))
                      : items.isEmpty
                          ? EmptyState(query.isEmpty ? 'لا يوجد مستخدمون مكتومون' : 'لا توجد نتائج مطابقة')
                          : ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: RS.divider),
                              itemBuilder: (context, index) {
                                final row = items[index];
                                final userId = (row['user_id'] ?? '').toString();
                                final name = (row['display_name'] ?? 'مستخدم').toString();
                                final publicId = (row['public_id'] ?? '').toString();
                                final avatar = (row['avatar_url'] ?? row['avatar'] ?? row['photo_url'] ?? row['profile_image'] ?? '').toString();
                                return ListTile(
                                  leading: ClipOval(
                                    child: SizedBox(
                                      width: 46,
                                      height: 46,
                                      child: avatar.isEmpty
                                          ? const ColoredBox(color: Color(0xFFF0F1F3), child: Icon(Icons.person, color: RS.gray))
                                          : HappyNetworkImage(
                                              avatar,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF0F1F3), child: Icon(Icons.person, color: RS.gray)),
                                            ),
                                    ),
                                  ),
                                  title: Text(name, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                                  subtitle: Text('ID: $publicId', style: const TextStyle(color: RS.gray, fontSize: 12)),
                                  trailing: TextButton(
                                    onPressed: userId.isEmpty ? null : () async {
                                      try {
                                        await widget.c.moderate('unmute', userId);
                                        if (context.mounted) showRsToast(context, 'تم إلغاء الكتم');
                                      } catch (e) {
                                        if (context.mounted) showRsToast(context, e.toString().replaceFirst('Exception: ', ''));
                                      }
                                    },
                                    child: const Text('إلغاء الكتم', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.w700)),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      );
}
