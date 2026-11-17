import 'package:constroi_api/diagnostico.dart';
import 'package:test/test.dart';

void main() {
  group('semCredenciais', () {
    test('remove a url de conexao com a senha', () {
      final erro = Exception(
        'falha ao abrir postgresql://dono:senha-secreta@ep-x.neon.tech/db',
      );

      final texto = semCredenciais(erro);

      expect(texto, contains('[conexao PostgreSQL omitida]'));
      expect(texto, isNot(contains('senha-secreta')));
      expect(texto, isNot(contains('neon.tech')));
    });

    test('remove a url em qualquer linha da pilha', () {
      final pilha = StackTrace.fromString(
        'linha de cima\n'
        'postgres://dono:outra-senha@host/db\n'
        'linha de baixo',
      );

      final texto = semCredenciais(Exception('falhou'), pilha);

      expect(texto, isNot(contains('outra-senha')));
      expect(texto, contains('linha de cima'));
      expect(texto, contains('linha de baixo'));
    });

    test('preserva o diagnostico quando nao ha url', () {
      final texto = semCredenciais(Exception('coluna inexistente'));

      expect(texto, contains('coluna inexistente'));
    });
  });
}
