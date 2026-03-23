import 'package:flutter/material.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black12,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: const [
          Icon(Icons.play_arrow),
          SizedBox(width: 8),
          Expanded(child: Text('Current track')),
        ],
      ),
    );
  }
}
