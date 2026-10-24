class UnidadeProduto {
  const UnidadeProduto(this.codigo, this.rotulo);
  final String codigo;
  final String rotulo;
}

class StatusEquipamento {
  const StatusEquipamento(this.codigo, this.rotulo);
  final String codigo;
  final String rotulo;
}

const unidadesDoProduto = <UnidadeProduto>[
  UnidadeProduto('un', 'Unidade (un)'),
  UnidadeProduto('pc', 'Peça (pc)'),
  UnidadeProduto('cx', 'Caixa (cx)'),
  UnidadeProduto('pct', 'Pacote (pct)'),
  UnidadeProduto('saco', 'Saco'),
  UnidadeProduto('sacos', 'Sacos'),
  UnidadeProduto('barra', 'Barra'),
  UnidadeProduto('barras', 'Barras'),
  UnidadeProduto('rolo', 'Rolo'),
  UnidadeProduto('rolos', 'Rolos'),
  UnidadeProduto('kg', 'Quilograma (kg)'),
  UnidadeProduto('g', 'Grama (g)'),
  UnidadeProduto('ton', 'Tonelada (ton)'),
  UnidadeProduto('t', 'Tonelada (t)'),
  UnidadeProduto('l', 'Litro (l)'),
  UnidadeProduto('lt', 'Litro (lt)'),
  UnidadeProduto('ml', 'Mililitro (ml)'),
  UnidadeProduto('m', 'Metro (m)'),
  UnidadeProduto('m2', 'Metro quadrado (m2)'),
  UnidadeProduto('m3', 'Metro cúbico (m3)'),
];

const statusDoEquipamento = <StatusEquipamento>[
  StatusEquipamento('disponivel', 'Disponível'),
  StatusEquipamento('em_uso', 'Em uso'),
  StatusEquipamento('manutencao', 'Em manutenção'),
  StatusEquipamento('quebrado', 'Quebrado'),
  StatusEquipamento('inativo', 'Inativo'),
];

String rotuloDaUnidade(String codigo) => unidadesDoProduto
    .firstWhere(
      (u) => u.codigo == codigo,
      orElse: () => UnidadeProduto(codigo, codigo),
    )
    .rotulo;

String rotuloDoStatus(String codigo) => statusDoEquipamento
    .firstWhere(
      (s) => s.codigo == codigo,
      orElse: () => StatusEquipamento(codigo, codigo),
    )
    .rotulo;
