class ObraPainel {
  const ObraPainel({required this.id, required this.nome});
  final int id;
  final String nome;

  factory ObraPainel.fromJson(Map<String, dynamic> json) =>
      ObraPainel(id: _inteiro(json['id']), nome: _texto(json['nome']));
}

class IndicadoresPainel {
  const IndicadoresPainel({
    required this.totalItens,
    required this.rupturasCriticas,
    required this.requisicoesPendentes,
    required this.obrasAtivas,
    this.valorEstimado,
    this.itensSemPreco = 0,
  });
  final int totalItens;
  final int rupturasCriticas;
  final int requisicoesPendentes;
  final int obrasAtivas;
  final num? valorEstimado;
  final int itensSemPreco;

  factory IndicadoresPainel.fromJson(Map<String, dynamic> json) =>
      IndicadoresPainel(
        totalItens: _inteiro(json['total_itens']),
        rupturasCriticas: _inteiro(json['rupturas_criticas']),
        requisicoesPendentes: _inteiro(json['requisicoes_pendentes']),
        obrasAtivas: _inteiro(json['obras_ativas']),
        valorEstimado: json['valor_estimado'] == null
            ? null
            : _numero(json['valor_estimado']),
        itensSemPreco: json.containsKey('itens_sem_preco')
            ? _inteiro(json['itens_sem_preco'])
            : 0,
      );
}

class MovimentacaoPainel {
  const MovimentacaoPainel({
    required this.id,
    required this.produtoNome,
    required this.obraNome,
    required this.acao,
    required this.quantidade,
    required this.unidade,
    required this.data,
  });
  final String id;
  final String produtoNome;
  final String obraNome;
  final String acao;
  final num quantidade;
  final String unidade;
  final DateTime data;

  factory MovimentacaoPainel.fromJson(Map<String, dynamic> json) {
    final acao = _texto(json['acao']);
    if (!{'entrada', 'saida', 'ajuste'}.contains(acao)) {
      throw const FormatException('Acao de estoque desconhecida.');
    }
    return MovimentacaoPainel(
      id: _texto(json['id']),
      produtoNome: _texto(json['produto_nome']),
      obraNome: _texto(json['obra_nome']),
      acao: acao,
      quantidade: _numero(json['quantidade']),
      unidade: _texto(json['unidade']),
      data: DateTime.parse(_texto(json['data'])),
    );
  }
}

class PainelDados {
  const PainelDados({
    required this.obras,
    required this.obraId,
    required this.atualizadoEm,
    required this.indicadores,
    required this.movimentacoes,
    required this.temMais,
  });
  final List<ObraPainel> obras;
  final int? obraId;
  final DateTime atualizadoEm;
  final IndicadoresPainel indicadores;
  final List<MovimentacaoPainel> movimentacoes;
  final bool temMais;

  factory PainelDados.fromJson(Map<String, dynamic> json) {
    final paginacao = json['paginacao'] as Map<String, dynamic>;
    if (paginacao['tem_mais'] is! bool) {
      throw const FormatException('Paginacao invalida.');
    }
    return PainelDados(
      obras: (json['obras'] as List)
          .map((o) => ObraPainel.fromJson(o as Map<String, dynamic>))
          .toList(),
      obraId: json['obra_id'] == null ? null : _inteiro(json['obra_id']),
      atualizadoEm: DateTime.parse(_texto(json['atualizado_em'])),
      indicadores: IndicadoresPainel.fromJson(
        json['indicadores'] as Map<String, dynamic>,
      ),
      movimentacoes: (json['movimentacoes'] as List)
          .map((m) => MovimentacaoPainel.fromJson(m as Map<String, dynamic>))
          .toList(),
      temMais: paginacao['tem_mais'] as bool,
    );
  }
}

int _inteiro(Object? valor) {
  final numero = _numero(valor);
  if (numero < 0 || numero != numero.truncate()) {
    throw const FormatException('Contagem invalida.');
  }
  return numero.toInt();
}

num _numero(Object? valor) {
  final numero = valor is num
      ? valor
      : valor is String
      ? num.tryParse(valor)
      : null;
  if (numero == null || !numero.isFinite) {
    throw const FormatException('Numero invalido.');
  }
  return numero;
}

String _texto(Object? valor) {
  if (valor is! String || valor.isEmpty) {
    throw const FormatException('Texto invalido.');
  }
  return valor;
}

String formatarNumero(num valor, {int? casas}) {
  final partes = valor
      .toStringAsFixed(casas ?? (valor == valor.truncate() ? 0 : 2))
      .split('.');
  final inteiro = partes.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return partes.length == 1 ? inteiro : '$inteiro,${partes.last}';
}
