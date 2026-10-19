String xmlNfe({
  String chave = '11111111111111111111111111111111111111111111',
  String? itens,
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe"><NFe>\n'
    '<infNFe Id="NFe$chave" versao="4.00">\n'
    '${itens ?? materialXml()}\n'
    '</infNFe></NFe></nfeProc>';

String materialXml({
  String codigo = 'CIM-01',
  String nome = 'Cimento',
  String quantidade = '1.2500',
  String unidade = 'saco',
}) => '''
<det nItem="1"><prod><cProd>$codigo</cProd><xProd>$nome</xProd><uCom>$unidade</uCom><qCom>$quantidade</qCom></prod></det>''';
