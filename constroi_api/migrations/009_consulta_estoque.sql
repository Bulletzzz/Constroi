ALTER TABLE produto
    ADD COLUMN sku VARCHAR(50),
    ADD COLUMN estoque_minimo NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD CONSTRAINT ck_produto_estoque_minimo CHECK (estoque_minimo >= 0),
    ADD CONSTRAINT ck_produto_sku CHECK (sku IS NULL OR LENGTH(TRIM(sku)) > 0);

CREATE UNIQUE INDEX ux_produto_sku_empresa
    ON produto (empresa_id, LOWER(sku)) WHERE sku IS NOT NULL;
