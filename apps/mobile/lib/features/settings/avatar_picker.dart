import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_controller.dart';
import '../../core/design_system/profile_avatar.dart';
import '../../core/design_system/theme.dart';

class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({super.key});
  @override
  ConsumerState<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<AvatarPicker> {
  String? selected;
  String style = '', error = '';
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appProvider).user;
    if (user == null) return const SizedBox.shrink();
    final chosen = selected ?? user.avatarId,
        choices = [
          '',
          ...avatarOptions.where(
            (id) => style.isEmpty || id.startsWith('${style}_'),
          ),
        ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(name: user.name, avatarId: chosen, size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your profile avatar',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${avatarOptions.length} avatars · ${avatarStyles.length} styles',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: const Text('All styles'),
                      selected: style.isEmpty,
                      onSelected: (_) => setState(() => style = ''),
                    ),
                  ),
                  for (final group in avatarStyles)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text('${group['label']} · ${group['count']}'),
                        selected: style == group['id'],
                        onSelected: (_) =>
                            setState(() => style = group['id'] as String),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              child: GridView.builder(
                primary: false,
                itemCount: choices.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 72,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final id = choices[index];
                  return Semantics(
                    label: avatarLabel(id),
                    selected: chosen == id,
                    button: true,
                    child: InkWell(
                      onTap: busy ? null : () => setState(() => selected = id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: chosen == id
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: ProfileAvatar(
                            name: user.name,
                            avatarId: id,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 10),
            ErrorNotice(error),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        await ref
                            .read(appProvider.notifier)
                            .updateAvatar(chosen);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile avatar saved.'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => error = 'Connect to save your profile. $e',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save avatar'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to save. All avatar styles are bundled for offline display.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
