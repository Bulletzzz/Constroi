import 'package:constroi_api/pedidos.dart';
import 'package:test/test.dart';

void main() {
  test('protocolo tem formato valido e cabe no banco', () {
    expect(gerarProtocolo(), matches(RegExp(r'^PED-[0-9A-F]{32}$')));
  });

  test('aceita itens com quantidade inteira ou fracionada', () {
    expect(
      validarItensPedido([
        {'produto_id': 1, 'quantidade': 2},
        {'produto_id': 2, 'quantidade': 0.01},
        {'produto_id': 3, 'quantidade': 9999999999.99},
      ]),
      hasLength(3),
    );
  });

  test('recusa lista vazia, produto repetido e tipos invalidos', () {
    for (final valor in [
      null,
      'itens',
      <Object?>[],
      [null],
      [
        {'produto_id': 1, 'quantidade': 2},
        {'produto_id': 1, 'quantidade': 3},
      ],
      [
        {'produto_id': '1', 'quantidade': 2},
      ],
    ]) {
      expect(validarItensPedido(valor), isNull);
    }
  });

  test('recusa quantidade invalida ou que seria arredondada pelo banco', () {
    for (final quantidade in [
      null,
      '2',
      0,
      -1,
      double.nan,
      double.infinity,
      0.001,
      1.999,
      10000000000,
    ]) {
      expect(
        validarItensPedido([
          {'produto_id': 1, 'quantidade': quantidade},
        ]),
        isNull,
      );
    }
  });

  test('identificadores devem caber em INTEGER do PostgreSQL', () {
    for (final id in [null, '1', 1.5, 0, -1, 2147483648]) {
      expect(validarIdPedido(id), isNull);
    }
    expect(validarIdPedido(2147483647), 2147483647);
  });
}
