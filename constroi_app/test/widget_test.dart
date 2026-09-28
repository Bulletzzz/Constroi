import 'dart:convert';

import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/main.dart';
import 'package:constroi_app/screens/login_screen.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:constroi_app/widgets/app_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

MockClient _semChamadas() =>
    MockClient((_) async => http.Response(jsonEncode({}), 200));

void main() {
  testWidgets('sem sessao guardada o app abre no login', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage(),
        httpClient: _semChamadas(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('ÁREA DE ACESSO'), findsOneWidget);
    expect(find.byType(AppHome), findsNothing);
  });

  testWidgets('com token guardado o app abre no painel', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage()..token = 'jwt-guardado',
        httpClient: _semChamadas(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppHome), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('CONSTRÓI'), findsOneWidget);
  });

  testWidgets('sem API_BASE_URL explica como rodar', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(storage: MemoryTokenStorage(), httpClient: _semChamadas()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Falta configurar o endereço da API'), findsOneWidget);
    expect(find.textContaining('--dart-define=API_BASE_URL'), findsOneWidget);
  });

  testWidgets('mantem o tema Constrói', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage(),
        httpClient: _semChamadas(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(LoginScreen))).colorScheme.primary,
      AppTheme.accent,
    );
  });
}
