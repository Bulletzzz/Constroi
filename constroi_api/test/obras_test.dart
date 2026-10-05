import 'package:constroi_api/obras.dart';
import 'package:test/test.dart';

void main() {
  group('obras', () {
    test('valida nome, endereco e os status permitidos', () {
      expect(validarNomeObra(' Obra Central '), equals('Obra Central'));
      expect(validarEnderecoObra(' Rua A, 10 '), equals('Rua A, 10'));
      expect(validarStatusObra('planejamento'), equals('planejamento'));
      expect(validarStatusObra('ATIVA'), equals('ativa'));
      expect(validarStatusObra('pausada'), equals('pausada'));
      expect(validarStatusObra('concluida'), equals('concluida'));
    });

    test('rejeita dados obrigatorios vazios e status desconhecido', () {
      expect(validarNomeObra(' '), isNull);
      expect(validarEnderecoObra(''), isNull);
      expect(validarStatusObra('cancelada'), isNull);
      expect(validarStatusObra(null), isNull);
    });
  });

  group('orcamento da obra', () {
    test('numero positivo e aceito', () {
      final lido = validarOrcamentoObra(250000.5);
      expect(lido.valido, isTrue);
      expect(lido.valor, equals(250000.5));
    });

    test('zero e aceito', () {
      expect(validarOrcamentoObra(0).valor, equals(0));
    });

    test('nulo e aceito e significa sem orcamento', () {
      final lido = validarOrcamentoObra(null);
      expect(lido.valido, isTrue);
      expect(lido.valor, isNull);
    });

    test('texto vazio limpa o orcamento', () {
      final lido = validarOrcamentoObra('  ');
      expect(lido.valido, isTrue);
      expect(lido.valor, isNull);
    });

    test('virgula decimal e aceita', () {
      expect(validarOrcamentoObra('310000,75').valor, equals(310000.75));
    });

    test('negativo e recusado', () {
      expect(validarOrcamentoObra(-1).valido, isFalse);
      expect(validarOrcamentoObra('-1').valido, isFalse);
    });

    test('texto que nao e numero e recusado', () {
      expect(validarOrcamentoObra('muito dinheiro').valido, isFalse);
    });

    test('infinito e nan sao recusados', () {
      expect(validarOrcamentoObra(double.infinity).valido, isFalse);
      expect(validarOrcamentoObra(double.nan).valido, isFalse);
    });

    test('tipo inesperado e recusado', () {
      expect(validarOrcamentoObra(<String>['1000']).valido, isFalse);
    });
  });

  group('mapeamento da resposta', () {
    test('orcamento vira texto para nao perder centavos', () {
      final saida = dadosDaObra({
        'id': 1,
        'nome': 'Obra',
        'endereco': 'Rua A',
        'status': 'ativa',
        'orcamento_total': 250000.5,
        'empresa_id': 3,
      });
      expect(saida['orcamento_total'], equals('250000.5'));
    });

    test('orcamento ausente volta como nulo', () {
      final saida = dadosDaObra({
        'id': 1,
        'nome': 'Obra',
        'endereco': 'Rua A',
        'status': 'ativa',
        'orcamento_total': null,
        'empresa_id': 3,
      });
      expect(saida['orcamento_total'], isNull);
    });
  });
}
