import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> baixarTexto(String nome, String conteudo) async {
  final partes = <JSAny>[utf8.encode('\uFEFF$conteudo').toJS].toJS;
  final arquivo = web.Blob(
    partes,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final endereco = web.URL.createObjectURL(arquivo);
  final ancora = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = endereco
    ..download = nome;
  ancora.click();
  web.URL.revokeObjectURL(endereco);
  return 'Planilha $nome gerada.';
}
