import 'package:file_selector/file_selector.dart';

import 'nfe_preview.dart';

typedef EscolherXml = Future<NfePreview?> Function();

Future<NfePreview?> escolherXml() async {
  final arquivo = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'XML de NF-e',
        extensions: ['xml'],
        mimeTypes: ['application/xml', 'text/xml'],
        uniformTypeIdentifiers: ['public.xml'],
      ),
    ],
  );
  if (arquivo == null) return null;
  // Evita carregar arquivos grandes na memória antes da validação.
  if (await arquivo.length() > limiteXmlNfe) {
    throw const FormatException('O arquivo excede o limite de 2 MiB.');
  }
  return NfePreview.ler(arquivo.name, await arquivo.readAsBytes());
}
