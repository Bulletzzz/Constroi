// Uma unica consulta mantem indicadores e movimentacoes no mesmo snapshot.
const consultaPainel = '''
WITH obras_visiveis AS (
  SELECT o.id, o.nome, o.status
  FROM obra o
  WHERE o.empresa_id = @empresa
    AND (@gestor OR EXISTS (
      SELECT 1 FROM usuario_obra uo
      WHERE uo.obra_id = o.id AND uo.usuario_id = @usuario
        AND uo.empresa_id = @empresa AND uo.data_fim IS NULL
    ))
), obras_filtradas AS (
  SELECT * FROM obras_visiveis
  WHERE @obra::int IS NULL OR id = @obra
), saldos AS (
  SELECT e.obra_id, e.produto_id, e.quantidade
  FROM estoque e
  JOIN obras_filtradas o ON o.id = e.obra_id
  JOIN produto p ON p.id = e.produto_id AND p.empresa_id = @empresa
), precos AS (
  SELECT DISTINCT ON (ee.obra_id, ie.produto_id)
    ee.obra_id, ie.produto_id, ie.valor_unitario
  FROM item_entrada ie
  JOIN entrada_estoque ee ON ee.id = ie.entrada_id
  JOIN obras_filtradas o ON o.id = ee.obra_id
  JOIN produto p ON p.id = ie.produto_id AND p.empresa_id = @empresa
  JOIN usuario u ON u.id = ee.usuario_id AND u.empresa_id = @empresa
  WHERE @gestor AND ie.valor_unitario IS NOT NULL
  ORDER BY ee.obra_id, ie.produto_id, ee.data DESC, ie.id DESC
), valoracao AS (
  SELECT
    SUM(s.quantidade * p.valor_unitario) FILTER (
      WHERE s.quantidade > 0 AND p.valor_unitario IS NOT NULL
    ) AS valor,
    COUNT(*) FILTER (
      WHERE s.quantidade > 0 AND p.valor_unitario IS NULL
    ) AS sem_preco
  FROM saldos s
  LEFT JOIN precos p ON p.obra_id = s.obra_id
    AND p.produto_id = s.produto_id
), recentes AS (
  SELECT ie.id AS ordem_id, 'ENT-' || ie.id AS id, p.nome AS produto_nome,
    p.unidade, o.nome AS obra_nome, 'entrada' AS acao,
    ie.quantidade::text AS quantidade, ee.data
  FROM item_entrada ie
  JOIN entrada_estoque ee ON ee.id = ie.entrada_id
  JOIN obras_filtradas o ON o.id = ee.obra_id
  JOIN produto p ON p.id = ie.produto_id AND p.empresa_id = @empresa
  JOIN usuario u ON u.id = ee.usuario_id AND u.empresa_id = @empresa
  ORDER BY ee.data DESC, ie.id DESC
  LIMIT @limite OFFSET @offset
)
SELECT jsonb_build_object(
  'obra_permitida', @obra::int IS NULL OR EXISTS (
    SELECT 1 FROM obras_visiveis WHERE id = @obra
  ),
  'obras', COALESCE((
    SELECT jsonb_agg(to_jsonb(o) ORDER BY o.nome, o.id)
    FROM obras_visiveis o
  ), '[]'::jsonb),
  'obra_id', @obra::int,
  'atualizado_em', CURRENT_TIMESTAMP,
  'indicadores', jsonb_build_object(
    'total_itens', (SELECT COUNT(DISTINCT produto_id) FROM saldos),
    'rupturas_criticas', (SELECT COUNT(*) FROM saldos WHERE quantidade = 0),
    'requisicoes_pendentes', (
      SELECT COUNT(*) FROM pedido p
      JOIN obras_filtradas o ON o.id = p.obra_id
      JOIN usuario u ON u.id = p.usuario_id AND u.empresa_id = @empresa
      WHERE LOWER(p.status) = 'pendente'
        AND (@gestor OR p.usuario_id = @usuario)
    ),
    'obras_ativas', (SELECT COUNT(*) FROM obras_filtradas WHERE status = 'ativa')
  ) || CASE WHEN @gestor THEN jsonb_build_object(
    'valor_estimado', (SELECT ROUND(valor, 2)::text FROM valoracao),
    'itens_sem_preco', (SELECT sem_preco FROM valoracao)
  ) ELSE '{}'::jsonb END,
  'movimentacoes', COALESCE((
    SELECT jsonb_agg(to_jsonb(r) - 'ordem_id' ORDER BY r.data DESC, r.ordem_id DESC)
    FROM recentes r
  ), '[]'::jsonb)
) AS dados
''';
