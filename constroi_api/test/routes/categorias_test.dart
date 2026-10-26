import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/categorias/index.dart' as rota;

class _Contexto extends Mock implements RequestContext {}

class _Banco extends Mock implements Pool<void> {}

class _Linha extends Mock implements ResultRow {}

const _conexao = 'postgresql://usuario:senha-secreta@host.neon.tech/db';

void main() {
  late _Contexto contexto;
  late _Banco banco;

  Future<Response> chamarComLogs(List<String> logs) => runZoned(
    () => rota.onRequest(contexto),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, mensagem) => logs.add(mensagem),
    ),
  );

  Result montarResultado(List<List<Object?>> linhas) {
    final rows = linhas.map((valores) {
      final linha = _Linha();
      when(() => linha[0]).thenReturn(valores[0]);
      when(() => linha[1]).thenReturn(valores[1]);
      return linha;
    }).toList();
    return Result(rows: rows, affectedRows: 0, schema: ResultSchema([]));
  }

  setUp(() {
    contexto = _Contexto();
    banco = _Banco();
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(
      () => contexto.request,
    ).thenReturn(Request.get(Uri.parse('http://localhost/categorias')));
  });

  test('lista as categorias em ordem de nome', () async {
    when(() => banco.execute(any())).thenAnswer(
      (_) async => montarResultado([
        [1, 'Aço e vergalhão'],
        [2, 'Cimento e agregados'],
      ]),
    );

    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.ok);
    final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
    expect(corpo['categorias'], [
      {'id': 1, 'nome': 'Aço e vergalhão'},
      {'id': 2, 'nome': 'Cimento e agregados'},
    ]);
  });

  test('metodo diferente de GET devolve 405', () async {
    when(
      () => contexto.request,
    ).thenReturn(Request.post(Uri.parse('http://localhost/categorias')));

    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.methodNotAllowed);
  });

  test('falha no banco devolve 503 sem vazar a conexao', () async {
    when(
      () => banco.execute(any()),
    ).thenThrow(const FormatException('falha ao conectar em $_conexao'));

    final logs = <String>[];
    final resposta = await chamarComLogs(logs);

    expect(resposta.statusCode, HttpStatus.serviceUnavailable);
    final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
    expect(corpo['erro'], isNot(contains('senha-secreta')));

    final registrado = logs.join('\n');
    expect(registrado, contains('FormatException'));
    expect(registrado, contains('[conexao PostgreSQL omitida]'));
    expect(registrado, isNot(contains('senha-secreta')));
  });
}
