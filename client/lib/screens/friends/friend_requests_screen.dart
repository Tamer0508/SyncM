import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({Key? key}) : super(key: key);

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      final result = await prov.getIncomingRequests();
      if (!mounted) return;
      setState(() => _requests = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
      appBar: AppBar(
        title: const Text('Запросы в друзья'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
            : _requests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mark_email_read, size: 64, color: theme.colorScheme.primary.withOpacity(0.8)),
                        const SizedBox(height: 16),
                        Text('Запросов нет', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Попросите друзей отправить вам запрос, чтобы начать общение.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.75)), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, i) {
                      final r = _requests[i];
                      final sender = r['sender'] as Map<String, dynamic>?;
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 28,
                              backgroundImage: sender?['avatarUrl'] != null ? NetworkImage(sender!['avatarUrl']) : null,
                              child: sender?['avatarUrl'] == null ? const Icon(Icons.person) : null,
                            ),
                            title: Text(sender?['displayName'] ?? 'Unknown', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            subtitle: Text('Хочет добавить вас в друзья', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78))),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () async {
                                    final prov = Provider.of<FriendsProvider>(context, listen: false);
                                    await prov.api.acceptRequest(r['id']);
                                    _load();
                                  },
                                  icon: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    final prov = Provider.of<FriendsProvider>(context, listen: false);
                                    await prov.api.deleteRequest(r['id']);
                                    _load();
                                  },
                                  icon: Icon(Icons.close, color: theme.colorScheme.error),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
