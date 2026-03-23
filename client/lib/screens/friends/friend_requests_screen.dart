import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({Key? key}) : super(key: key);

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final ApiService api = ApiService();
  List<dynamic> _requests = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _requests = await api.getIncomingRequests();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('Нет входящих заявок'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (_, i) {
                    final r = _requests[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: r['sender']?['avatarUrl'] != null
                            ? NetworkImage(r['sender']['avatarUrl'])
                            : null,
                      ),
                      title: Text(r['sender']?['displayName'] ?? 'Unknown'),
                      subtitle: Text('Заявка'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              onPressed: () async {
                                await api.acceptRequest(r['id']);
                                _load();
                              },
                              icon: const Icon(Icons.check, color: Colors.green)),
                          IconButton(
                              onPressed: () async {
                                await api.deleteRequest(r['id']);
                                _load();
                              },
                              icon: const Icon(Icons.close, color: Colors.red)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
