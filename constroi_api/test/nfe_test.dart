import 'dart:convert';

import 'package:constroi_api/nfe.dart';
import 'package:test/test.dart';

import 'fixtures/nfe.dart';

void main() {
  test('le NF-e, mantem original e converte quantidade sem double', () {
    final xml = xmlNfe();
    final nota = lerNfe(utf8.encode(xml));
    expect(nota.xml, xml);
    expect(nota.chave, '1' * 44);
    expect(nota.itens.single.quantidade, '1.25');
    expect(nota.itens.single.codigo, 'CIM-01');
  });
  test('aceita NFe sem envelope e prefixo de namespace', () {
    final xml = xmlNfe()
        .replaceAll('<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">', '')
        .replaceAll('</nfeProc>', '')
        .replaceAll(
          '<NFe>',
          '<NFe xmlns="http://www.portalfiscal.inf.br/nfe">',
        );
    expect(lerNfe(utf8.encode(xml)).itens, hasLength(1));
    final prefixado = xmlNfe()
        .replaceAll('xmlns=', 'xmlns:n=')
        .replaceAllMapped(
          RegExp(
            r'<(/?)(nfeProc|NFe|infNFe|det|prod|cProd|xProd|uCom|qCom)([\s>])',
          ),
          (m) => '<${m[1]}n:${m[2]}${m[3]}',
        );
    expect(lerNfe(utf8.encode(prefixado)).itens.single.nome, 'Cimento');
  });
  test('rejeita XML malformado, estrutura ambigua, DTD e nota vazia', () {
    for (final xml in [
      '<NFe>',
      '<outro/>',
      xmlNfe(itens: ''),
      xmlNfe().replaceAll('NFe${'1' * 44}', 'NFe123'),
      '<!DOCTYPE a [<!ENTITY x SYSTEM "file:///secret">]>${xmlNfe()}',
      xmlNfe().replaceAll('</prod>', '<qCom>1</qCom></prod>'),
      xmlNfe().replaceAll(namespaceNfe, 'http://outro'),
    ]) {
      expect(
        () => lerNfe(utf8.encode(xml)),
        throwsA(isA<FalhaNfe>().having((e) => e.status, 'status', 400)),
      );
    }
  });
  test('limita tamanho, itens e UTF-8 invalido', () {
    expect(
      () => lerNfe(List.filled(limiteXmlNfe + 1, 32)),
      throwsA(isA<FalhaNfe>()),
    );
    expect(() => lerNfe([255]), throwsA(isA<FalhaNfe>()));
    expect(
      () => lerNfe(utf8.encode(xmlNfe(itens: materialXml() * 201))),
      throwsA(isA<FalhaNfe>()),
    );
  });
  test(
    'quantidades respeitam NUMERIC(12,2), nao arredondam nem aceitam NaN',
    () {
      for (final entrada in [
        '0',
        '-1',
        '1.001',
        'NaN',
        'Infinity',
        '1e2',
        '10000000000',
        '1,25',
      ]) {
        expect(decimalNfe(entrada), isNull);
      }
      expect(decimalNfe('9999999999.9900'), '9999999999.99');
      expect(decimalNfe('0.0100'), '0.01');
    },
  );
}
