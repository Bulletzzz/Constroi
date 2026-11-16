import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/empresa.dart' as atalho;
import '../../routes/empresas.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _ArquivoFalso extends Mock implements File {}

void main() {
  late _ContextoFalso contexto;
  late _BancoFalso banco;
  late List<Map<String, Object?>> consultas;

  void requisicao(Object? corpo, [HttpMethod metodo = HttpMethod.post]) {
    when(() => contexto.request).thenReturn(
      Request(
        metodo.name.toUpperCase(),
        Uri.parse('http://localhost/empresas'),
        body: corpo is String ? corpo : jsonEncode(corpo),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  setUpAll(() => registerFallbackValue(Sql.named('SELECT 1')));

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    consultas = [];
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      consultas.add(
        Map<String, Object?>.from(chamada.namedArguments[#parameters] as Map),
      );
      return Result(rows: [], affectedRows: 0, schema: ResultSchema([]));
    });
  });

  group('tipos errados no corpo nao derrubam a rota', () {
    for (final corpo in <Map<String, Object?>>[
      {
        'empresa': {'nome': 123, 'cnpj': '11.111.111/0001-11'},
      },
      {
        'empresa': {'nome': 'Construtora', 'cnpj': <String>[]},
      },
      {
        'empresa': {'nome': true, 'cnpj': false},
      },
      {'nome_empresa': 7, 'cnpj': 9},
      {
        'empresa': {'nome': 'Construtora', 'cnpj': '11.111.111/0001-11'},
        'usuario': {'nome': 1, 'email': 2, 'senha': 3},
      },
    ]) {
      test('$corpo responde 400', () async {
        requisicao(corpo);
        final resposta = await rota.onRequest(contexto);
        expect(resposta.statusCode, HttpStatus.badRequest);
        expect(consultas, isEmpty);
      });
    }
  });

  test('JSON malformado responde 400 sem tocar o banco', () async {
    requisicao('{');
    expect(
      (await rota.onRequest(contexto)).statusCode,
      HttpStatus.badRequest,
    );
    expect(consultas, isEmpty);
  });

  test('corpo sem empresa responde 400', () async {
    requisicao(<String, Object?>{});
    expect(
      (await rota.onRequest(contexto)).statusCode,
      HttpStatus.badRequest,
    );
  });

  for (final metodo in [HttpMethod.get, HttpMethod.patch, HttpMethod.delete]) {
    test('${metodo.name} responde 405 sem tocar o banco', () async {
      requisicao(<String, Object?>{}, metodo);
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.methodNotAllowed,
      );
      expect(consultas, isEmpty);
    });
  }

  group('chave de cadastro', () {
    late _ArquivoFalso arquivo;

    setUp(() {
      arquivo = _ArquivoFalso();
      when(arquivo.existsSync).thenReturn(true);
    });

    Future<Response> comChaveNoAmbiente(
      String? doAmbiente,
      String? noCabecalho,
    ) async {
      when(arquivo.readAsLinesSync).thenReturn([
        if (doAmbiente != null) 'CHAVE_DE_CADASTRO=$doAmbiente',
      ]);
      when(() => contexto.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/empresas'),
          headers: {
            'content-type': 'application/json',
            if (noCabecalho != null) 'x-chave-de-cadastro': noCabecalho,
          },
          body: jsonEncode({
            'empresa': {'nome': 123, 'cnpj': 'x'},
          }),
        ),
      );
      return IOOverrides.runZoned(
        () => rota.onRequest(contexto),
        createFile: (_) => arquivo,
      )!;
    }

    test('sem a variavel o cadastro segue aberto', () async {
      final resposta = await comChaveNoAmbiente(null, null);
      expect(resposta.statusCode, HttpStatus.badRequest);
    });
  });

  test('o atalho /empresa usa o mesmo handler de /empresas', () async {
    requisicao({
      'empresa': {'nome': 123, 'cnpj': 'x'},
    });
    expect(
      (await atalho.onRequest(contexto)).statusCode,
      HttpStatus.badRequest,
    );
  });
}
