import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/api_service.dart';
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
  final Set<String> _pendingRequests = {};

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
        _pendingRequests.clear();
      });
    } catch (e) {
      if (mounted) {
        final msg = (e is ApiException) ? e.userMessage : 'Ошибка поиска: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg))
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendRequest(String userId) async {
    if (_pendingRequests.contains(userId)) return;
    
    setState(() => _pendingRequests.add(userId));
    
    try {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      await prov.sendRequest(userId);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Заявка отправлена!'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(seconds: 2),
        )
      );
      
      setState(() {
        _results.removeWhere((user) => user.id == userId);
      });
      
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _pendingRequests.remove(userId));
      
      final msg = (e is ApiException) ? e.userMessage : 'Ошибка при отправке заявки';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        )
      );
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Введите имя пользователя',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                        ),
                        onSubmitted: _search,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _loading ? null : () => _search(_controller.text),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)
                          ),
                        ),
                        child: const Text(
                          'Найти',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary
                      )
                    )
                  : !_searched
                      ? Center(
                          child: Text(
                            'Введите имя пользователя и нажмите "Найти"',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      : _results.isEmpty
                          ? Center(
                              child: Text(
                                'Пользователи не найдены',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final u = _results[i];
                                final isPending = _pendingRequests.contains(u.id);
                                
                                return Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)
                                  ),
                                  elevation: 4,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16, 
                                      vertical: 8
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundImage: u.avatarUrl != null && 
                                              u.avatarUrl!.isNotEmpty
                                              ? NetworkImage(u.avatarUrl!)
                                              : null,
                                          child: u.avatarUrl == null || 
                                              u.avatarUrl!.isEmpty
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            u.name,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          height: 36,
                                          child: ElevatedButton(
                                            onPressed: isPending 
                                                ? null 
                                                : () => _sendRequest(u.id),
                                            style: ElevatedButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(18)
                                              ),
                                              backgroundColor: isPending 
                                                  ? theme.disabledColor 
                                                  : theme.colorScheme.primary,
                                            ),
                                            child: Text(
                                              isPending ? 'Отправлено' : 'Добавить',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isPending 
                                                    ? theme.colorScheme.onSurface.withOpacity(0.7)
                                                    : theme.colorScheme.onPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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