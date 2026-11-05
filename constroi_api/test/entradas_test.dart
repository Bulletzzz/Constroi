import 'package:constroi_api/entradas.dart';
import 'package:test/test.dart';

void main() {
  test('aceita 200 itens e recusa entradas acima do limite', () {
    final itens = List.generate(
      201,
      (indice) => {'produto_id': indice + 1, 'quantidade': 1},
    );
    expect(validarItensEntrada(itens.take(200).toList()), hasLength(200));
    expect(validarItensEntrada(itens), isNull);
  });
}
