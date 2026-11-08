import 'dart:convert';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/emprestimos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../routes/emprestimos/[id].dart' as devolucao;
import '../routes/emprestimos/_middleware.dart' as protecao;
import '../routes/emprestimos/index.dart' as emprestimos;

class _Contexto extends Mock implements RequestContext {}

void main() {
  late _Contexto contexto;
  setUp(() {
    contexto = _Contexto();
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      const UsuarioAutenticado(id: 2, empresaId: 1, nivel: Nivel.engenheiro),
    );
  });
  void requisicao(String metodo, String caminho, [Object? corpo]) {
    when(() => contexto.request).thenReturn(
      Request(
        metodo,
        Uri.parse('http://localhost$caminho'),
        body: corpo == null ? null : jsonEncode(corpo),
      ),
    );
  }

  void semBanco() => verifyNever(() => contexto.read<Pool<void>>());

  test('IDs e dias exigem inteiro positivo dentro do INTEGER do banco', () {
    expect(validarIdEmprestimo(1), 1);
    expect(validarIdEmprestimo(4000), 4000);
    expect(validarIdEmprestimo(2147483647), 2147483647);
    for (final valor in [null, 0, -1, '1', 1.0, true, 2147483648]) {
      expect(validarIdEmprestimo(valor), isNull);
    }
  });

  test('datas do contrato sao ISO em UTC e devolucao admite null', () {
    final dados = dadosDoEmprestimo({
      'id': 1,
      'data_emprestimo': DateTime.parse('2026-10-01T10:00:00-03:00'),
      'data_prevista': DateTime.parse('2026-10-03T10:00:00-03:00'),
      'data_devolucao': null,
      'status': 'aberto',
      'atrasado': false,
    });
    expect(dados['data_emprestimo'], '2026-10-01T13:00:00.000Z');
    expect(dados['data_prevista'], '2026-10-03T13:00:00.000Z');
    expect(dados['data_devolucao'], isNull);
  });

  test('POST invalido e recusado antes de abrir transacao', () async {
    for (final corpo in [
      <Object?>[],
      <String, dynamic>{},
      {'emprestimo': null},
      {
        'emprestimo': {'equipamento_id': 1},
      },
      {
        'emprestimo': {
          'equipamento_id': 1,
          'usuario_id': 3,
          'obra_id': 1,
          'dias': 0,
        },
      },
    ]) {
      requisicao('POST', '/emprestimos', corpo);
      expect((await emprestimos.onRequest(contexto)).statusCode, 400);
    }
    semBanco();
  });

  test('filtros invalidos nao consultam o banco', () async {
    for (final filtro in [
      'equipamento_id=',
      'equipamento_id=2147483648',
      'status=atrasado',
      'limit=201',
      'offset=-1',
    ]) {
      requisicao('GET', '/emprestimos?$filtro');
      expect((await emprestimos.onRequest(contexto)).statusCode, 400);
    }
    semBanco();
  });

  test('PATCH invalido nao consulta nem grava', () async {
    requisicao('PATCH', '/emprestimos/1', {
      'emprestimo': {'status': 'aberto'},
    });
    expect((await devolucao.onRequest(contexto, '1')).statusCode, 400);
    requisicao('PATCH', '/emprestimos/abc', {
      'emprestimo': {'status': 'devolvido'},
    });
    expect((await devolucao.onRequest(contexto, 'abc')).statusCode, 400);
    semBanco();
  });

  test(
    'sem token e pedreiro sao barrados pelo middleware antes do banco',
    () async {
      requisicao('POST', '/emprestimos', {});
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
      expect(
        (await protecao.middleware(emprestimos.onRequest)(contexto)).statusCode,
        401,
      );
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        const UsuarioAutenticado(id: 3, empresaId: 1, nivel: Nivel.pedreiro),
      );
      expect(
        (await protecao.middleware(emprestimos.onRequest)(contexto)).statusCode,
        403,
      );
      semBanco();
    },
  );
}
