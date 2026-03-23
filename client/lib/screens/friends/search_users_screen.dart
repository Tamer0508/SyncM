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

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      final res = await prov.search(q);
      setState(() => _results = res);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка поиска: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                    child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Введите имя'),
                )),
                IconButton(onPressed: () => _search(_controller.text), icon: const Icon(Icons.search))
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('Нет результатов'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final u = _results[i];
                          return ListTile(
                            leading: u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                                ? CircleAvatar(backgroundImage: NetworkImage(u.avatarUrl!))
                                : const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(u.name),
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
                              child: const Text('Add'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}