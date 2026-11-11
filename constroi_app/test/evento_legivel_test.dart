import 'package:constroi_app/features/administracao/evento_legivel.dart';
import 'package:flutter_test/flutter_test.dart';

const nomes = DicionarioDeNomes(
  usuarios: {2: 'Joao Pedreiro', 3: 'Ana Master'},
  obras: {110: 'Residencial Vista Verde'},
  produtos: {114: 'Cimento CP-II 50kg', 116: 'Areia media'},
  unidades: {114: 'saco', 116: 'm3'},
  equipamentos: {7: 'Betoneira 400L'},
);

void main() {
  group('titulo', () {
    test('login vira frase', () {
      expect(lerEvento('LOGIN usuario=2', nomes).titulo, 'entrou no sistema');
    });

    test('cadastro usa o nome do produto quando ele e conhecido', () {
      expect(
        lerEvento('CRIACAO_PRODUTO produto=114', nomes).titulo,
        'cadastrou o produto Cimento CP-II 50kg',
      );
    });

    test('produto desconhecido aparece como numero, sem repetir o rotulo', () {
      expect(
        lerEvento('CRIACAO_PRODUTO produto=999', nomes).titulo,
        'cadastrou o produto #999',
      );
    });

    test('obra e equipamento tambem usam o nome', () {
      expect(
        lerEvento('CRIACAO_OBRA obra=110', nomes).titulo,
        'cadastrou a obra Residencial Vista Verde',
      );
      expect(
        lerEvento(
          'EMPRESTIMO_EQUIPAMENTO emprestimo=1 equipamento=7 usuario=2'
          ' obra=110 dias=14',
          nomes,
        ).titulo,
        'retirou o equipamento Betoneira 400L',
      );
    });

    test('requisicao mostra o protocolo', () {
      expect(
        lerEvento(
          'CRIACAO_PEDIDO pedido=9 obra=110 protocolo=PED-5EED01',
          nomes,
        ).titulo,
        'abriu a requisição PED-5EED01',
      );
    });

    test('evento sem protocolo nao deixa buraco na frase', () {
      expect(
        lerEvento('CRIACAO_PEDIDO pedido=9 obra=110', nomes).titulo,
        'abriu uma requisição',
      );
      expect(lerEvento('ALTERACAO_OBRA', nomes).titulo, 'alterou a obra');
    });

    test('evento desconhecido nao vira texto tecnico sem sentido', () {
      final legivel = lerEvento('EVENTO_NOVO alvo=1', nomes);
      expect(legivel.titulo, 'evento novo');
      expect(legivel.detalhe, 'alvo=1');
    });
  });

  group('detalhe', () {
    test('baixa descreve quantidade com unidade, saldo e obra', () {
      final legivel = lerEvento(
        'BAIXA_ESTOQUE pedido=9 obra=110 produto=114 quantidade=40.00'
        ' saldo=320.00 protocolo=PED-5EED01',
        nomes,
      );
      expect(
        legivel.titulo,
        'aprovou a requisição PED-5EED01 e baixou o estoque',
      );
      expect(
        legivel.detalhe,
        'saída de 40 sacos de Cimento CP-II 50kg · saldo 320 sacos'
        ' · obra Residencial Vista Verde',
      );
    });

    test('entrada manual mantem decimais de unidade fracionada', () {
      expect(
        lerEvento(
          'ENTRADA_MANUAL entrada=3 obra=110 produto=116 quantidade=40.50'
          ' saldo=40.50',
          nomes,
        ).detalhe,
        '40.50 m3 de Areia media · saldo 40.50 m3'
        ' · obra Residencial Vista Verde',
      );
    });

    test('produto desconhecido no detalhe mantem o rotulo', () {
      expect(
        lerEvento(
          'ENTRADA_MANUAL entrada=3 obra=110 produto=999 quantidade=10',
          nomes,
        ).detalhe,
        '10 de produto #999 · obra Residencial Vista Verde',
      );
    });

    test('emprestimo informa responsavel, obra e prazo', () {
      expect(
        lerEvento(
          'EMPRESTIMO_EQUIPAMENTO emprestimo=1 equipamento=7 usuario=2'
          ' obra=110 dias=14',
          nomes,
        ).detalhe,
        'responsável Joao Pedreiro · obra Residencial Vista Verde'
        ' · prazo de 14 dias',
      );
    });

    test('despesa de obra aparece como lancamento', () {
      final legivel = lerEvento('CRIACAO_DESPESA despesa=70', nomes);
      expect(legivel.titulo, 'lançou uma despesa de obra');
      expect(legivel.detalhe, 'lançamento #70');
    });

    test('nota fiscal mostra a chave', () {
      expect(
        lerEvento('ANEXO_NFE entrada=3 chave=${'1' * 44}', nomes).detalhe,
        'chave ${'1' * 44}',
      );
    });
  });

  group('dicionario', () {
    test('comUsuarios troca so os usuarios', () {
      final trocado = nomes.comUsuarios({9: 'Rita Alves'});
      expect(trocado.usuarios, {9: 'Rita Alves'});
      expect(trocado.produtos, nomes.produtos);
      expect(trocado.obras, nomes.obras);
      expect(trocado.equipamentos, nomes.equipamentos);
      expect(trocado.unidades, nomes.unidades);
    });

    test('sem dicionario nenhum evento quebra', () {
      const vazio = DicionarioDeNomes();
      expect(
        lerEvento('CRIACAO_PRODUTO produto=114', vazio).titulo,
        'cadastrou o produto #114',
      );
      expect(lerEvento('', vazio).titulo, 'registrou um evento do sistema');
    });
  });
}
