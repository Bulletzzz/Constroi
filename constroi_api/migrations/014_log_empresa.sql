-- Materializa a empresa dos registros existentes sem alterar autor, texto ou data.
ALTER TABLE log_sistema ADD COLUMN IF NOT EXISTS empresa_id INTEGER;

UPDATE log_sistema l
SET empresa_id = u.empresa_id
FROM usuario u
WHERE u.id = l.usuario_id AND l.empresa_id IS NULL;

ALTER TABLE log_sistema ALTER COLUMN empresa_id SET NOT NULL;
ALTER TABLE log_sistema DROP CONSTRAINT IF EXISTS fk_log_usuario_empresa;
ALTER TABLE log_sistema
    ADD CONSTRAINT fk_log_usuario_empresa
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES usuario (id, empresa_id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS ix_log_empresa_periodo
    ON log_sistema (empresa_id, data DESC, id DESC);
CREATE INDEX IF NOT EXISTS ix_log_empresa_usuario_periodo
    ON log_sistema (empresa_id, usuario_id, data DESC, id DESC);
