import 'package:constroi_app/main.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:constroi_app/widgets/app_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra a tela inicial com o tema Constrói', (tester) async {
    await tester.pumpWidget(const ConstroiApp());

    expect(find.text('CONSTRÓI'), findsOneWidget);
    expect(find.text('Acompanhe suas obras em um só lugar.'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      Theme.of(tester.element(find.byType(AppHome))).colorScheme.primary,
      AppTheme.accent,
    );
  });
}
