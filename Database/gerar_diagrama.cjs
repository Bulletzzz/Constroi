const fs = require('fs');
const path = require('path');

const width = 2400;
const height = 1710;
const boxWidth = 380;
const boxHeight = 250;
const columns = [60, 530, 1000, 1470, 1940];
const rows = [80, 480, 880, 1280];

const tables = [
  ['sessao_usuario', 0, 0, 'auth', ['id PK', 'usuario_id FK', 'refresh_token_hash', 'expira_em', 'revogado_em']],
  ['recuperacao_senha', 1, 0, 'auth', ['id PK', 'usuario_id FK', 'token_hash', 'expira_em', 'utilizado_em']],
  ['empresa', 2, 0, 'base', ['id PK', 'nome', 'cnpj UQ']],
  ['tentativa_login', 3, 0, 'auth', ['id PK', 'usuario_id FK', 'email_hash', 'sucesso', 'criado_em']],
  ['log_sistema', 4, 0, 'base', ['id PK', 'usuario_id FK', 'acao', 'data']],
  ['equipamento', 0, 1, 'base', ['id PK', 'empresa_id FK', 'nome', 'patrimonio', 'status']],
  ['usuario', 1, 1, 'base', ['id PK', 'empresa_id FK', 'nome', 'email', 'tipo / ativo']],
  ['usuario_obra', 2, 1, 'team', ['id PK', 'empresa_id', 'usuario_id FK', 'obra_id FK', 'data_inicio / data_fim']],
  ['obra', 3, 1, 'cost', ['id PK', 'empresa_id FK', 'nome', 'status', 'orcamento_total']],
  ['emprestimo', 4, 1, 'base', ['id PK', 'equipamento_id FK', 'usuario_id FK', 'obra_id FK', 'datas / status']],
  ['categoria_custo', 0, 2, 'cost', ['id PK', 'nome UQ']],
  ['produto', 1, 2, 'cost', ['id PK', 'empresa_id FK', 'categoria_custo_id FK', 'nome', 'unidade']],
  ['estoque', 2, 2, 'base', ['id PK', 'obra_id FK', 'produto_id FK', 'quantidade']],
  ['pedido', 3, 2, 'base', ['id PK', 'usuario_id FK', 'obra_id FK', 'protocolo', 'status / data']],
  ['item_pedido', 4, 2, 'base', ['id PK', 'pedido_id FK', 'produto_id FK', 'quantidade']],
  ['despesa_obra', 0, 3, 'cost', ['id PK', 'obra_id FK', 'usuario_id FK', 'categoria_custo_id FK', 'descricao / valor']],
  ['item_entrada', 1, 3, 'cost', ['id PK', 'entrada_id FK', 'produto_id FK', 'categoria_custo_id FK', 'quantidade / valor_unitario']],
  ['entrada_estoque', 2, 3, 'base', ['id PK', 'usuario_id FK', 'obra_id FK', 'xml_nota_fiscal', 'data']],
  ['vw_resumo_custo_obra', 3, 3, 'view', ['VIEW', 'obra_id', 'custo_acumulado', 'saldo_orcamento', 'percentual_consumido']],
  ['vw_lancamento_custo', 4, 3, 'view', ['VIEW', 'origem / origem_id', 'obra_id', 'categoria_custo_id', 'valor']],
];

