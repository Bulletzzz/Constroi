import 'dart:convert';

import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session.dart';
import 'package:constroi_app/main.dart';
import 'package:constroi_app/navigation/app_bottom_navigation.dart';
import 'package:constroi_app/navigation/app_route.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/navigation/route_guard.dart';
import 'package:constroi_app/screens/module_screen.dart';
import 'package:constroi_app/widgets/app_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

AppUser usuarioDe(String tipo) => AppUser(
  id: 7,
  empresaId: 3,
  nome: 'Operador',
  email: 'operador@example.test',
  tipo: tipo,
);

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
  group('perfil do JWT usado como fallback', () {
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

  group('perfil da sessao', () {
    test('usuario da sessao prevalece quando o JWT tem outro tipo', () {
      for (final perfil in PerfilUsuario.values) {
        for (final perfilAntigo in PerfilUsuario.values) {
          if (perfil == perfilAntigo) continue;
          final sessao = AppSession(
            accessToken: tokenDe(perfilAntigo.name),
            user: usuarioDe(perfil.name),
          );

          expect(PerfilDaSessao.ler(sessao), perfil);
          expect(RouteGuard.daSessao(sessao).perfil, perfil);
        }
      }
    });

    test('sem usuario na sessao usa o perfil do JWT valido', () {
      for (final perfil in PerfilUsuario.values) {
        final sessao = AppSession(accessToken: tokenDe(perfil.name));

        expect(sessao.user, isNull);
        expect(PerfilDaSessao.ler(sessao), perfil);
        expect(RouteGuard.daSessao(sessao).perfil, perfil);
      }
    });

    test('usuario com perfil desconhecido nao herda privilegios do JWT', () {
      final sessao = AppSession(
        accessToken: tokenDe('master'),
        user: usuarioDe('visitante'),
      );

      expect(PerfilDaSessao.ler(sessao), isNull);
      expect(AppRoute.values.any(RouteGuard.daSessao(sessao).permite), isFalse);
    });

    test('sem sessao ou sem JWT valido nao libera rotas', () {
      expect(PerfilDaSessao.ler(null), isNull);
      expect(
        PerfilDaSessao.ler(const AppSession(accessToken: 'invalido')),
        isNull,
      );
      expect(AppRoute.values.any(RouteGuard.daSessao(null).permite), isFalse);
    });
  });

  group('guarda de rota', () {
    test('pedreiro nao abre custos mas pode ler equipe', () {
      final guarda = RouteGuard.daSessao(
        AppSession(accessToken: tokenDe('pedreiro')),
      );

      expect(guarda.permite(AppRoute.painel), isTrue);
      expect(guarda.permite(AppRoute.estoque), isTrue);
      expect(guarda.permite(AppRoute.requisicoes), isTrue);
      expect(guarda.permite(AppRoute.custos), isFalse);
      expect(guarda.permite(AppRoute.equipe), isTrue);
      expect(guarda.destinoPermitido(AppRoute.equipe), AppRoute.equipe);
    });

    test('engenheiro abre custos e equipe', () {
      final guarda = RouteGuard.daSessao(
        AppSession(
          accessToken: tokenDe('master'),
          user: usuarioDe('engenheiro'),
        ),
      );

      expect(guarda.perfil, PerfilUsuario.engenheiro);
      expect(guarda.permite(AppRoute.custos), isTrue);
      expect(guarda.permite(AppRoute.equipe), isTrue);
    });

    test('master abre todas as rotas', () {
      final guarda = RouteGuard.daSessao(
        AppSession(accessToken: tokenDe('pedreiro'), user: usuarioDe('master')),
      );

      expect(AppRoute.values.every(guarda.permite), isTrue);
    });
  });

  testWidgets('menu mostra equipe e esconde custos para pedreiro', (
    tester,
  ) async {
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
    expect(find.text('Equipe'), findsOneWidget);
  });

  for (final perfil in PerfilUsuario.values) {
    testWidgets(
      'menu de ${perfil.name} suporta tela estreita e fonte ampliada',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2.5)),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: AppBottomNavigation(
                rotaAtual: AppRoute.painel,
                perfil: perfil,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final rota in AppRoute.values.where(
          (rota) => rota.podeSerAcessadaPor(perfil),
        )) {
          final rotulo = tester.widget<Text>(find.text(rota.rotulo));
          expect(rotulo.maxLines, 1);
          expect(rotulo.overflow, TextOverflow.ellipsis);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    ).pushReplacementNamed('/custos');
    await tester.pumpAndSettle();

    expect(find.byType(AppHome), findsOneWidget);
    expect(find.text('EQUIPE'), findsNothing);
  });
}
