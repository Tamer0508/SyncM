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
      setState(() => _requests = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Requests'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('Нет входящих заявок'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (_, i) {
                    final r = _requests[i];
                    final sender = r['sender'] as Map<String, dynamic>?;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: sender?['avatarUrl'] != null
                            ? NetworkImage(sender!['avatarUrl'])
                            : null,
                        child: sender?['avatarUrl'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(sender?['displayName'] ?? 'Unknown'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () async {
                              final prov = Provider.of<FriendsProvider>(
                                  context, listen: false);
                              await prov.api.acceptRequest(r['id']);
                              _load();
                            },
                            icon: const Icon(Icons.check, color: Colors.green),
                          ),
                          IconButton(
                            onPressed: () async {
                              final prov = Provider.of<FriendsProvider>(
                                  context, listen: false);
                              await prov.api.deleteRequest(r['id']);
                              _load();
                            },
                            icon: const Icon(Icons.close, color: Colors.red),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}