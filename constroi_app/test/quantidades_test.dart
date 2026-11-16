import 'package:flutter_test/flutter_test.dart';
import 'package:constroi_app/core/catalogo/opcoes.dart';

void main() {
  test('formata sacos de acordo com a quantidade', () {
    expect(unidadeParaQuantidade('saco', '1.00'), 'saco');
    expect(unidadeParaQuantidade('sacos', '1'), 'saco');
    expect(unidadeParaQuantidade('saco', '100.00'), 'sacos');
    expect(unidadeParaQuantidade('saco', '0'), 'sacos');
    expect(formatarQuantidade('100.00'), '100');
    expect(formatarQuantidade('1.50'), '1.50');
  });

  test('numero inteiro perde o .00 em qualquer unidade', () {
    expect(formatarQuantidade('24.00'), '24');
    expect(formatarQuantidade('20.00'), '20');
    expect(formatarQuantidade('0.00'), '0');
    expect(formatarQuantidade('300'), '300');
  });

  test('decimal significativo e texto invalido ficam como vieram', () {
    expect(formatarQuantidade('40.50'), '40.50');
    expect(formatarQuantidade('0.01'), '0.01');
    expect(formatarQuantidade(''), '');
    expect(formatarQuantidade('abc'), 'abc');
  });
}
