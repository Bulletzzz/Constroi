import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/[id].dart' as detalhe;
import '../../routes/pedidos/_middleware.dart' as protecao;
import '../../routes/pedidos/index.dart' as lista;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _LinhaFalsa extends Mock implements ResultRow {}

Result _resultado(List<Map<String, dynamic>> dados) => Result(
  rows: dados.map((dados) {
    final linha = _LinhaFalsa();
    when(linha.toColumnMap).thenReturn(dados);
    return linha;
  }).toList(),
  affectedRows: dados.length,
  schema: ResultSchema([]),
);

void main() {
  late _ContextoFalso contexto;
  late _BancoFalso banco;
  late List<Result> resultados;
  late List<Map<String, Object?>> parametros;
  late Map<String, dynamic> pedido;

  void requisicao(String caminho) {
    when(() => contexto.request).thenReturn(
      Request.get(Uri.parse('http://localhost$caminho')),
    );
  }

  void autenticar(Nivel nivel) {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
    );
  }

  setUpAll(() {
    registerFallbackValue(Sql.named(''));
    registerFallbackValue(() => gerarProtocolo);
  });

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    parametros = [];
    pedido = {
      'id': 30,
      'usuario_id': 7,
      'obra_id': 10,
      'protocolo': 'PED-0123456789ABCDEF0123456789ABCDEF',
      'status': 'pendente',
      'justificativa': null,
      'data': DateTime.utc(2026, 10, 4),
    };
    resultados = [
      _resultado([pedido]),
    ];
    autenticar(Nivel.pedreiro);
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => contexto.provide<GeradorProtocolo>(any())).thenReturn(contexto);
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      parametros.add(
        Map<String, Object?>.from(chamada.namedArguments[#parameters] as Map),
      );
      return resultados.removeAt(0);
    });
    requisicao('/pedidos');
  });

  group('GET /pedidos', () {
    for (final nivel in Nivel.values) {
      test('aplica empresa e visibilidade do perfil ${nivel.name}', () async {
        autenticar(nivel);
        final resposta = await protecao.middleware(lista.onRequest)(contexto);
        final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
        expect(resposta.statusCode, HttpStatus.ok);
        expect(corpo['pedidos'], [
          {...pedido, 'data': '2026-10-04T00:00:00.000Z'},
        ]);
        expect(parametros.single, {
          'empresa': 3,
          'usuario': 7,
          'todos': nivel != Nivel.pedreiro,
        });
      });
    }

    test('combina filtros e normaliza status e protocolo', () async {
      requisicao(
        '/pedidos?obra_id=10&status=%20PENDENTE%20&protocolo=%20ped-abc%20',
      );
      final resposta = await lista.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.ok);
      expect(parametros.single, {
        'empresa': 3,
        'usuario': 7,
        'todos': false,
        'obra': 10,
        'status': 'pendente',
        'protocolo': 'PED-ABC',
      });
    });

    for (final filtro in [
      ('obra_id=10', 'obra', 10),
      ('status=pendente', 'status', 'pendente'),
      ('protocolo=ped-abc', 'protocolo', 'PED-ABC'),
    ]) {
      test('aceita filtro isolado ${filtro.$2}', () async {
        requisicao('/pedidos?${filtro.$1}');
        expect((await lista.onRequest(contexto)).statusCode, HttpStatus.ok);
        expect(parametros.single[filtro.$2], filtro.$3);
        expect(parametros.single, hasLength(4));
      });
    }

    test('retorna lista vazia quando nenhum pedido e visivel', () async {
      resultados = [_resultado([])];
      requisicao('/pedidos?protocolo=PED-DE-OUTRO-USUARIO');
      final resposta = await lista.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.ok);
      expect(jsonDecode(await resposta.body()), {'pedidos': <Object?>[]});
      expect(parametros.single['todos'], isFalse);
      expect(parametros.single['usuario'], 7);
      expect(parametros.single['empresa'], 3);
    });

    test('recusa filtros invalidos antes de acessar o banco', () async {
      for (final filtro in [
        'obra_id=',
        'obra_id=abc',
        'obra_id=0',
        'obra_id=-1',
        'obra_id=1.5',
        'obra_id=2147483648',
        'status=',
        'status=%20',
        'status=${'a' * 31}',
        'protocolo=',
        'protocolo=%20',
        'protocolo=${'a' * 51}',
      ]) {
        requisicao('/pedidos?$filtro');
        final resposta = await lista.onRequest(contexto);
        expect(resposta.statusCode, HttpStatus.badRequest, reason: filtro);
      }
      verifyNever(
        () => banco.execute(any(), parameters: any(named: 'parameters')),
      );
    });

    test(
      'filtros de usuario e empresa nao alteram o escopo do token',
      () async {
        requisicao('/pedidos?usuario_id=99&empresa_id=99&todos=true');
        expect((await lista.onRequest(contexto)).statusCode, HttpStatus.ok);
        expect(parametros.single, {'empresa': 3, 'usuario': 7, 'todos': false});
      },
    );

    test('sem token retorna 401 sem consultar o banco', () async {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
      final resposta = await protecao.middleware(lista.onRequest)(contexto);
      expect(resposta.statusCode, HttpStatus.unauthorized);
      expect(parametros, isEmpty);
    });
  });

  group('GET /pedidos/{id}', () {
    for (final nivel in Nivel.values) {
      test('retorna itens com visibilidade do perfil ${nivel.name}', () async {
        autenticar(nivel);
        requisicao('/pedidos/30');
        resultados.add(
          _resultado([
            {
              'id': 40,
              'produto_id': 20,
              'produto_nome': 'Cimento',
              'unidade': 'saco',
              'quantidade': '2.50',
            },
            {
              'id': 41,
              'produto_id': 21,
              'produto_nome': 'Areia',
              'unidade': 'm3',
              'quantidade': '1.00',
            },
          ]),
        );
        final resposta = await protecao.middleware(
          (contexto) => detalhe.onRequest(contexto, '30'),
        )(contexto);
        final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
        expect(resposta.statusCode, HttpStatus.ok);
        expect(corpo['protocolo'], pedido['protocolo']);
        expect(corpo['data'], '2026-10-04T00:00:00.000Z');
        expect(corpo['itens'], [
          {
            'id': 40,
            'produto_id': 20,
            'produto_nome': 'Cimento',
            'unidade': 'saco',
            'quantidade': '2.50',
          },
          {
            'id': 41,
            'produto_id': 21,
            'produto_nome': 'Areia',
            'unidade': 'm3',
            'quantidade': '1.00',
          },
        ]);
        expect(parametros.first, {
          'id': 30,
          'empresa': 3,
          'usuario': 7,
          'todos': nivel != Nivel.pedreiro,
        });
        expect(parametros.last, {'pedido': 30, 'empresa': 3});
      });

      test(
        'pedido ausente ou nao visivel retorna 404 para ${nivel.name}',
        () async {
          autenticar(nivel);
          resultados = [_resultado([])];
          final resposta = await detalhe.onRequest(contexto, '30');
          expect(resposta.statusCode, HttpStatus.notFound);
          expect(jsonDecode(await resposta.body()), {
            'erro': 'Pedido nao encontrado.',
          });
          expect(parametros, hasLength(1));
          expect(parametros.single['empresa'], 3);
          expect(parametros.single['todos'], nivel != Nivel.pedreiro);
        },
      );
    }

    test('recusa IDs invalidos sem consultar o banco', () async {
      for (final id in ['', 'abc', '0', '-1', '1.5', '2147483648']) {
        expect(
          (await detalhe.onRequest(contexto, id)).statusCode,
          HttpStatus.badRequest,
          reason: id,
        );
      }
      expect(parametros, isEmpty);
    });

    test('sem token retorna 401 sem consultar pedido ou itens', () async {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
      final resposta = await protecao.middleware(
        (contexto) => detalhe.onRequest(contexto, '30'),
      )(contexto);
      expect(resposta.statusCode, HttpStatus.unauthorized);
      expect(parametros, isEmpty);
    });

    test('metodo diferente de GET retorna 405', () async {
      when(() => contexto.request).thenReturn(
        Request.post(Uri.parse('http://localhost/pedidos/30')),
      );
      expect(
        (await detalhe.onRequest(contexto, '30')).statusCode,
        HttpStatus.methodNotAllowed,
      );
      expect(parametros, isEmpty);
    });
  });
}
