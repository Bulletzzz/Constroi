const chaveNfe = '11111111111111111111111111111111111111111111';

String xmlNfe({
  String quantidade = '1.2500',
  String nome = 'Cimento CP-II',
  String? itens,
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe"><NFe>'
    '<infNFe Id="NFe$chaveNfe">'
    '${itens ?? '<det nItem="1"><prod><cProd>CIM-01</cProd><xProd>$nome</xProd><uCom>SC</uCom><qCom>$quantidade</qCom></prod></det>'}'
    '</infNFe></NFe></nfeProc>';

Map<String, Object> resultadoNfe({bool anexo = false}) => {
  'id': 42,
  'obra_id': 7,
  'chave_nfe': chaveNfe,
  if (anexo) 'xml_anexado': true,
};

const pendenciasNfe = {
  'erro':
      'Confira os materiais antes de importar. Nenhuma entrada foi gravada.',
  'materiais_pendentes': [
    {
      'codigo': 'ARE-01',
      'nome': 'Areia fina',
      'unidade': 'm3',
      'motivo': 'nao_encontrado',
    },
    {
      'codigo': 'FER-01',
      'nome': 'Vergalhão',
      'unidade': 'kg',
      'motivo': 'ambiguo',
    },
    {
      'codigo': 'CIM-01',
      'nome': 'Cimento',
      'unidade': 'SC',
      'motivo': 'unidade_diferente',
    },
  ],
};
