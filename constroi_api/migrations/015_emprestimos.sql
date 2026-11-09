CREATE UNIQUE INDEX IF NOT EXISTS ux_equipamento_id_empresa
    ON equipamento (id, empresa_id);

ALTER TABLE emprestimo ADD COLUMN IF NOT EXISTS empresa_id INTEGER;
ALTER TABLE emprestimo ADD COLUMN IF NOT EXISTS data_prevista TIMESTAMPTZ;

UPDATE emprestimo p SET empresa_id = e.empresa_id
FROM equipamento e WHERE e.id = p.equipamento_id AND p.empresa_id IS NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM emprestimo WHERE data_prevista IS NULL) THEN
        RAISE EXCEPTION 'Preencha data_prevista dos emprestimos legados antes da migration 015';
    END IF;
END $$;

ALTER TABLE emprestimo ALTER COLUMN empresa_id SET NOT NULL;
ALTER TABLE emprestimo ALTER COLUMN data_prevista SET NOT NULL;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS emprestimo_equipamento_id_fkey;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS emprestimo_usuario_id_fkey;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS emprestimo_obra_id_fkey;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS fk_emprestimo_equipamento_empresa;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS fk_emprestimo_usuario_empresa;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS fk_emprestimo_obra_empresa;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS ck_emprestimo_status;
ALTER TABLE emprestimo DROP CONSTRAINT IF EXISTS ck_emprestimo_datas;
ALTER TABLE emprestimo ADD CONSTRAINT fk_emprestimo_equipamento_empresa
    FOREIGN KEY (equipamento_id, empresa_id)
    REFERENCES equipamento (id, empresa_id) ON DELETE RESTRICT;
ALTER TABLE emprestimo ADD CONSTRAINT fk_emprestimo_usuario_empresa
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES usuario (id, empresa_id) ON DELETE RESTRICT;
ALTER TABLE emprestimo ADD CONSTRAINT fk_emprestimo_obra_empresa
    FOREIGN KEY (obra_id, empresa_id)
    REFERENCES obra (id, empresa_id) ON DELETE RESTRICT;
ALTER TABLE emprestimo ADD CONSTRAINT ck_emprestimo_status
    CHECK (status IN ('aberto', 'devolvido'));
ALTER TABLE emprestimo ADD CONSTRAINT ck_emprestimo_datas CHECK (
    isfinite(data_emprestimo) AND isfinite(data_prevista)
    AND data_prevista > data_emprestimo
    AND ((status = 'aberto' AND data_devolucao IS NULL)
        OR (status = 'devolvido' AND data_devolucao IS NOT NULL
            AND isfinite(data_devolucao) AND data_devolucao >= data_emprestimo))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_emprestimo_equipamento_aberto
    ON emprestimo (equipamento_id) WHERE status = 'aberto';
CREATE INDEX IF NOT EXISTS ix_emprestimo_empresa_data
    ON emprestimo (empresa_id, data_emprestimo DESC, id DESC);

UPDATE equipamento e SET status = 'em_uso', atualizado_em = CURRENT_TIMESTAMP
WHERE e.status <> 'em_uso' AND EXISTS (
    SELECT 1 FROM emprestimo p
    WHERE p.equipamento_id = e.id AND p.empresa_id = e.empresa_id
        AND p.status = 'aberto'
);
