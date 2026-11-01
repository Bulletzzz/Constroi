import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/administracao/administracao_screen.dart';
import 'package:constroi_app/features/administracao/administracao_service.dart';
import 'package:constroi_app/navigation/app_route.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

Map<String, Object?> usuario(
  int id,
  String nome,
  String tipo, {
  bool ativo = true,
}) => {
  'id': id,
  'nome': nome,
  'email': '${nome.toLowerCase()}@empresa.test',
  'tipo': tipo,
  'ativo': ativo,
};

Map<String, Object?> evento(int id, int autor, String acao) => {
  'id': id,
  'usuario_id': autor,
  'acao': acao,
  'data': '2026-10-30T18:30:00.000Z',
};

Map<String, Object?> paginaDeLogs(
  List<Map<String, Object?>> logs, {
  bool temMais = false,
}) => {
  'logs': logs,
  'paginacao': {'limit': 50, 'offset': 0, 'tem_mais': temMais},
};

http.Response resposta(Object corpo, [int status = 200]) => http.Response(
  jsonEncode(corpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AdministracaoService service(
  Future<http.Response> Function(http.Request) responder,
) => AdministracaoService(
  api: ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient(responder),
  ),
);

Future<void> abrir(
  WidgetTester tester,
  AdministracaoService servico, {
  int? usuarioAtualId,
  Size tamanho = const Size(1200, 3200),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: AdministracaoScreen(
        service: servico,
        perfil: PerfilUsuario.master,
        usuarioAtualId: usuarioAtualId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('rota', () {
    test('so o master alcanca a administracao', () {
      expect(
        AppRoute.administracao.podeSerAcessadaPor(PerfilUsuario.master),
        isTrue,
      );
      expect(
        AppRoute.administracao.podeSerAcessadaPor(PerfilUsuario.engenheiro),
        isFalse,
      );
      expect(
        AppRoute.administracao.podeSerAcessadaPor(PerfilUsuario.pedreiro),
        isFalse,
      );
      expect(AppRoute.porCaminho('/administracao'), AppRoute.administracao);
    });
  });

  group('service', () {
    test('nao converte resposta invalida em lista vazia', () async {
      await expectLater(
        service((_) async => resposta({})).usuarios(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        service((_) async => resposta({'logs': []})).logs(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        service((_) async => resposta({'id': 1})).inativar(1),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        service((_) async => resposta({'erro': 'Sem acesso'}, 403)).usuarios(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('data_fim vai um dia a frente porque a API exclui o limite', () async {
      late Uri pedida;
      await service((pedido) async {
        pedida = pedido.url;
        return resposta(paginaDeLogs([]));
      }).logs(
        inicio: DateTime(2026, 10, 29),
        fim: DateTime(2026, 10, 31),
        usuarioId: 4,
        pagina: 2,
      );

      expect(pedida.queryParameters['data_inicio'], '2026-10-29');
      expect(pedida.queryParameters['data_fim'], '2026-11-01');
      expect(pedida.queryParameters['usuario_id'], '4');
      expect(pedida.queryParameters['limit'], '50');
      expect(pedida.queryParameters['offset'], '100');
    });

    test('fim no ultimo dia do mes atravessa para o mes seguinte', () {
      expect(diaParaApi(diaSeguinte(DateTime(2026, 12, 31))), '2027-01-01');
      expect(diaParaApi(diaSeguinte(DateTime(2028, 2, 28))), '2028-02-29');
    });

    test('filtro ausente nao entra na consulta', () async {
      late Uri pedida;
      await service((pedido) async {
        pedida = pedido.url;
        return resposta(paginaDeLogs([]));
      }).logs();

      expect(pedida.queryParameters.containsKey('data_inicio'), isFalse);
      expect(pedida.queryParameters.containsKey('data_fim'), isFalse);
      expect(pedida.queryParameters.containsKey('usuario_id'), isFalse);
      expect(pedida.queryParameters['offset'], '0');
    });

    test('evento e detalhe saem da acao gravada pela API', () {
      final registro = RegistroLog.fromJson(
        evento(9, 2, 'CRIACAO_PRODUTO produto=15'),
      );
      expect(registro.evento, 'CRIACAO_PRODUTO');
      expect(registro.detalhe, 'produto=15');
      expect(RegistroLog.fromJson(evento(9, 2, 'LOGIN')).detalhe, isEmpty);
    });
  });

  group('usuarios', () {
    testWidgets('lista perfis e marca quem esta inativo', (tester) async {
      await abrir(
        tester,
        service(
          (_) async => resposta({
            'usuarios': [
              usuario(1, 'Ana', 'master'),
              usuario(2, 'Bruno', 'engenheiro', ativo: false),
            ],
          }),
        ),
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Master'), findsOneWidget);
      expect(find.text('Engenheiro'), findsOneWidget);
      expect(find.text('INATIVO'), findsOneWidget);
      expect(find.text('1 ativos de 2'), findsOneWidget);
    });

    testWidgets('nao oferece inativar para quem esta usando a tela', (
      tester,
    ) async {
      await abrir(
        tester,
        service(
          (_) async => resposta({
            'usuarios': [usuario(1, 'Ana', 'master'), usuario(2, 'Bruno', 'pedreiro')],
          }),
        ),
        usuarioAtualId: 1,
      );

      expect(find.text('Você'), findsOneWidget);
      expect(find.text('INATIVAR'), findsOneWidget);
    });

    testWidgets('cadastra e acrescenta na lista em ordem', (tester) async {
      var criou = false;
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.method == 'POST') {
            criou = true;
            expect(
              jsonDecode(pedido.body),
              {
                'usuario': {
                  'nome': 'Ana Lima',
                  'email': 'ana@empresa.test',
                  'senha': 'senha-bem-longa',
                  'tipo': 'engenheiro',
                },
              },
            );
            return resposta(usuario(9, 'Ana Lima', 'engenheiro'), 201);
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'pedreiro')],
          });
        }),
      );

      await tocar(tester, find.text('NOVO USUÁRIO'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Lima');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@empresa.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'senha-bem-longa',
      );
      await tocar(tester, find.byType(DropdownButton<PerfilUsuario>));
      await tocar(tester, find.text('Engenheiro').last);
      await tocar(tester, find.text('SALVAR'));

      expect(criou, isTrue);
      expect(find.text('Ana Lima'), findsOneWidget);
      expect(find.text('2 ativos de 2'), findsOneWidget);
    });

    testWidgets('recusa senha curta antes de chamar a API', (tester) async {
      var chamouPost = false;
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.method == 'POST') chamouPost = true;
          return resposta({
            'usuarios': [usuario(1, 'Ana', 'master')],
          });
        }),
      );

      await tocar(tester, find.text('NOVO USUÁRIO'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Nova');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'nova@empresa.test',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'curta');
      await tocar(tester, find.text('SALVAR'));

      expect(chamouPost, isFalse);
      expect(
        find.text('A senha precisa de pelo menos 8 caracteres.'),
        findsOneWidget,
      );
    });

    testWidgets('mostra o erro da API no formulario', (tester) async {
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.method == 'POST') {
            return resposta({'erro': 'Email ja cadastrado.'}, 409);
          }
          return resposta({
            'usuarios': [usuario(1, 'Ana', 'master')],
          });
        }),
      );

      await tocar(tester, find.text('NOVO USUÁRIO'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Repetida');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@empresa.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'senha-bem-longa',
      );
      await tocar(tester, find.text('SALVAR'));

      expect(find.text('Email ja cadastrado.'), findsOneWidget);
    });

    testWidgets('inativar pede confirmacao e atualiza a linha', (tester) async {
      var inativou = false;
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.method == 'PATCH') {
            inativou = true;
            expect(pedido.url.path, endsWith('/usuarios/2/inativar'));
            return resposta(usuario(2, 'Bruno', 'pedreiro', ativo: false));
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'pedreiro')],
          });
        }),
      );

      await tocar(tester, find.text('INATIVAR'));
      expect(find.text('Inativar usuário'), findsOneWidget);

      await tocar(tester, find.text('Cancelar'));
      expect(inativou, isFalse);
      expect(find.text('INATIVO'), findsNothing);

      await tocar(tester, find.text('INATIVAR'));
      await tocar(tester, find.widgetWithText(TextButton, 'Inativar'));

      expect(inativou, isTrue);
      expect(find.text('INATIVO'), findsOneWidget);
      expect(find.text('0 ativos de 1'), findsOneWidget);
    });

    testWidgets('erro de carga oferece tentar de novo', (tester) async {
      var tentativas = 0;
      await abrir(
        tester,
        service((_) async {
          tentativas++;
          if (tentativas == 1) {
            return resposta({'erro': 'Banco indisponivel.'}, 503);
          }
          return resposta({
            'usuarios': [usuario(1, 'Ana', 'master')],
          });
        }),
      );

      expect(find.text('Banco indisponivel.'), findsOneWidget);
      await tocar(tester, find.text('Tentar novamente'));
      expect(find.text('Ana'), findsOneWidget);
    });
  });

  group('logs', () {
    testWidgets('aba de logs usa o nome do autor vindo da lista', (
      tester,
    ) async {
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.url.path.endsWith('/logs')) {
            return resposta(
              paginaDeLogs([
                evento(1, 2, 'CRIACAO_PRODUTO produto=15'),
                evento(2, 99, 'LOGIN usuario=99'),
              ]),
            );
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'engenheiro')],
          });
        }),
      );

      await tocar(tester, find.text('LOGS'));

      expect(find.text('CRIACAO_PRODUTO'), findsOneWidget);
      expect(find.text('produto=15'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Usuário #99'), findsOneWidget);
    });

    testWidgets('proxima pagina so habilita quando a API diz que ha mais', (
      tester,
    ) async {
      var temMais = true;
      final offsets = <String?>[];
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.url.path.endsWith('/logs')) {
            offsets.add(pedido.url.queryParameters['offset']);
            final atual = temMais;
            temMais = false;
            return resposta(
              paginaDeLogs([evento(1, 2, 'LOGIN usuario=2')], temMais: atual),
            );
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'engenheiro')],
          });
        }),
      );

      await tocar(tester, find.text('LOGS'));
      expect(find.text('página 1'), findsOneWidget);

      await tocar(tester, find.text('Próxima'));
      expect(offsets, ['0', '50']);
      expect(find.text('página 2'), findsOneWidget);

      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Próxima')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Anterior')).onPressed,
        isNotNull,
      );
    });

    testWidgets('inativar um usuario obriga a aba de logs a recarregar', (
      tester,
    ) async {
      var buscas = 0;
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.url.path.endsWith('/logs')) {
            buscas++;
            return resposta(
              paginaDeLogs([
                for (var i = 0; i < buscas; i++)
                  evento(i + 1, 2, 'LOGIN usuario=2'),
              ]),
            );
          }
          if (pedido.method == 'PATCH') {
            return resposta(usuario(2, 'Bruno', 'engenheiro', ativo: false));
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'engenheiro')],
          });
        }),
        usuarioAtualId: 9,
      );

      await tocar(tester, find.text('LOGS'));
      expect(buscas, 1);

      await tocar(tester, find.text('USUÁRIOS'));
      await tocar(tester, find.text('INATIVAR'));
      await tocar(tester, find.widgetWithText(TextButton, 'Inativar'));
      expect(find.text('INATIVO'), findsOneWidget);

      await tocar(tester, find.text('LOGS'));
      expect(buscas, 2);
      expect(find.text('LOGIN'), findsNWidgets(2));
    });

    testWidgets('filtro por autor volta para a primeira pagina', (
      tester,
    ) async {
      final consultas = <Map<String, String>>[];
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.url.path.endsWith('/logs')) {
            consultas.add(pedido.url.queryParameters);
            return resposta(
              paginaDeLogs([evento(1, 2, 'LOGIN usuario=2')], temMais: true),
            );
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'engenheiro')],
          });
        }),
      );

      await tocar(tester, find.text('LOGS'));
      await tocar(tester, find.text('Próxima'));
      expect(consultas.last['offset'], '50');

      await tocar(tester, find.byType(DropdownButton<int?>));
      await tocar(tester, find.text('Bruno').last);

      expect(consultas.last['offset'], '0');
      expect(consultas.last['usuario_id'], '2');
      expect(find.text('Limpar filtros'), findsOneWidget);
    });

    testWidgets('sem eventos mostra aviso em vez de lista vazia', (
      tester,
    ) async {
      await abrir(
        tester,
        service((pedido) async {
          if (pedido.url.path.endsWith('/logs')) {
            return resposta(paginaDeLogs([]));
          }
          return resposta({
            'usuarios': [usuario(2, 'Bruno', 'engenheiro')],
          });
        }),
      );

      await tocar(tester, find.text('LOGS'));

      expect(
        find.text('Nenhum evento registrado para este filtro.'),
        findsOneWidget,
      );
      expect(find.text('Próxima'), findsNothing);
    });
  });

  group('layout', () {
    for (final tamanho in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(1280, 800),
    ]) {
      testWidgets('sem overflow em $tamanho com texto ampliado', (
        tester,
      ) async {
        await abrir(
          tester,
          service((pedido) async {
            if (pedido.url.path.endsWith('/logs')) {
              return resposta(
                paginaDeLogs([
                  evento(1, 2, 'CRIACAO_PRODUTO produto=15'),
                  evento(2, 3, 'INATIVACAO_USUARIO usuario=3'),
                ], temMais: true),
              );
            }
            return resposta({
              'usuarios': [
                usuario(2, 'Bruno Carvalho Pereira', 'engenheiro'),
                usuario(3, 'Ana', 'pedreiro', ativo: false),
              ],
            });
          }),
          tamanho: tamanho,
          escala: 1.4,
        );

        expect(tester.takeException(), isNull);
        await tocar(tester, find.text('LOGS'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
