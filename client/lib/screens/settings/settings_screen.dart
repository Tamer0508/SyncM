import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  final bool embedded;
  const SettingsScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'Внешний вид'),
              Tab(text: 'Приватность'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AppearanceTab(),
                _PrivacyTab(),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: content,
    );
  }
}

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Оформление',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Системная'),
                  leading: Radio<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: themeProvider.themeMode,
                    onChanged: (v) => themeProvider.setThemeMode(v!),
                  ),
                ),
                ListTile(
                  title: const Text('Светлая'),
                  leading: Radio<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: themeProvider.themeMode,
                    onChanged: (v) => themeProvider.setThemeMode(v!),
                  ),
                ),
                ListTile(
                  title: const Text('Тёмная'),
                  leading: Radio<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: themeProvider.themeMode,
                    onChanged: (v) => themeProvider.setThemeMode(v!),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Профиль',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: auth.user?.displayName ?? '',
                  decoration: const InputDecoration(labelText: 'Имя'),
                  onFieldSubmitted: (val) async {
                    try {
                      await auth.updateProfile(username: val.trim());
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Замена URL поля на кнопку загрузки
                InkWell(
                  onTap: () async {
                    final picker = ImagePicker();
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      maxHeight: 512,
                    );
                    if (image != null) {
                      try {
                        await auth.uploadAvatar(image.path);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.photo_camera, size: 20),
                        SizedBox(width: 8),
                        Text('Выбрать фото'),
                      ],
                    ),
                  ),
                ),
                if (auth.user?.avatarUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(auth.user!.avatarUrl!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Приватность',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Скрыть количество друзей'),
                  subtitle: const Text('Никто не увидит количество ваших друзей и общих друзей'),
                  value: user?.isFriendsHidden ?? false,
                  onChanged: (val) async {
                    try {
                      await auth.updateSettings({'isFriendsHidden': val});
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Скрыть активность'),
                  subtitle: const Text('Ваша активность в сессиях не будет видна другим'),
                  value: user?.isActivityHidden ?? false,
                  onChanged: (val) async {
                    try {
                      await auth.updateSettings({'isActivityHidden': val});
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Скрыть онлайн-статус'),
                  subtitle: const Text('Друзья не увидят, когда вы в сети'),
                  value: user?.isOnlineHidden ?? false,
                  onChanged: (val) async {
                    try {
                      await auth.updateSettings({'isOnlineHidden': val});
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}