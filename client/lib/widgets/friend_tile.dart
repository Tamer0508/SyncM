import 'package:flutter/material.dart';

class FriendTile extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const FriendTile({Key? key, required this.name, required this.avatarUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundImage: NetworkImage(avatarUrl)),
      title: Text(name),
    );
  }
}
