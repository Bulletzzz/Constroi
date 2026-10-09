// Run from constroi_api. Optional SQL test dependency stays inside ignored .dart_tool:
// npm install --prefix .dart_tool/sql-validation --no-save @electric-sql/pglite@0.5.8
// node test/sql/estoque_contract.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../.dart_tool/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
try {
  const schema = await readFile('../Database/schema.sql', 'utf8');
  // PGlite lacks pgcrypto here; gen_random_uuid is available in core PostgreSQL.
  await db.exec(schema.replace('CREATE EXTENSION IF NOT EXISTS pgcrypto;', ''));
  const source = await readFile('routes/estoque/index.dart', 'utf8');
  const queries = [...source.matchAll(/Sql.named\('''([\s\S]*?)'''\)/g)].map(m => m[1]);
  assert.equal(queries.length, 2);
  async function query(index, params) {
    const names = [];
    const sql = queries[index].replace(/@(\w+)/g, (_, name) => {
      if (!names.includes(name)) names.push(name);
      return '$' + (names.indexOf(name) + 1);
    });
    return (await db.query(sql, names.map(n => params[n]))).rows;
  }

  await db.exec(`
    INSERT INTO empresa (id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
    INSERT INTO usuario (id,empresa_id,nome,email,senha_hash,tipo) VALUES
      (1,1,'Ped','ped@a','hash','pedreiro'),(2,1,'Sem vinculo','outro@a','hash','pedreiro');
    INSERT INTO obra (id,empresa_id,nome,endereco,status) VALUES
      (1,1,'Obra A','Rua','ativa'),(2,1,'Obra B','Rua','ativa'),
      (3,2,'Alheia','Rua','ativa'),(4,1,'Vazia','Rua','ativa');
    INSERT INTO usuario_obra (empresa_id,usuario_id,obra_id) VALUES
      (1,1,1),(1,1,2);
    UPDATE usuario_obra SET data_fim=CURRENT_TIMESTAMP WHERE obra_id=2;
    INSERT INTO produto (id,empresa_id,nome,unidade,sku,estoque_minimo,categoria_custo_id) VALUES
      (1,1,'Cimento','saco','CIM-01',5,2),
      (2,1,'Areia','kg','AR-01',2,2),
      (3,1,'Cal','saco',NULL,0,NULL),
      (4,2,'Alheio','kg','B-01',5,1),
      (5,1,'Literal %_','un','LIT',0,1),
      (6,1,'Sem saldo','un','SEM',1,2);
    INSERT INTO estoque (obra_id,produto_id,quantidade) VALUES
      (1,1,5),(1,2,3),(1,3,0),(1,5,1),(2,1,6),(3,4,4),(1,4,1);
  `);
  const pedreiro = {
    empresa:1, usuario:1, todas:false, obra:null, categoria:null,
    busca:'', baixo:false, limite:50, offset:0,
  };
  const gestor = {...pedreiro, todas:true};

  // Contract is asserted on real SQL results, rather than pre-shaped mock rows.
  const cimento = (await query(1,{...pedreiro,busca:'cim-01'}))[0];
  assert.deepEqual(cimento, {
    id:1, obra_id:1, produto_id:1, produto_nome:'Cimento', unidade:'saco',
    sku:'CIM-01', categoria_custo_id:2, categoria_nome:'Cimento e agregados',
    quantidade:'5.00', estoque_minimo:'5.00', baixo:true,
  });
  assert.equal(Object.hasOwn(cimento,'nome'),false);
  const semCategoria = (await query(1,{...pedreiro,busca:'Cal'}))[0];
  assert.equal(semCategoria.produto_nome,'Cal');
  assert.equal(semCategoria.categoria_custo_id,null);
  assert.equal(semCategoria.categoria_nome,null);

  assert.deepEqual((await query(1,pedreiro)).map(x=>x.produto_id),[2,3,1,5]);
  assert.deepEqual((await query(1,{...pedreiro,categoria:2})).map(x=>x.produto_id),[2,1]);
  assert.deepEqual((await query(1,{...pedreiro,categoria:1})).map(x=>x.produto_id),[5]);
  assert.equal((await query(1,{...pedreiro,categoria:2147483647})).length,0);
  assert.deepEqual((await query(1,{...pedreiro,categoria:2,baixo:true})).map(x=>x.produto_id),[1]);
  assert.equal((await query(1,{...pedreiro,categoria:1,busca:'Cimento'})).length,0);
  assert.equal((await query(1,{...pedreiro,busca:'%_'}))[0].produto_id,5);
  assert.equal((await query(1,{...pedreiro,busca:"' OR 1=1 --"})).length,0);

  // No obra_id aggregates only visible works, even after a membership ends.
  assert.deepEqual((await query(1,gestor)).map(x=>[x.produto_id,x.obra_id]),
    [[2,1],[3,1],[1,1],[1,2],[5,1]]);
  assert.equal((await query(1,{...pedreiro,usuario:2})).length,0);
  assert.equal((await query(1,{...pedreiro,obra:2})).length,0);
  assert.equal((await query(1,{...gestor,obra:3})).length,0);
  assert.equal((await query(1,{...gestor,obra:4})).length,0);
  assert.equal((await query(1,{...gestor,empresa:2})).length,1);
  const page = await query(1,{...gestor,limite:1,offset:3});
  assert.deepEqual(page.map(x=>[x.produto_id,x.obra_id]),[[1,2]]);

  // Explicit works retain 404 authorization behavior via the access query.
  for (const obra of [2,3,999]) {
    assert.equal((await query(0,{...pedreiro,obra})).length,0);
  }
  assert.equal((await query(0,{...pedreiro,obra:1})).length,1);
  assert.equal((await query(0,{...gestor,obra:2})).length,1);
  assert.equal((await query(0,{...gestor,obra:3})).length,0);
  console.log('Stock SQL contract OK: names, categories, filters, optional works, authorization and pagination.');
} finally {
  await db.close();
}
