import 'dart:io';

import 'package:test/test.dart';

import '../integration_test/apoio_pool.dart';

void main() {
  test('a url de teste ganha o tamanho de pool que a concorrencia exige', () {
    final url = urlComPoolDeTeste(
      'postgres://u:s@localhost:5432/constroi_test_x?sslmode=require',
    );
    final parametros = Uri.parse(url).queryParameters;

    expect(parametros['max_connection_count'], '$conexoesDeTeste');
    expect(parametros['sslmode'], 'require');
    expect(conexoesDeTeste, greaterThanOrEqualTo(8));
  });

  test('um tamanho ja escrito na url nao vence o do teste', () {
    final url = urlComPoolDeTeste(
      'postgres://u:s@localhost:5432/constroi_test_x'
      '?sslmode=require&max_connection_count=1',
    );

    expect(
      Uri.parse(url).queryParameters['max_connection_count'],
      '$conexoesDeTeste',
    );
  });

  test('nenhuma suite de integracao abre pool por fora do apoio', () {
    final diretos = Directory('integration_test')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => f.readAsStringSync().contains('Pool<void>.withUrl'))
        .map((f) => f.uri.pathSegments.last)
        .toList();

    expect(
      diretos,
      isEmpty,
      reason: 'use poolDeTeste: com pool de uma conexao os testes que '
          'prendem varias requisicoes no mesmo lock nunca destravam',
    );
  });
}
