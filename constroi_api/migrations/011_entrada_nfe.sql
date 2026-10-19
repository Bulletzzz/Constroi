-- Reexecucao preserva colunas/dados existentes e restaura as constraints.
ALTER TABLE entrada_estoque
  ADD COLUMN IF NOT EXISTS empresa_nfe_id INTEGER,
  ADD COLUMN IF NOT EXISTS chave_nfe VARCHAR(44),
  DROP CONSTRAINT IF EXISTS fk_entrada_nfe_empresa,
  DROP CONSTRAINT IF EXISTS ck_entrada_nfe_chave,
  DROP CONSTRAINT IF EXISTS ux_entrada_nfe_empresa;

ALTER TABLE entrada_estoque
  ADD CONSTRAINT fk_entrada_nfe_empresa FOREIGN KEY (obra_id, empresa_nfe_id)
    REFERENCES obra (id, empresa_id),
  ADD CONSTRAINT ck_entrada_nfe_chave CHECK (
    (empresa_nfe_id IS NULL AND chave_nfe IS NULL) OR
    (empresa_nfe_id IS NOT NULL AND chave_nfe IS NOT NULL
      AND chave_nfe ~ '^[0-9]{44}$' AND xml_nota_fiscal IS NOT NULL)
  ),
  ADD CONSTRAINT ux_entrada_nfe_empresa UNIQUE (empresa_nfe_id, chave_nfe);
