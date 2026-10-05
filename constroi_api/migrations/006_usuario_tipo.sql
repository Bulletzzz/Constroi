-- Converte o perfil administrativo legado para o perfil administrativo atual.
-- A API e a migration aceitam pedreiro, engenheiro e master.
UPDATE usuario
SET tipo = 'master'
WHERE LOWER(TRIM(tipo)) = 'admin';

-- Mantem os perfis do banco alinhados com os niveis aceitos pela API.
ALTER TABLE usuario
    ADD CONSTRAINT ck_usuario_tipo
    CHECK (tipo IN ('pedreiro', 'engenheiro', 'master'));
