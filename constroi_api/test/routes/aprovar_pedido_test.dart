import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/[id]/_middleware.dart' as protecao;
import '../../routes/pedidos/[id]/aprovar.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

void main() {
  late _ContextoFalso contexto;
  late _BancoFalso banco;

  void requisicao(Request pedido, Nivel nivel) {
    when(() => contexto.request).thenReturn(pedido);
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
    );
  }

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
  });

  final url = Uri.parse('http://localhost/pedidos/30/aprovar');

  test('pedreiro nao aprova pedido e o banco nem e consultado', () async {
    requisicao(Request.post(url), Nivel.pedreiro);
    final resposta = await protecao.middleware(
      (contexto) => rota.onRequest(contexto, '30'),
    )(contexto);
    expect(resposta.statusCode, HttpStatus.forbidden);
    verifyZeroInteractions(banco);
  });

  test('id invalido retorna 400 sem abrir transacao', () async {
    requisicao(Request.post(url), Nivel.engenheiro);
    final resposta = await rota.onRequest(contexto, 'abc');
    expect(resposta.statusCode, HttpStatus.badRequest);
    verifyZeroInteractions(banco);
  });

  test('metodo diferente de POST retorna 405', () async {
    requisicao(Request.get(url), Nivel.engenheiro);
    final resposta = await rota.onRequest(contexto, '30');
    expect(resposta.statusCode, HttpStatus.methodNotAllowed);
    verifyZeroInteractions(banco);
  });
}
