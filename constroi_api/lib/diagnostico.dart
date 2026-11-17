final _conexaoPostgres = RegExp(
  r'postgres(?:ql)?://[^\r\n]*',
  caseSensitive: false,
);

String semCredenciais(Object erro, [StackTrace? pilha]) {
  final texto = pilha == null ? '$erro' : '$erro\n$pilha';
  return texto.replaceAll(_conexaoPostgres, '[conexao PostgreSQL omitida]');
}
