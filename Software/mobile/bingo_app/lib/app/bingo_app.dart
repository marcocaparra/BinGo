import 'package:bingo_app/pages/initial_page.dart';
import 'package:flutter/material.dart';

class BingoApp extends StatelessWidget {
  const BingoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const lineColor = Color(0xFFE0E0E0);
    const textColor = Color(0xFF555555);

    return MaterialApp(
      title: 'BinGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: textColor,
          centerTitle: true,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: lineColor,
              width: 1,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: textColor,
            elevation: 0,
            side: const BorderSide(
              color: lineColor,
              width: 1,
            ),
          ),
        ),
      ),
      home: const InitialPage(),
    );
  }
}
