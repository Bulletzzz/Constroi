import 'dart:convert';
import 'dart:io';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/auth_service.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/core/auth/token_storage.dart';
import 'package:constroi_app/screens/login_screen.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage implements TokenStorage {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}

const _respostaDeSucesso = {
  'token': 'jwt-de-teste',
  'expira_em': '2026-10-01T00:00:00.000Z',
  'refresh_token': 'refresh-de-teste',
  'usuario': {
    'id': 7,
    'nome': 'Eduardo',
    'email': 'eduardo@constroi.test',
    'tipo': 'engenheiro',
    'empresa_id': 3,
  },
};

({
  SessionManager sessoes,
  MemoryTokenStorage cofre,
  AuthService auth,
  List<Map<String, dynamic>> enviados,
})
montar(http.Response Function(http.Request) responder) {
  final cofre = MemoryTokenStorage();
  final sessoes = SessionManager(cofre);
  final enviados = <Map<String, dynamic>>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: sessoes,
    httpClient: MockClient((requisicao) async {
      if (requisicao.body.isNotEmpty) {
        enviados.add(jsonDecode(requisicao.body) as Map<String, dynamic>);
      }
      return responder(requisicao);
    }),
  );
  return (
    sessoes: sessoes,
    cofre: cofre,
    auth: AuthService(api: api, sessions: sessoes),
    enviados: enviados,
  );
}

Future<void> abrir(WidgetTester tester, AuthService auth) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: LoginScreen(auth: auth)),
  );
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> preencher(
  WidgetTester tester, {
  required String email,
  required String senha,
}) async {
  await tester.enterText(find.byType(TextField).at(0), email);
  await tester.enterText(find.byType(TextField).at(1), senha);
}

