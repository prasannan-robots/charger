import 'package:flutter/material.dart';

import 'map.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Charger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF00A86B)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A86B),
        brightness: Brightness.dark,
      ),
      home: const MapScreen(),
    );
  }
}
