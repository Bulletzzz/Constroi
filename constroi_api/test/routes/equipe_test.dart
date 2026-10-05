import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/obras/[id]/equipe/index.dart' as route;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

Result _resultado({bool obraEncontrada = false}) {
  final schema = ResultSchema([
    ResultSchemaColumn(typeOid: 23, type: Type.integer, columnName: 'id'),
  ]);
  return Result(
    rows: [
      if (obraEncontrada) ResultRow(values: [7], schema: schema),
    ],
    affectedRows: 0,
    schema: schema,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Sql.named('SELECT 1')));

  for (final nivel in Nivel.values) {
    group('GET equipe como ${nivel.name}', () {
      late RequestContext contexto;
      late _BancoFalso banco;
      late List<Map<String, dynamic>> consultas;

      setUp(() {
        contexto = _ContextoFalso();
        banco = _BancoFalso();
        consultas = [];
        when(() => contexto.request).thenReturn(
          Request.get(Uri.parse('http://localhost/obras/7/equipe')),
        );
        when(() => contexto.read<Pool<void>>()).thenReturn(banco);
        when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
          UsuarioAutenticado(id: 3, empresaId: 2, nivel: nivel),
        );
      });

      void responder({required bool obraEncontrada}) {
        when(
          () => banco.execute(any(), parameters: any(named: 'parameters')),
        ).thenAnswer((invocacao) async {
          consultas.add(
            invocacao.namedArguments[#parameters]! as Map<String, dynamic>,
          );
          return _resultado(
            obraEncontrada: consultas.length == 1 && obraEncontrada,
          );
        });
      }

      test('obra inacessivel retorna 404 sem consultar membros', () async {
        responder(obraEncontrada: false);
        final resposta = await route.onRequest(contexto, '7');
        expect(resposta.statusCode, HttpStatus.notFound);
        expect(jsonDecode(await resposta.body()), {
          'erro': 'Obra nao encontrada.',
        });
        expect(consultas, hasLength(1));
        expect(consultas.single, {
          'obra': 7,
          'empresa': 2,
          'usuario': 3,
          'todas': nivel != Nivel.pedreiro,
        });
      });

      test('obra acessivel retorna equipe', () async {
        responder(obraEncontrada: true);
        final resposta = await route.onRequest(contexto, '7');
        expect(resposta.statusCode, HttpStatus.ok);
        expect(jsonDecode(await resposta.body()), {'equipe': <dynamic>[]});
        expect(consultas, hasLength(2));
        expect(consultas.first['todas'], nivel != Nivel.pedreiro);
        expect(consultas.last, {'obra': 7, 'empresa': 2});
      });
    });
  }
}
