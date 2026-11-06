enum Urgencia {
  padrao('padrao', 'Padrão', '3 a 5 dias'),
  urgente('urgente', 'Urgente', 'Até 24 horas');

  const Urgencia(this.valor, this.rotulo, this.prazo);

  final String valor;
  final String rotulo;
  final String prazo;

  static Urgencia daApi(Object? valor) => values.firstWhere(
    (u) => u.valor == valor,
    orElse: () => Urgencia.padrao,
  );
}

enum SituacaoPedido {
  pendente('pendente', 'Pendente'),
  aprovado('aprovado', 'Aprovado'),
  recusado('recusado', 'Recusado');

  const SituacaoPedido(this.valor, this.rotulo);

  final String valor;
  final String rotulo;

  static SituacaoPedido daApi(Object? valor) {
    final texto = '${valor ?? ''}'.trim().toLowerCase();
    return values.firstWhere(
      (s) => s.valor == texto,
      orElse: () => SituacaoPedido.pendente,
    );
  }
}

class ItemDoPedido {
  const ItemDoPedido({
    required this.produtoId,
    required this.quantidade,
    this.produtoNome,
    this.unidade,
  });

  final int produtoId;
  final String quantidade;
  final String? produtoNome;
  final String? unidade;

  static ItemDoPedido? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final produto = _inteiro(dados['produto_id']);
    if (produto == null) return null;
    return ItemDoPedido(
      produtoId: produto,
      quantidade: _texto(dados['quantidade']) ?? '0',
      produtoNome: _texto(dados['produto_nome']),
      unidade: _texto(dados['unidade']),
    );
  }

  String get descricao {
    final nome = produtoNome ?? 'Produto $produtoId';
    return unidade == null ? '$quantidade · $nome' : '$quantidade $unidade · $nome';
  }
}

class Pedido {
  const Pedido({
    required this.id,
    required this.protocolo,
    required this.status,
    required this.urgencia,
    required this.itens,
    this.obraId,
    this.solicitante,
    this.localObra,
    this.justificativa,
    this.motivoRecusa,
    this.obraNome,
    this.data,
  });

  final int id;
  final String protocolo;
  final String status;
  final Urgencia urgencia;
  final List<ItemDoPedido> itens;
  final int? obraId;
  final String? solicitante;
  final String? localObra;
  final String? justificativa;
  final String? motivoRecusa;
  final String? obraNome;
  final DateTime? data;

  bool get pendente => situacao == SituacaoPedido.pendente;

  SituacaoPedido get situacao => SituacaoPedido.daApi(status);

  String get protocoloCurto {
    final semPrefixo = protocolo.startsWith('PED-')
        ? protocolo.substring(4)
        : protocolo;
    return semPrefixo.length <= 6
        ? '#$semPrefixo'
        : '#${semPrefixo.substring(0, 6)}';
  }

  static Pedido? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = _inteiro(dados['id']);
    if (id == null) return null;
    final itens = dados['itens'];
    return Pedido(
      id: id,
      protocolo: _texto(dados['protocolo']) ?? '',
      status: _texto(dados['status']) ?? 'pendente',
      urgencia: Urgencia.daApi(dados['urgencia']),
      itens: itens is List
          ? itens
                .map(ItemDoPedido.talvezDoJson)
                .whereType<ItemDoPedido>()
                .toList()
          : const [],
      obraId: _inteiro(dados['obra_id']),
      solicitante: _texto(dados['solicitante_nome']),
      localObra: _texto(dados['local_obra']),
      justificativa: _texto(dados['justificativa']),
      motivoRecusa: _texto(dados['justificativa_recusa']),
      obraNome: _texto(dados['obra_nome']),
      data: DateTime.tryParse(_texto(dados['data']) ?? '')?.toLocal(),
    );
  }
}

int? _inteiro(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor);
  return null;
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final texto = '$valor'.trim();
  return texto.isEmpty ? null : texto;
}
