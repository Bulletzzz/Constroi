bool quantidadeInteiraObrigatoria(String unidade) =>
    {'un', 'saco', 'sacos'}.contains(unidade.trim().toLowerCase());

bool quantidadeValidaParaUnidade(String unidade, num quantidade) =>
    !quantidadeInteiraObrigatoria(unidade) ||
    quantidade == quantidade.truncateToDouble();
