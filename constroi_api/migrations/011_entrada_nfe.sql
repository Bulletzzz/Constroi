-- 010 esta reservada pelo PR #26 (campos de pedido); nao altera essa entrega.
ALTER TABLE entrada_estoque
  ADD COLUMN empresa_nfe_id INTEGER,
  ADD COLUMN chave_nfe VARCHAR(44),
  ADD CONSTRAINT fk_entrada_nfe_empresa FOREIGN KEY (obra_id, empresa_nfe_id)
    REFERENCES obra (id, empresa_id),
  ADD CONSTRAINT ck_entrada_nfe_chave CHECK (
    (empresa_nfe_id IS NULL AND chave_nfe IS NULL) OR
    (empresa_nfe_id IS NOT NULL AND chave_nfe IS NOT NULL
      AND chave_nfe ~ '^[0-9]{44}$' AND xml_nota_fiscal IS NOT NULL)
  ),
  ADD CONSTRAINT ux_entrada_nfe_empresa UNIQUE (empresa_nfe_id, chave_nfe);
