import 'package:flutter_test/flutter_test.dart';
import 'package:constroi_app/core/catalogo/opcoes.dart';

void main() {
  test('formata sacos de acordo com a quantidade', () {
    expect(unidadeParaQuantidade('saco', '1.00'), 'saco');
    expect(unidadeParaQuantidade('sacos', '1'), 'saco');
    expect(unidadeParaQuantidade('saco', '100.00'), 'sacos');
    expect(unidadeParaQuantidade('saco', '0'), 'sacos');
    expect(formatarQuantidade('100.00', 'saco'), '100');
    expect(formatarQuantidade('1.50', 'm3'), '1.50');
  });
}
