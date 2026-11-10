import '../../core/catalogo/opcoes.dart';

class DicionarioDeNomes {
  const DicionarioDeNomes({
    this.usuarios = const {},
    this.obras = const {},
    this.produtos = const {},
    this.unidades = const {},
    this.equipamentos = const {},
  });

  final Map<int, String> usuarios;
  final Map<int, String> obras;
  final Map<int, String> produtos;
  final Map<int, String> unidades;
  final Map<int, String> equipamentos;

  DicionarioDeNomes comUsuarios(Map<int, String> novos) => DicionarioDeNomes(
    usuarios: novos,
    obras: obras,
    produtos: produtos,
    unidades: unidades,
    equipamentos: equipamentos,
  );
}

class EventoLegivel {
  const EventoLegivel(this.titulo, this.detalhe);

  final String titulo;
  final String detalhe;
}

EventoLegivel lerEvento(String acao, DicionarioDeNomes nomes) {
  final partes = acao.trim().split(' ');
  final evento = partes.isEmpty ? '' : partes.first;
  final campos = _campos(partes.skip(1));

  final obra = _nomeOuNumero(nomes.obras, campos['obra']);
  final produto = _nomeOuNumero(nomes.produtos, campos['produto']);
  final equipamento = _nomeOuNumero(nomes.equipamentos, campos['equipamento']);
  final usuario = _nomeOuNumero(nomes.usuarios, campos['usuario']);
  final oProduto = _comRotulo(nomes.produtos, campos['produto'], 'produto');
  final oResponsavel = _comRotulo(nomes.usuarios, campos['usuario'], 'usuário');
  final protocolo = campos['protocolo'];

  return switch (evento) {
    'LOGIN' => const EventoLegivel('entrou no sistema', ''),
    'CRIACAO_EMPRESA' => EventoLegivel(
      'cadastrou a empresa',
      _juntar([if (oResponsavel != null) 'responsável $oResponsavel']),
    ),
    'CRIACAO_USUARIO' => EventoLegivel(
      'cadastrou o usuário ${usuario ?? 'novo'}',
      '',
    ),
    'ALTERACAO_USUARIO' => EventoLegivel(
      'alterou o cadastro de ${usuario ?? 'um usuário'}',
      '',
    ),
    'INATIVACAO_USUARIO' => EventoLegivel(
      'inativou o usuário ${usuario ?? ''}'.trimRight(),
      '',
    ),
    'CRIACAO_OBRA' => EventoLegivel('cadastrou a obra ${obra ?? 'nova'}', ''),
    'ALTERACAO_OBRA' => EventoLegivel(
      'alterou a obra ${obra ?? ''}'.trimRight(),
      '',
    ),
    'CRIACAO_PRODUTO' => EventoLegivel(
      'cadastrou o produto ${produto ?? 'novo'}',
      '',
    ),
    'ALTERACAO_PRODUTO' => EventoLegivel(
      'alterou o produto ${produto ?? ''}'.trimRight(),
      '',
    ),
    'CRIACAO_EQUIPAMENTO' => EventoLegivel(
      'cadastrou o equipamento ${equipamento ?? 'novo'}',
      '',
    ),
    'ALTERACAO_EQUIPAMENTO' => EventoLegivel(
      'alterou o equipamento ${equipamento ?? ''}'.trimRight(),
      '',
    ),
    'CRIACAO_DESPESA' => EventoLegivel(
      'lançou uma despesa de obra',
      _juntar([
        if (campos['despesa'] != null) 'lançamento #${campos['despesa']}',
      ]),
    ),
    'VINCULO_EQUIPE' => EventoLegivel(
      'incluiu um integrante na equipe de uma obra',
      _juntar([if (campos['vinculo'] != null) 'vínculo #${campos['vinculo']}']),
    ),
    'ENCERRAMENTO_EQUIPE' => EventoLegivel(
      'encerrou a participação de um integrante na equipe',
      _juntar([if (campos['vinculo'] != null) 'vínculo #${campos['vinculo']}']),
    ),
    'CRIACAO_PEDIDO' => EventoLegivel(
      protocolo == null
          ? 'abriu uma requisição'
          : 'abriu a requisição $protocolo',
      _juntar([if (obra != null) 'obra $obra']),
    ),
    'RECUSA_PEDIDO' => EventoLegivel(
      protocolo == null
          ? 'recusou uma requisição'
          : 'recusou a requisição $protocolo',
      _juntar([if (obra != null) 'obra $obra']),
    ),
    'BAIXA_ESTOQUE' => EventoLegivel(
      protocolo == null
          ? 'aprovou uma requisição e baixou o estoque'
          : 'aprovou a requisição $protocolo e baixou o estoque',
      _juntar([
        if (oProduto != null)
          'saída de ${_quantia(campos, nomes)} de $oProduto',
        if (campos['saldo'] != null)
          'saldo ${_numero(campos['saldo']!, campos, nomes)}',
        if (obra != null) 'obra $obra',
      ]),
    ),
    'ENTRADA_MANUAL' => EventoLegivel(
      'registrou entrada de material',
      _juntar([
        if (oProduto != null) '${_quantia(campos, nomes)} de $oProduto',
        if (campos['saldo'] != null)
          'saldo ${_numero(campos['saldo']!, campos, nomes)}',
        if (obra != null) 'obra $obra',
      ]),
    ),
    'ENTRADA_NFE' => EventoLegivel(
      'registrou entrada por nota fiscal',
      _juntar([
        if (obra != null) 'obra $obra',
        if (campos['chave'] != null) 'chave ${campos['chave']}',
      ]),
    ),
    'ANEXO_NFE' => EventoLegivel(
      'anexou a nota fiscal de uma entrada',
      _juntar([if (campos['chave'] != null) 'chave ${campos['chave']}']),
    ),
    'EMPRESTIMO_EQUIPAMENTO' => EventoLegivel(
      'retirou o equipamento ${equipamento ?? ''}'.trimRight(),
      _juntar([
        if (oResponsavel != null) 'responsável $oResponsavel',
        if (obra != null) 'obra $obra',
        if (campos['dias'] != null) 'prazo de ${campos['dias']} dias',
      ]),
    ),
    'DEVOLUCAO_EQUIPAMENTO' => EventoLegivel(
      'devolveu o equipamento ${equipamento ?? ''}'.trimRight(),
      _juntar([
        if (oResponsavel != null) 'responsável $oResponsavel',
        if (obra != null) 'obra $obra',
      ]),
    ),
    _ => EventoLegivel(_humanizar(evento), partes.skip(1).join(' ')),
  };
}

