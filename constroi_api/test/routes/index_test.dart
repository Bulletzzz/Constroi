import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../routes/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('GET /', () {
    test('responde 200 sem revelar o framework', () async {
      final contexto = _MockRequestContext();

      final resposta = route.onRequest(contexto);
      final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;

      expect(resposta.statusCode, equals(HttpStatus.ok));
      expect(corpo, equals({'servico': 'constroi-api', 'status': 'ok'}));
      expect(corpo.values.join(), isNot(contains('Frog')));
    });
  });
}
