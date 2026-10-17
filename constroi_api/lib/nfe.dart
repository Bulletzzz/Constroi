import 'dart:convert';

import 'package:xml/xml.dart';

const limiteXmlNfe = 2 * 1024 * 1024;
const namespaceNfe = 'http://www.portalfiscal.inf.br/nfe';

class FalhaNfe implements Exception {
  const FalhaNfe(this.status, this.mensagem, {this.detalhes = const {}});
  final int status;
  final String mensagem;
  final Map<String, Object?> detalhes;
}

typedef MaterialNfe = ({
  String codigo,
  String nome,
  String unidade,
  String quantidade,
});

class NotaFiscal {
  const NotaFiscal(this.xml, this.chave, this.itens);
  final String xml;
  final String chave;
  final List<MaterialNfe> itens;
}

/// Mantem o texto recebido, sem consultar rede ou validar assinatura fiscal.
NotaFiscal lerNfe(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > limiteXmlNfe) {
    throw const FalhaNfe(400, 'Envie um XML de ate 2 MiB.');
  }
  try {
    final original = utf8.decode(bytes);
    if (RegExp(
      r'<!\s*(DOCTYPE|ENTITY)',
      caseSensitive: false,
    ).hasMatch(original)) {
      throw const FalhaNfe(400, 'DTD e entidades externas nao sao permitidos.');
    }
    final doc = XmlDocument.parse(original);
    final raiz = doc.rootElement;
    XmlElement? nfe;
    if (raiz.name.local == 'NFe') nfe = raiz;
    if (raiz.name.local == 'nfeProc') nfe = _filho(raiz, 'NFe');
    if (nfe == null || nfe.name.namespaceUri != namespaceNfe) {
      throw const FalhaNfe(400, 'Envie uma NF-e no namespace oficial.');
    }
    final info = _filho(nfe, 'infNFe');
    final identificador = info?.getAttribute('Id') ?? '';
    if (info == null || !RegExp(r'^NFe\d{44}$').hasMatch(identificador)) {
      throw const FalhaNfe(
        400,
        'A NF-e deve informar uma chave de 44 digitos.',
      );
    }
    final detalhes = info.childElements
        .where(
          (e) => e.name.local == 'det' && e.name.namespaceUri == namespaceNfe,
        )
        .toList();
    if (detalhes.isEmpty || detalhes.length > 200) {
      throw const FalhaNfe(400, 'A NF-e deve conter de 1 a 200 materiais.');
    }
    final itens = <MaterialNfe>[];
    for (final det in detalhes) {
      final produto = _filho(det, 'prod');
      if (produto == null) {
        throw const FalhaNfe(400, 'Material da NF-e sem prod.');
      }
      final codigo = _texto(produto, 'cProd');
      final nome = _texto(produto, 'xProd');
      final unidade = _texto(produto, 'uCom').toLowerCase();
      final quantidade = decimalNfe(_texto(produto, 'qCom'));
      if (codigo.isEmpty ||
          codigo.length > 60 ||
          nome.isEmpty ||
          nome.length > 150 ||
          unidade.isEmpty ||
          unidade.length > 20 ||
          quantidade == null) {
        throw const FalhaNfe(
          400,
          'Material invalido: informe codigo, nome, unidade e quantidade '
          'positiva com ate duas casas decimais.',
        );
      }
      itens.add((
        codigo: codigo,
        nome: nome,
        unidade: unidade,
        quantidade: quantidade,
      ));
    }
    return NotaFiscal(
      original,
      identificador.substring(3),
      List.unmodifiable(itens),
    );
  } on FalhaNfe {
    rethrow;
  } on FormatException {
    throw const FalhaNfe(
      400,
      'XML malformado ou codificacao diferente de UTF-8.',
    );
  } on XmlException {
    throw const FalhaNfe(400, 'XML malformado.');
  }
}

XmlElement? _filho(XmlElement elemento, String nome) {
  final encontrados = elemento.childElements
      .where((e) => e.name.local == nome && e.name.namespaceUri == namespaceNfe)
      .toList();
  if (encontrados.length > 1) {
    throw const FalhaNfe(400, 'Estrutura da NF-e ambigua.');
  }
  return encontrados.isEmpty ? null : encontrados.single;
}

String _texto(XmlElement elemento, String nome) =>
    _filho(elemento, nome)?.innerText.trim() ?? '';

/// Aceita zeros extras de qCom, nunca arredonda nem usa double.
String? decimalNfe(String texto) {
  final partes = RegExp(r'^(\d{1,10})(?:\.(\d{1,10}))?$').firstMatch(texto);
  if (partes == null) return null;
  final fracao = (partes[2] ?? '').padRight(2, '0');
  if (fracao.length > 2 && fracao.substring(2).contains(RegExp('[1-9]'))) {
    return null;
  }
  final inteiro = BigInt.parse(partes[1]!);
  final centesimos =
      inteiro * BigInt.from(100) + BigInt.parse(fracao.substring(0, 2));
  if (centesimos <= BigInt.zero) return null;
  return '$inteiro.${fracao.substring(0, 2)}';
}
