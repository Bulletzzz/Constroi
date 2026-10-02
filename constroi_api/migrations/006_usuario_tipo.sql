-- Mantem os perfis do banco alinhados com os niveis aceitos pela API.
ALTER TABLE usuario
    ADD CONSTRAINT ck_usuario_tipo
    CHECK (tipo IN ('pedreiro', 'engenheiro', 'master'));
