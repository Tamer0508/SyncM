import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../widgets/friend_tile.dart';


class FriendsScreen extends StatelessWidget {
  const FriendsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<FriendsProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Friends'), actions: [
        IconButton(
            onPressed: () async {
              await prov.fetchFriends();
            },
            icon: const Icon(Icons.refresh))
      ]),
      body: prov.friends.isEmpty
          ? const Center(child: Text('Нет друзей. Нажмите обновить.'))
          : ListView.builder(
              itemCount: prov.friends.length,
              itemBuilder: (_, i) {
                final f = prov.friends[i];
                return FriendTile(name: f.name, avatarUrl: f.avatarUrl ?? '');
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
