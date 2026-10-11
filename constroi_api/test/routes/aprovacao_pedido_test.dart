import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/[id].dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

void main() {
  late _ContextoFalso contexto;
  late _BancoFalso banco;

  void requisicao(Object? corpo) {
    when(() => contexto.request).thenReturn(
      Request.patch(
        Uri.parse('http://localhost/pedidos/1'),
        body: jsonEncode(corpo),
      ),
    );
  }

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      const UsuarioAutenticado(id: 3, empresaId: 1, nivel: Nivel.engenheiro),
    );
    requisicao({
      'pedido': {'status': 'aprovado'},
    });
  });

  test('PATCH exige token e perfil engenheiro antes de ler o banco', () async {
    for (final caso in [
      (usuario: null, status: HttpStatus.unauthorized),
      (
        usuario: const UsuarioAutenticado(
          id: 1,
          empresaId: 1,
          nivel: Nivel.pedreiro,
        ),
        status: HttpStatus.forbidden,
      ),
    ]) {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(caso.usuario);
      expect((await rota.onRequest(contexto, '1')).statusCode, caso.status);
    }
    verifyNever(() => contexto.read<Pool<void>>());
  });

  test('id invalido retorna 400 sem ler o banco', () async {
    for (final id in ['abc', '0', '-1', '2147483648']) {
      expect(
        (await rota.onRequest(contexto, id)).statusCode,
        HttpStatus.badRequest,
      );
    }
    verifyNever(() => contexto.read<Pool<void>>());
  });

  test('corpo invalido ou outra decisao retorna 400 sem ler o banco', () async {
    for (final corpo in [
      null,
      <Object?>[],
      <String, dynamic>{},
      {'pedido': null},
      {'pedido': <Object?>[]},
      {
        'pedido': {'status': 'pendente'},
      },
      {
        'pedido': {'status': 'recusado'},
      },
      {
        'pedido': {'status': 1},
      },
    ]) {
      requisicao(corpo);
      expect(
        (await rota.onRequest(contexto, '1')).statusCode,
        HttpStatus.badRequest,
      );
    }
    verifyNever(() => contexto.read<Pool<void>>());
  });

  test('JSON malformado retorna 400 sem ler o banco', () async {
    when(() => contexto.request).thenReturn(
      Request.patch(Uri.parse('http://localhost/pedidos/1'), body: '{'),
    );
    expect(
      (await rota.onRequest(contexto, '1')).statusCode,
      HttpStatus.badRequest,
    );
    verifyNever(() => contexto.read<Pool<void>>());
  });
}
