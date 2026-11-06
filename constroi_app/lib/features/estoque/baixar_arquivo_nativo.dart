import 'package:flutter/services.dart';

Future<String> baixarTexto(String nome, String conteudo) async {
  await Clipboard.setData(ClipboardData(text: conteudo));
  return 'A planilha foi copiada. Cole em um editor e salve como $nome.';
}
