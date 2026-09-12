import 'dart:io';

import 'package:dotenv/dotenv.dart';

final _ambiente = DotEnv(includePlatformEnvironment: true)
  ..load(File('.env').existsSync() ? ['.env'] : []);

/// Le do .env quando existe e cai para a variavel de ambiente do sistema,
/// que e como o docker-compose entrega os valores.
String? variavel(String nome) {
  final valor = _ambiente[nome]?.trim();
  return (valor == null || valor.isEmpty) ? null : valor;
}
