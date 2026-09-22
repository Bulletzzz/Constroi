import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'widgets/app_home.dart';

void main() => runApp(const ConstroiApp());

class ConstroiApp extends StatelessWidget {
  const ConstroiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Constrói',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: const AppHome(),
  );
}
