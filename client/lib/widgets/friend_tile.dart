import 'package:flutter/material.dart';

class FriendTile extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const FriendTile({Key? key, required this.name, required this.avatarUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(radius: 22, backgroundImage: NetworkImage(avatarUrl), backgroundColor: Colors.grey[700]),
      title: Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: const Text('Online', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
      trailing: Icon(Icons.more_horiz, color: theme.iconTheme.color),
    );
  }
}
