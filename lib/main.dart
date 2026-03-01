import 'package:flutter/material.dart';
import 'game/game_page.dart';

void main() {
  runApp(const TypeInvadersApp());
}

class TypeInvadersApp extends StatelessWidget {
  const TypeInvadersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Typing Invaders',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}