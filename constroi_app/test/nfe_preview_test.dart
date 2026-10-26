import 'dart:convert';
import 'dart:io';

import 'package:constroi_app/features/nfe/nfe_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nfe_fixture.dart';

void main() {
  test('prévia respeita o mesmo contrato XML e resultado da API', () {
    final bytes = File('../testes/fixtures/nfe/contrato.xml').readAsBytesSync();
    final esperado = jsonDecode(
      File('../testes/fixtures/nfe/contrato.json').readAsStringSync(),
    );
    final nota = NfePreview.ler('contrato.xml', bytes);
    expect({
      'chave': nota.chave,
      'itens': [
        for (final item in nota.materiais)
          {
            'codigo': item.codigo,
            'nome': item.nome,
            'unidade': item.unidade,
            'quantidade': item.quantidade,
          },
      ],
    }, esperado);
    expect(nota.bytes, bytes);
  });

  test('lê NF-e e preserva bytes originais e quantidades sem arredondar', () {
    final bytes = utf8.encode(xmlNfe(nome: 'Cimento &amp; argamassa'));
    final nota = NfePreview.ler('NOTA.XML', bytes);
    expect(nota.chave, chaveNfe);
    expect(nota.bytes, bytes);
    expect(nota.materiais.single.nome, 'Cimento & argamassa');
    expect(nota.materiais.single.codigo, 'CIM-01');
    expect(nota.materiais.single.unidade, 'sc');
    expect(nota.materiais.single.quantidade, '1.25');
    bytes[0] = 0;
    expect(nota.bytes.first, 60);
    expect(() => nota.bytes[0] = 0, throwsUnsupportedError);
  });

  test('aceita raiz NFe e namespace prefixado', () {
    final xml = xmlNfe()
        .replaceAll(
          '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe"><NFe>',
          '<f:NFe xmlns:f="http://www.portalfiscal.inf.br/nfe">',
        )
        .replaceAll('</NFe></nfeProc>', '</f:NFe>');
    final prefixado = xml.replaceAllMapped(
      RegExp(r'<(/?)(infNFe|det|prod|cProd|xProd|uCom|qCom)([ >])'),
      (m) => '<${m[1]}f:${m[2]}${m[3]}',
    );
    expect(
      NfePreview.ler('nota.xml', utf8.encode(prefixado)).materiais.length,
      1,
    );
  });

  for (final quantidade in ['0', '-1', '1.234', '1e3', '10000000000', '1,25']) {
    test('rejeita quantidade $quantidade', () {
      expect(
        () => NfePreview.ler(
          'nota.xml',
          utf8.encode(xmlNfe(quantidade: quantidade)),
        ),
        throwsFormatException,
      );
    });
  }
  for (final quantidade in ['1', '0.0100', '9999999999.9900']) {
    test('aceita quantidade $quantidade', () {
      expect(
        NfePreview.ler(
          'nota.xml',
          utf8.encode(xmlNfe(quantidade: quantidade)),
        ).materiais,
        hasLength(1),
      );
    });
  }
  final invalidos = <String, String>{
    'XML malformado': '<NFe>',
    'outra estrutura': '<nota/>',
    'namespace incorreto': xmlNfe().replaceAll(
      'http://www.portalfiscal.inf.br/nfe',
      'urn:outro',
    ),
    'chave ausente': xmlNfe().replaceAll('Id="NFe$chaveNfe"', ''),
    'sem materiais': xmlNfe(itens: ''),
    'produto sem código': xmlNfe().replaceAll('<cProd>CIM-01</cProd>', ''),
    'campo ambíguo': xmlNfe().replaceAll(
      '<cProd>CIM-01</cProd>',
      '<cProd>A</cProd><cProd>B</cProd>',
    ),
    'DTD':
        '<!DOCTYPE nfe [<!ENTITY teste SYSTEM "file:///segredo">]>${xmlNfe()}',
    'mais de 200 materiais': xmlNfe(itens: List.filled(201, '<det/>').join()),
  };
  for (final caso in invalidos.entries) {
    test('rejeita ${caso.key}', () {
      expect(
        () => NfePreview.ler('nota.xml', utf8.encode(caso.value)),
        throwsFormatException,
      );
    });
  }
  test('valida extensão, arquivo vazio, UTF-8 e limite em bytes', () {
    expect(
      () => NfePreview.ler('nota.pdf', utf8.encode(xmlNfe())),
      throwsFormatException,
    );
    expect(() => NfePreview.ler('nota.xml', []), throwsFormatException);
    expect(() => NfePreview.ler('nota.xml', [0xff]), throwsFormatException);
    expect(
      () => NfePreview.ler('nota.xml', List.filled(limiteXmlNfe + 1, 32)),
      throwsFormatException,
    );
  });
}