void main() {
  testWidgets('desenha os elementos do Figma 01', (tester) async {
    final tudo = montar((_) => http.Response('{}', 200));
    await abrir(tester, tudo.auth);

    expect(find.text('ÁREA DE ACESSO'), findsOneWidget);
    expect(find.text('AUTORIZAÇÃO NECESSÁRIA'), findsOneWidget);
    expect(find.text('EMAIL DO OPERADOR'), findsOneWidget);
    expect(find.text('SENHA DE SEGURANÇA'), findsOneWidget);
    expect(find.text('REDEFINIR SENHA'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('ENTRAR'), findsOneWidget);
    expect(
      find.textContaining('Sistema de acesso restrito'),
      findsOneWidget,
    );
  });

  testWidgets('campos vazios nao chamam a API', (tester) async {
    var chamou = false;
    final tudo = montar((_) {
      chamou = true;
      return http.Response('{}', 200);
    });
    await abrir(tester, tudo.auth);

    await tocar(tester, find.text('ENTRAR'));

    expect(chamou, isFalse);
    expect(find.text('Informe o e-mail e a senha.'), findsOneWidget);
  });

  testWidgets('senha errada mostra mensagem que nao entrega o email', (
    tester,
  ) async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({'erro': 'Email ou senha invalidos.'}),
        401,
      ),
    );
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'alguem@constroi.test', senha: 'errada');
    await tocar(tester, find.text('ENTRAR'));

    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(tudo.sessoes.isSignedIn, isFalse);
  });

  testWidgets('erro interno do servidor nao vaza para a tela', (tester) async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({'erro': 'Servidor sem JWT_SECRET.'}),
        503,
      ),
    );
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'a@b.com', senha: 'Senha#Forte123');
    await tocar(tester, find.text('ENTRAR'));

    expect(find.text('Servidor sem JWT_SECRET.'), findsNothing);
    expect(find.textContaining('Não foi possível entrar agora'), findsOneWidget);
  });

  testWidgets('usuario inativo mostra o motivo real', (tester) async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({'erro': 'Usuario inativo. Procure o administrador.'}),
        403,
      ),
    );
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'a@b.com', senha: 'Senha#Forte123');
    await tocar(tester, find.text('ENTRAR'));

    expect(
      find.text('Usuario inativo. Procure o administrador.'),
      findsOneWidget,
    );
  });

  testWidgets('bloqueio por tentativas mostra o motivo real', (tester) async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({'erro': 'Muitas tentativas. Tente novamente mais tarde.'}),
        429,
      ),
    );
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'a@b.com', senha: 'Senha#Forte123');
    await tocar(tester, find.text('ENTRAR'));

    expect(
      find.text('Muitas tentativas. Tente novamente mais tarde.'),
      findsOneWidget,
    );
  });

  testWidgets('perfil malformado nao derruba o login', (tester) async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({
          'token': 'jwt-de-teste',
          'usuario': {'id': null, 'empresa_id': 'abc'},
        }),
        200,
      ),
    );
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'a@b.com', senha: 'Senha#Forte123');
    await tocar(tester, find.text('ENTRAR'));

    expect(tudo.sessoes.isSignedIn, isTrue);
    expect(tudo.sessoes.accessToken, 'jwt-de-teste');
    expect(tudo.sessoes.session?.user, isNull);
  });

  testWidgets('login certo abre a sessao e manda email e senha', (
    tester,
  ) async {
    final tudo = montar(
      (_) => http.Response(jsonEncode(_respostaDeSucesso), 200),
    );
    await abrir(tester, tudo.auth);

    await preencher(
      tester,
      email: '  eduardo@constroi.test ',
      senha: 'Senha#Forte123',
    );
    await tocar(tester, find.text('ENTRAR'));

    expect(tudo.sessoes.isSignedIn, isTrue);
    expect(tudo.sessoes.accessToken, 'jwt-de-teste');
    expect(tudo.sessoes.session?.user?.tipo, 'engenheiro');
    expect(tudo.enviados.single, {
      'email': 'eduardo@constroi.test',
      'senha': 'Senha#Forte123',
    });
  });

  testWidgets('o token nunca fica guardado em disco', (tester) async {
    final tudo = montar(
      (_) => http.Response(jsonEncode(_respostaDeSucesso), 200),
    );
    tudo.cofre.token = 'sobra-de-versao-antiga';
    await abrir(tester, tudo.auth);

    await preencher(tester, email: 'a@b.com', senha: 'Senha#Forte123');
    await tocar(tester, find.text('ENTRAR'));

    expect(tudo.sessoes.isSignedIn, isTrue);
    expect(tudo.cofre.token, isNull);
  });

  test('token guardado valido abre a sessao e carrega o perfil', () async {
    final tudo = montar(
      (_) => http.Response(
        jsonEncode({
          'id': 7,
          'nome': 'Eduardo',
          'email': 'eduardo@constroi.test',
          'tipo': 'engenheiro',
          'empresa_id': 3,
        }),
        200,
      ),
    );
    tudo.cofre.token = 'jwt-guardado';

    await tudo.auth.restaurar();

    expect(tudo.sessoes.isSignedIn, isTrue);
    expect(tudo.sessoes.session?.user?.nome, 'Eduardo');
  });

  test('token guardado invalido volta para o login', () async {
    final tudo = montar(
      (_) => http.Response(jsonEncode({'erro': 'Token expirado.'}), 401),
    );
    tudo.cofre.token = 'jwt-vencido';

    await tudo.auth.restaurar();

    expect(tudo.sessoes.isSignedIn, isFalse);
    expect(tudo.cofre.token, isNull);
  });

  test('api fora do ar nao desloga quem ja estava dentro', () async {
    final tudo = montar((_) => throw const SocketException('sem rede'));
    tudo.cofre.token = 'jwt-guardado';

    await tudo.auth.restaurar();

    expect(tudo.sessoes.isSignedIn, isTrue);
  });

  testWidgets('redefinir senha avisa que e o administrador', (tester) async {
    final tudo = montar((_) => http.Response('{}', 200));
    await abrir(tester, tudo.auth);

    await tocar(tester, find.text('REDEFINIR SENHA'));

    expect(
      find.textContaining('administrador da empresa'),
      findsOneWidget,
    );
  });
}
