import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../models/friend.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({Key? key}) : super(key: key);

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _controller = TextEditingController();
  List<Friend> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _searched = false;
        _results = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      final res = await prov.search(q);
      if (!mounted) return;
      setState(() {
        _searched = true;
        _results = res;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка поиска: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск пользователей')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Введите имя',
                          prefixIcon: const Icon(Icons.search),
                          border: InputBorder.none,
                        ),
                        onSubmitted: _search,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => _search(_controller.text),
                      child: const Text('Найти'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                  : !_searched
                      ? Center(
                          child: Text(
                            'Введите ник пользователя и нажмите "Найти"',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      : _results.isEmpty
                      ? Center(
                          child: Text('Ничего не найдено', style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8))),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final u = _results[i];
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 4,
                              child: ListTile(
                                leading: u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                                    ? CircleAvatar(backgroundImage: NetworkImage(u.avatarUrl!))
                                    : const CircleAvatar(child: Icon(Icons.person)),
                                title: Text(u.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                trailing: ElevatedButton(
                                  onPressed: () async {
                                    final prov = Provider.of<FriendsProvider>(context, listen: false);
                                    try {
                                      await prov.sendRequest(u.id);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заявка отправлена')));
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                                  child: const Text('Добавить'),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
