import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:constroi_api/nfe.dart';
import 'package:dart_frog/dart_frog.dart';

/// Limita o corpo inteiro, inclusive campos e multipart sem Content-Length.
Future<({NotaFiscal nota, Map<String, String> campos})> receberNfe(
  Request request,
) async {
  try {
    final tipo = ContentType.parse(request.headers['content-type'] ?? '');
    if (tipo.mimeType != 'multipart/form-data' ||
        (tipo.parameters['boundary'] ?? '').isEmpty) {
      throw const FalhaNfe(
        400,
        'Envie multipart/form-data com o arquivo no campo xml.',
      );
    }
    var tamanho = 0;
    final buffer = BytesBuilder(copy: false);
    await for (final bloco in request.bytes().timeout(
      const Duration(seconds: 15),
    )) {
      tamanho += bloco.length;
      if (tamanho <= limiteXmlNfe + 65536) {
        buffer.add(bloco);
      }
    }
    // Drena sem acumular o excesso para responder 413 tambem em HTTP chunked.
    if (tamanho > limiteXmlNfe + 65536) {
      throw const FalhaNfe(413, 'O upload excede o limite permitido.');
    }
    final form = await request.copyWith(body: buffer.takeBytes()).formData();
    final arquivo = form.files['xml'];
    if (arquivo == null || form.files.length != 1) {
      throw const FalhaNfe(400, 'Envie somente um arquivo no campo xml.');
    }
    return (nota: lerNfe(await arquivo.readAsBytes()), campos: form.fields);
  } on FalhaNfe {
    rethrow;
  } on TimeoutException {
    throw const FalhaNfe(408, 'Tempo esgotado ao receber o arquivo.');
  } on Object {
    // Somente o parser de upload fica neste catch; erros do banco propagam.
    throw const FalhaNfe(400, 'Formulario multipart ou XML invalido.');
  }
}

Response erroNfe(FalhaNfe erro) => Response.json(
  statusCode: erro.status,
  body: {'erro': erro.mensagem, ...erro.detalhes},
);
