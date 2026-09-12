import 'package:bcrypt/bcrypt.dart';

/// Hash de comparacao usado quando o email nao existe, para que a resposta
/// demore o mesmo tanto e ninguem descubra quais emails estao cadastrados.
const _hashFalso =
    r'$2b$12$C6UzMDM.H6dfI/f/IKcEe.6fMLrNGCCOXHZ8PMHLZ1RrEPUJ/zzXG';

/// Gera o hash bcrypt da senha, com salt novo a cada chamada.
String gerarHash(String senha) =>
    BCrypt.hashpw(senha, BCrypt.gensalt(logRounds: 12));

/// Compara a senha digitada com o hash guardado no banco.
bool senhaConfere(String senha, String hash) {
  try {
    return BCrypt.checkpw(senha, hash);
  } catch (_) {
    return false;
  }
}

/// Faz uma comparacao descartavel para igualar o tempo de resposta.
void gastarTempoDeComparacao(String senha) {
  senhaConfere(senha, _hashFalso);
}
