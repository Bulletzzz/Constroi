import 'package:flutter/material.dart';

import 'app_header.dart';
import 'base_card.dart';

class AppHome extends StatelessWidget {
  const AppHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppHeader(title: 'CONSTRÓI'),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: BaseCard(child: Text('Acompanhe suas obras em um só lugar.')),
        ),
      ),
    ),
  );
}