Map<String, String> _campos(Iterable<String> partes) {
  final campos = <String, String>{};
  for (final parte in partes) {
    final corte = parte.indexOf('=');
    if (corte > 0 && corte < parte.length - 1) {
      campos[parte.substring(0, corte)] = parte.substring(corte + 1);
    }
  }
  return campos;
}

String? _nomeOuNumero(Map<int, String> fonte, String? valor) {
  final id = int.tryParse(valor ?? '');
  if (id == null) return null;
  return fonte[id] ?? '#$id';
}

String? _comRotulo(Map<int, String> fonte, String? valor, String rotulo) {
  final id = int.tryParse(valor ?? '');
  if (id == null) return null;
  return fonte[id] ?? '$rotulo #$id';
}

String _quantia(Map<String, String> campos, DicionarioDeNomes nomes) {
  final quantidade = campos['quantidade'];
  if (quantidade == null) return 'quantidade não registrada';
  return _numero(quantidade, campos, nomes);
}

String _numero(
  String valor,
  Map<String, String> campos,
  DicionarioDeNomes nomes,
) {
  final id = int.tryParse(campos['produto'] ?? '');
  final unidade = id == null ? null : nomes.unidades[id];
  final numero = formatarQuantidade(valor, unidade ?? '');
  if (unidade == null || unidade.isEmpty) return numero;
  return '$numero ${unidadeParaQuantidade(unidade, valor)}';
}

String _juntar(List<String> fragmentos) => fragmentos.join(' · ');

String _humanizar(String evento) {
  if (evento.isEmpty) return 'registrou um evento do sistema';
  final palavras = evento
      .toLowerCase()
      .split('_')
      .where((palavra) => palavra.isNotEmpty);
  return palavras.isEmpty
      ? 'registrou um evento do sistema'
      : palavras.join(' ');
}
