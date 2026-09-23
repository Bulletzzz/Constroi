import 'package:bcrypt/bcrypt.dart';

const minimoDaSenha = 8;

const _hashFalso =
    r'$2b$12$C6UzMDM.H6dfI/f/IKcEe.6fMLrNGCCOXHZ8PMHLZ1RrEPUJ/zzXG';

const _senhasComuns = {
  '12345678', '123456789', '1234567890', '12345678910', '123123123',
  '87654321', '11111111', '00000000', '88888888', '99999999',
  '1q2w3e4r', '1qaz2wsx', 'qwertyui', 'qwerty123', 'asdfghjk',
  'abcd1234', 'abc12345', 'a1b2c3d4', 'zaq12wsx', 'qazwsxedc',
  'password', 'password1', 'password123', 'passw0rd', 'iloveyou',
  'sunshine', 'princess', 'trustno1', 'superman', 'letmein1',
  'football', 'baseball', 'dragon123', 'monkey123', 'shadow123',
  'senha123', 'senha1234', 'senhasenha', 'minhasenha', 'senha@123',
  'brasil123', 'brasil2026', 'futebol1', 'flamengo', 'corinthians',
  'palmeiras', 'saopaulo', 'gremio12', 'vasco123', 'santos123',
  'admin123', 'administrador', 'usuario123', 'teste123', 'testando',
  'mudar123', 'mudar@123', 'constroi', 'constroi123', 'pedreiro',
  'engenheiro', 'obra1234', 'cimento1', 'construcao',
};

String gerarHash(String senha) =>
    BCrypt.hashpw(senha, BCrypt.gensalt(logRounds: 12));

bool senhaConfere(String senha, String hash) {
  try {
    return BCrypt.checkpw(senha, hash);
  } catch (_) {
    return false;
  }
}

void gastarTempoDeComparacao(String senha) {
  senhaConfere(senha, _hashFalso);
}

String? erroDaSenha(String senha) {
  if (senha.length < minimoDaSenha) {
    return 'A senha deve ter no minimo $minimoDaSenha caracteres.';
  }
  if (_senhasComuns.contains(senha.toLowerCase())) {
    return 'Esta senha e muito comum. Escolha outra.';
  }
  return null;
}