const links = [
  ['empresa', 'usuario'], ['empresa', 'obra'], ['empresa', 'produto'], ['empresa', 'equipamento'],
  ['usuario', 'sessao_usuario'], ['usuario', 'recuperacao_senha'], ['usuario', 'tentativa_login'], ['usuario', 'log_sistema'],
  ['usuario', 'usuario_obra'], ['obra', 'usuario_obra'], ['equipamento', 'emprestimo'], ['usuario', 'emprestimo'], ['obra', 'emprestimo'],
  ['categoria_custo', 'produto'], ['categoria_custo', 'item_entrada'], ['categoria_custo', 'despesa_obra'],
  ['obra', 'estoque'], ['produto', 'estoque'], ['usuario', 'pedido'], ['obra', 'pedido'], ['pedido', 'item_pedido'], ['produto', 'item_pedido'],
  ['usuario', 'entrada_estoque'], ['obra', 'entrada_estoque'], ['entrada_estoque', 'item_entrada'], ['produto', 'item_entrada'],
  ['obra', 'despesa_obra'], ['usuario', 'despesa_obra'], ['obra', 'vw_resumo_custo_obra'], ['item_entrada', 'vw_lancamento_custo'],
  ['despesa_obra', 'vw_lancamento_custo'], ['vw_lancamento_custo', 'vw_resumo_custo_obra'],
];

const palette = {
  base: ['#2f343a', '#f4f6f8'],
  auth: ['#563d7c', '#f4f6f8'],
  team: ['#1976a3', '#ffffff'],
  cost: ['#d99a00', '#171717'],
  view: ['#247c55', '#ffffff'],
};

const byName = Object.fromEntries(tables.map((table) => [table[0], table]));
const esc = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const center = (table) => [columns[table[1]] + boxWidth / 2, rows[table[2]] + boxHeight / 2];

const linkSvg = links.map(([from, to]) => {
  const [x1, y1] = center(byName[from]);
  const [x2, y2] = center(byName[to]);
  const midY = Math.round((y1 + y2) / 2);
  return `<path d="M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}" />`;
}).join('\n');

const tableSvg = tables.map(([name, col, row, group, fields]) => {
  const x = columns[col];
  const y = rows[row];
  const [header, headerText] = palette[group];
  const rowsSvg = fields.map((field, index) =>
    `<text x="${x + 20}" y="${y + 92 + index * 29}" class="field">${esc(field)}</text>`,
  ).join('\n');
  return `<g>
    <rect x="${x}" y="${y}" width="${boxWidth}" height="${boxHeight}" rx="12" class="table" />
    <path d="M ${x + 12} ${y} H ${x + boxWidth - 12} Q ${x + boxWidth} ${y} ${x + boxWidth} ${y + 12} V ${y + 58} H ${x} V ${y + 12} Q ${x} ${y} ${x + 12} ${y}" fill="${header}" />
    <text x="${x + 20}" y="${y + 39}" class="title" fill="${headerText}">${esc(name)}</text>
    ${rowsSvg}
  </g>`;
}).join('\n');

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#111416" />
  <style>
    .table { fill: #202429; stroke: #697078; stroke-width: 2; }
    .title { font: 700 23px Arial, sans-serif; }
    .field { fill: #e8eaed; font: 18px Consolas, monospace; }
    .links path { fill: none; stroke: #89929c; stroke-width: 2; opacity: .42; }
    .heading { fill: #ffffff; font: 700 34px Arial, sans-serif; }
    .subtitle { fill: #aeb6bf; font: 19px Arial, sans-serif; }
  </style>
  <text x="60" y="48" class="heading">CONSTRÓI — Modelo de dados</text>
  <text x="810" y="46" class="subtitle">azul: equipe • amarelo: custos • roxo: autenticação • verde: views</text>
  <g class="links">${linkSvg}</g>
  ${tableSvg}
</svg>`;

const docsDir = path.resolve(__dirname, '..', 'Documentação');
const svgPath = path.join(docsDir, 'Diagrama_Banco.svg');
const pngPath = path.join(docsDir, 'Diagrama_Banco.png');
fs.writeFileSync(svgPath, svg, 'utf8');

const sharp = require('sharp');
sharp(Buffer.from(svg)).png().toFile(pngPath)
  .then(() => console.log(`Diagramas gerados em ${svgPath} e ${pngPath}`))
  .catch((error) => {
    console.error(`Falha ao gerar o PNG: ${error.message}`);
    process.exitCode = 1;
  });
