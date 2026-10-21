// Totais, categorias e pagina usam o mesmo snapshot e os precos historicos.
const consultaCustos = '''
WITH obras_visiveis AS (
  SELECT id, nome FROM obra WHERE empresa_id = @empresa
), obras_filtradas AS (
  SELECT * FROM obras_visiveis WHERE @obra::int IS NULL OR id = @obra
), lancamentos AS (
  SELECT l.*, o.nome AS obra_nome, c.nome AS categoria_nome
  FROM vw_lancamento_custo l
  JOIN obras_filtradas o ON o.id = l.obra_id
  JOIN categoria_custo c ON c.id = l.categoria_custo_id
), periodo AS (
  SELECT * FROM lancamentos
  WHERE @periodo = 'total' OR data_lancamento >= (
    date_trunc(
      CASE WHEN @periodo = 'semana' THEN 'week' ELSE 'month' END,
      CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo'
    ) AT TIME ZONE 'America/Sao_Paulo'
  )
), totais AS (
  SELECT r.*, o.nome,
    COALESCE((SELECT SUM(p.valor) FROM periodo p WHERE p.obra_id = o.id), 0)
      AS custo_periodo
  FROM obras_filtradas o
  JOIN vw_resumo_custo_obra r ON r.obra_id = o.id
), resumo AS (
  SELECT COALESCE(SUM(custo_acumulado), 0) AS custo_acumulado,
    COALESCE(SUM(custo_periodo), 0) AS custo_periodo,
    CASE WHEN COUNT(*) = COUNT(orcamento_total) THEN SUM(orcamento_total) END
      AS orcamento_total
  FROM totais
), categorias AS (
  SELECT categoria_custo_id AS id, categoria_nome AS nome, SUM(valor) AS valor
  FROM periodo GROUP BY categoria_custo_id, categoria_nome
), recentes AS (
  SELECT * FROM periodo
  ORDER BY data_lancamento DESC, origem, origem_id DESC
  LIMIT @limite OFFSET @offset
)
SELECT jsonb_build_object(
  'obra_permitida', @obra::int IS NULL OR EXISTS (
    SELECT 1 FROM obras_visiveis WHERE id = @obra
  ),
  'obras', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY nome, id)
    FROM obras_visiveis o), '[]'::jsonb),
  'obra_id', @obra::int,
  'periodo', @periodo::text,
  'resumo', (SELECT jsonb_build_object(
    'custo_acumulado', custo_acumulado::text,
    'custo_periodo', custo_periodo::text,
    'orcamento_total', orcamento_total::text,
    'saldo_orcamento', (orcamento_total - custo_acumulado)::text,
    'percentual_consumido', CASE WHEN orcamento_total > 0
      THEN ROUND(custo_acumulado * 100 / orcamento_total, 1)::text END,
    'lancamentos_periodo', (SELECT COUNT(*) FROM periodo),
    'itens_sem_preco', (
      SELECT COUNT(*) FROM item_entrada ie
      JOIN entrada_estoque ee ON ee.id = ie.entrada_id
      JOIN obras_filtradas o ON o.id = ee.obra_id
      WHERE ie.valor_unitario IS NULL
    )
  ) FROM resumo),
  'totais_por_obra', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'obra_id', obra_id, 'nome', nome,
      'custo_acumulado', custo_acumulado::text,
      'custo_periodo', custo_periodo::text,
      'orcamento_total', orcamento_total::text,
      'saldo_orcamento', saldo_orcamento::text,
      'percentual_consumido', percentual_consumido::text
    ) ORDER BY nome, obra_id) FROM totais
  ), '[]'::jsonb),
  'categorias', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id', id, 'nome', nome,
      'valor', valor::text) ORDER BY valor DESC, id) FROM categorias
  ), '[]'::jsonb),
  'lancamentos', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'origem', origem, 'origem_id', origem_id,
      'obra_id', obra_id, 'obra_nome', obra_nome,
      'descricao', descricao, 'categoria_nome', categoria_nome,
      'data_lancamento', data_lancamento, 'valor', valor::text
    ) ORDER BY data_lancamento DESC, origem, origem_id DESC) FROM recentes
  ), '[]'::jsonb)
) AS dados
''';
