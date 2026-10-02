import 'dart:convert';

import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/main.dart';
import 'package:constroi_app/navigation/app_bottom_navigation.dart';
import 'package:constroi_app/navigation/app_route.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/navigation/route_guard.dart';
import 'package:constroi_app/screens/module_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

String tokenDe(String tipo) {
  final cabecalho = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final corpo = base64Url.encode(
    utf8.encode(jsonEncode({'sub': '7', 'empresa_id': 3, 'tipo': tipo})),
  );
  return '$cabecalho.$corpo.assinatura';
}

MockClient semChamadas() =>
    MockClient((_) async => http.Response(jsonEncode({}), 200));

void main() {
  group('perfil do token', () {
    test('le os tres perfis aceitos pelo backend', () {
      expect(PerfilDoToken.ler(tokenDe('pedreiro')), PerfilUsuario.pedreiro);
      expect(
        PerfilDoToken.ler(tokenDe('engenheiro')),
        PerfilUsuario.engenheiro,
      );
      expect(PerfilDoToken.ler(tokenDe('master')), PerfilUsuario.master);
    });

    test('recusa token malformado ou perfil desconhecido', () {
      expect(PerfilDoToken.ler('token-invalido'), isNull);
      expect(PerfilDoToken.ler(tokenDe('visitante')), isNull);
    });
  });

  group('guarda de rota', () {
    test('pedreiro nao abre custos nem equipe', () {
      final guarda = RouteGuard.doToken(tokenDe('pedreiro'));

      expect(guarda.permite(AppRoute.painel), isTrue);
      expect(guarda.permite(AppRoute.estoque), isTrue);
      expect(guarda.permite(AppRoute.requisicoes), isTrue);
      expect(guarda.permite(AppRoute.custos), isFalse);
      expect(guarda.permite(AppRoute.equipe), isFalse);
      expect(guarda.destinoPermitido(AppRoute.equipe), AppRoute.painel);
    });

    test('engenheiro abre custos mas nao equipe', () {
      final guarda = RouteGuard.doToken(tokenDe('engenheiro'));

      expect(guarda.permite(AppRoute.custos), isTrue);
      expect(guarda.permite(AppRoute.equipe), isFalse);
    });

    test('master abre todas as rotas', () {
      final guarda = RouteGuard.doToken(tokenDe('master'));

      expect(AppRoute.values.every(guarda.permite), isTrue);
    });
  });

  testWidgets('menu esconde abas proibidas para pedreiro', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            rotaAtual: AppRoute.painel,
            perfil: PerfilUsuario.pedreiro,
          ),
        ),
      ),
    );

    expect(find.text('Painel'), findsOneWidget);
    expect(find.text('Estoque'), findsOneWidget);
    expect(find.text('Requisições'), findsOneWidget);
    expect(find.text('Custos'), findsNothing);
    expect(find.text('Equipe'), findsNothing);
  });

  testWidgets('rota nomeada permitida abre o modulo', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage()..token = tokenDe('engenheiro'),
        httpClient: semChamadas(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custos'));
    await tester.pumpAndSettle();

    expect(find.byType(ModuleScreen), findsOneWidget);
    expect(find.text('CUSTOS'), findsWidgets);
  });

  testWidgets('rota direta proibida volta ao painel', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage()..token = tokenDe('pedreiro'),
        httpClient: semChamadas(),
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(
      tester.element(find.byType(AppBottomNavigation)),
    ).pushReplacementNamed('/equipe');
    await tester.pumpAndSettle();

    expect(find.text('PAINEL'), findsWidgets);
    expect(find.text('EQUIPE'), findsNothing);
  });
}
