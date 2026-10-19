ALTER TABLE pedido
    ADD COLUMN IF NOT EXISTS local_obra VARCHAR(120);

ALTER TABLE pedido
    ADD COLUMN IF NOT EXISTS urgencia VARCHAR(20) NOT NULL DEFAULT 'padrao';

ALTER TABLE pedido
    DROP CONSTRAINT IF EXISTS ck_pedido_urgencia;

ALTER TABLE pedido
    ADD CONSTRAINT ck_pedido_urgencia
    CHECK (urgencia IN ('padrao', 'urgente'));

ALTER TABLE pedido
    DROP CONSTRAINT IF EXISTS ck_pedido_local_obra;

ALTER TABLE pedido
    ADD CONSTRAINT ck_pedido_local_obra
    CHECK (local_obra IS NULL OR LENGTH(TRIM(local_obra)) > 0);
