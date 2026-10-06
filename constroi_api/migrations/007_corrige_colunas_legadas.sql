DROP VIEW IF EXISTS vw_resumo_custo_obra;
DROP VIEW IF EXISTS vw_lancamento_custo;

ALTER TABLE pedido
    ALTER COLUMN protocolo TYPE VARCHAR(50);

ALTER TABLE pedido
    ALTER COLUMN data TYPE TIMESTAMPTZ USING data AT TIME ZONE 'UTC';

ALTER TABLE emprestimo
    ALTER COLUMN data_emprestimo TYPE TIMESTAMPTZ
    USING data_emprestimo AT TIME ZONE 'UTC';

ALTER TABLE emprestimo
    ALTER COLUMN data_devolucao TYPE TIMESTAMPTZ
    USING data_devolucao AT TIME ZONE 'UTC';

ALTER TABLE entrada_estoque
    ALTER COLUMN data TYPE TIMESTAMPTZ USING data AT TIME ZONE 'UTC';

ALTER TABLE log_sistema
    ALTER COLUMN data TYPE TIMESTAMPTZ USING data AT TIME ZONE 'UTC';

ALTER TABLE pedido
    ALTER COLUMN data SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE emprestimo
    ALTER COLUMN data_emprestimo SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE entrada_estoque
    ALTER COLUMN data SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE log_sistema
    ALTER COLUMN data SET DEFAULT CURRENT_TIMESTAMP;

CREATE VIEW vw_lancamento_custo AS
SELECT
    'material'::TEXT AS origem,
    ie.id::BIGINT AS origem_id,
    ee.obra_id,
    ie.categoria_custo_id,
    ee.data AS data_lancamento,
    p.nome AS descricao,
    ROUND(ie.quantidade * ie.valor_unitario, 2) AS valor
FROM item_entrada AS ie
JOIN entrada_estoque AS ee ON ee.id = ie.entrada_id
JOIN produto AS p ON p.id = ie.produto_id
WHERE ie.valor_unitario IS NOT NULL
UNION ALL
SELECT
    'despesa'::TEXT AS origem,
    d.id AS origem_id,
    d.obra_id,
    d.categoria_custo_id,
    d.data_lancamento,
    d.descricao,
    d.valor
FROM despesa_obra AS d;

CREATE VIEW vw_resumo_custo_obra AS
SELECT
    o.id AS obra_id,
    o.orcamento_total,
    COALESCE(SUM(l.valor), 0) AS custo_acumulado,
    CASE WHEN o.orcamento_total IS NULL THEN NULL
         ELSE o.orcamento_total - COALESCE(SUM(l.valor), 0)
    END AS saldo_orcamento,
    CASE WHEN o.orcamento_total > 0
         THEN ROUND(COALESCE(SUM(l.valor), 0) * 100 / o.orcamento_total, 1)
         ELSE NULL
    END AS percentual_consumido
FROM obra AS o
LEFT JOIN vw_lancamento_custo AS l ON l.obra_id = o.id
GROUP BY o.id, o.orcamento_total;
