import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

const limiteXmlNfe = 2 * 1024 * 1024;
const _namespace = 'http://www.portalfiscal.inf.br/nfe';

class MaterialNfe {
  const MaterialNfe(this.codigo, this.nome, this.unidade, this.quantidade);
  final String codigo;
  final String nome;
  final String unidade;
  final String quantidade;
}

/// Prévia local. O servidor continua responsável por catálogo e unicidade.
class NfePreview {
  NfePreview._(this.nomeArquivo, this.bytes, this.chave, this.materiais);
  final String nomeArquivo;
  final Uint8List bytes;
  final String chave;
  final List<MaterialNfe> materiais;

  factory NfePreview.ler(String nomeArquivo, List<int> bytes) {
    if (!nomeArquivo.toLowerCase().endsWith('.xml')) {
      throw const FormatException('Escolha um arquivo com extensão .xml.');
    }
    if (bytes.isEmpty || bytes.length > limiteXmlNfe) {
      throw const FormatException('Escolha um XML não vazio de até 2 MiB.');
    }
    try {
      final String original;
      try {
        original = utf8.decode(bytes);
      } on FormatException {
        throw const FormatException('O XML deve estar codificado em UTF-8.');
      }
      if (RegExp(
        r'<!\s*(DOCTYPE|ENTITY)',
        caseSensitive: false,
      ).hasMatch(original)) {
        throw const FormatException(
          'O XML não pode conter DTD ou entidades externas.',
        );
      }
      final raiz = XmlDocument.parse(original).rootElement;
      final nfe = raiz.name.local == 'NFe'
          ? raiz
          : raiz.name.local == 'nfeProc'
          ? _filho(raiz, 'NFe')
          : null;
      if (nfe == null || nfe.name.namespaceUri != _namespace) {
        throw const FormatException(
          'Escolha um XML de NF-e no formato oficial.',
        );
      }
      final info = _filho(nfe, 'infNFe');
      final id = info?.getAttribute('Id') ?? '';
      if (info == null || !RegExp(r'^NFe\d{44}$').hasMatch(id)) {
        throw const FormatException(
          'A NF-e deve informar uma chave de 44 dígitos.',
        );
      }
      final detalhes = info.childElements
          .where(
            (e) => e.name.local == 'det' && e.name.namespaceUri == _namespace,
          )
          .toList();
      if (detalhes.isEmpty || detalhes.length > 200) {
        throw const FormatException('A NF-e deve conter de 1 a 200 materiais.');
      }
      final materiais = <MaterialNfe>[];
      for (final detalhe in detalhes) {
        final produto = _filho(detalhe, 'prod');
        if (produto == null) {
          throw const FormatException(
            'Há um material sem dados de produto no XML.',
          );
        }
        final codigo = _texto(produto, 'cProd');
        final nome = _texto(produto, 'xProd');
        final unidade = _texto(produto, 'uCom').toLowerCase();
        final quantidade = _decimal(_texto(produto, 'qCom'));
        if (codigo.isEmpty ||
            codigo.length > 60 ||
            nome.isEmpty ||
            nome.length > 150 ||
            unidade.isEmpty ||
            unidade.length > 20 ||
            quantidade == null) {
          throw const FormatException(
            'Confira código, nome, unidade e quantidade dos materiais. '
            'A quantidade deve ser positiva e ter até duas casas decimais.',
          );
        }
        materiais.add(MaterialNfe(codigo, nome, unidade, quantidade));
      }
      return NfePreview._(
        nomeArquivo,
        Uint8List.fromList(bytes).asUnmodifiableView(),
        id.substring(3),
        List.unmodifiable(materiais),
      );
    } on XmlException {
      throw const FormatException('XML malformado. Escolha outro arquivo.');
    }
  }
}

XmlElement? _filho(XmlElement elemento, String nome) {
  final filhos = elemento.childElements
      .where((e) => e.name.local == nome && e.name.namespaceUri == _namespace)
      .toList();
  if (filhos.length > 1) {
    throw const FormatException('O XML contém campos duplicados na NF-e.');
  }
  return filhos.firstOrNull;
}

String _texto(XmlElement elemento, String nome) =>
    _filho(elemento, nome)?.innerText.trim() ?? '';

String? _decimal(String valor) {
  final partes = RegExp(r'^(\d{1,10})(?:\.(\d{1,10}))?$').firstMatch(valor);
  if (partes == null) return null;
  final fracao = (partes[2] ?? '').padRight(2, '0');
  if (fracao.length > 2 && RegExp('[1-9]').hasMatch(fracao.substring(2))) {
    return null;
  }
  final inteiro = BigInt.parse(partes[1]!);
  final centavos =
      inteiro * BigInt.from(100) + BigInt.parse(fracao.substring(0, 2));
  if (centavos <= BigInt.zero) return null;
  return '$inteiro.${fracao.substring(0, 2)}';
}
