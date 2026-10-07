ALTER TABLE estoque
    ALTER COLUMN quantidade TYPE NUMERIC(12, 2);

ALTER TABLE estoque
    ALTER COLUMN quantidade SET DEFAULT 0;

ALTER TABLE estoque
    ADD CONSTRAINT ck_estoque_quantidade CHECK (quantidade >= 0);

ALTER TABLE estoque
    ADD CONSTRAINT ux_estoque_obra_produto UNIQUE (obra_id, produto_id);
