# Contrato de leitura da NF-e

`contrato.xml` e `contrato.json` são compartilhados pelos testes do parser da
API (`constroi_api/test/nfe_test.dart`) e da prévia no aplicativo
(`constroi_app/test/nfe_preview_test.dart`).

Ambos devem produzir exatamente a mesma chave e lista de materiais do JSON.
O XML cobre espaços, entidade escapada, unidades `SC`, `M3` e `Un`, decimais
com zeros extras e quantidade inteira. Os testes também preservam o documento
original: a normalização é só nos dados lidos, não no arquivo enviado.

Ao alterar a leitura, rode os dois testes. Não crie cópias desta fixture nos
pacotes: a entrada e o resultado esperado precisam continuar compartilhados.

```powershell
Push-Location constroi_api
dart test test/nfe_test.dart
Pop-Location
Push-Location constroi_app
flutter test --no-pub test/nfe_preview_test.dart
Pop-Location
```
