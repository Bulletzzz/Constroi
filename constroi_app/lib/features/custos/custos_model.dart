class ObraCusto {
  const ObraCusto(this.id, this.nome);
  factory ObraCusto.fromJson(Map dados) =>
      ObraCusto(dados['id'] as int, dados['nome'] as String);
  final int id;
  final String nome;
}

class ResumoCusto {
  ResumoCusto.fromJson(Map dados)
    : acumulado = _valor(dados['custo_acumulado']),
      periodo = _valor(dados['custo_periodo']),
      orcamento = _opcional(dados['orcamento_total']),
      saldo = _opcional(dados['saldo_orcamento']),
      percentual = dados['percentual_consumido'] == null
          ? null
          : double.parse('${dados['percentual_consumido']}');

  final String acumulado;
  final String periodo;
  final String? orcamento;
  final String? saldo;
  final double? percentual;
}

class TotalObra extends ResumoCusto {
  TotalObra.fromJson(super.dados)
    : nome = dados['nome'] as String,
      super.fromJson();
  final String nome;
}

class CategoriaCusto {
  CategoriaCusto.fromJson(Map dados)
    : nome = dados['nome'] as String,
      valor = _valor(dados['valor']);
  final String nome;
  final String valor;
}

class LancamentoCusto {
  LancamentoCusto.fromJson(Map dados)
    : descricao = dados['descricao'] as String,
      obra = dados['obra_nome'] as String,
      categoria = dados['categoria_nome'] as String,
      // Data civil do lancamento; nao muda conforme o fuso do dispositivo.
      data = DateTime.parse(
        dados['data_lancamento'] as String,
      ).toUtc().subtract(const Duration(hours: 3)),
      valor = _valor(dados['valor']);
  final String descricao;
  final String obra;
  final String categoria;
  final DateTime data;
  final String valor;

  String get dataFormatada =>
      '${data.day.toString().padLeft(2, '0')}/'
      '${data.month.toString().padLeft(2, '0')}/${data.year}';
}

class DadosCustos {
  DadosCustos.fromJson(Map dados)
    : obras = (dados['obras'] as List)
          .map((e) => ObraCusto.fromJson(e as Map))
          .toList(),
      resumo = ResumoCusto.fromJson(dados['resumo'] as Map),
      semPreco = (dados['resumo'] as Map)['itens_sem_preco'] as int,
      totais = (dados['totais_por_obra'] as List)
          .map((e) => TotalObra.fromJson(e as Map))
          .toList(),
      categorias = (dados['categorias'] as List)
          .map((e) => CategoriaCusto.fromJson(e as Map))
          .toList(),
      lancamentos = (dados['lancamentos'] as List)
          .map((e) => LancamentoCusto.fromJson(e as Map))
          .toList(),
      temMais = (dados['paginacao'] as Map)['tem_mais'] as bool;
  final List<ObraCusto> obras;
  final ResumoCusto resumo;
  final int semPreco;
  final List<TotalObra> totais;
  final List<CategoriaCusto> categorias;
  final List<LancamentoCusto> lancamentos;
  final bool temMais;
}

String _valor(Object? valor) {
  final texto = '$valor';
  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(texto)) {
    throw const FormatException('Valor monetário inválido.');
  }
  return texto;
}

String? _opcional(Object? valor) => valor == null ? null : _valor(valor);

// Formata o decimal recebido sem arredondar dinheiro com ponto flutuante.
String dinheiro(String valor) {
  final partes = _valor(valor).split('.');
  final inteiro = partes.first.replaceFirst('-', '');
  final agrupado = inteiro.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  final centavos = partes.length == 1 ? '00' : partes.last.padRight(2, '0');
  return '${valor.startsWith('-') ? '-' : ''}R\$ $agrupado,$centavos';
}
