# Banco e diagrama

`schema.sql` representa o estado consolidado do banco. Bancos existentes devem
ser atualizados pelas migrations em `constroi_api/migrations`.

A migration `014_log_empresa.sql` preenche a empresa dos logs existentes pelo
usuário e adiciona a FK composta e os índices de consulta por empresa/período
e por empresa/usuário/período. Nos dois índices, `data` e `id` usam ordem DESC;
`schema.sql` contém a definição completa dessa ordenação.
A 014 permite reaplicação, preservando os registros e recriando índices ausentes.

A migration `015_emprestimos.sql` adiciona `empresa_id` e `data_prevista` ao
empréstimo e cria a chave única `(id, empresa_id)` em equipamento. As FKs
compostas validam equipamento, responsável e obra na mesma empresa. O índice
parcial permite somente um empréstimo `aberto` por equipamento.

Empréstimos legados precisam ter `data_prevista` preenchida com o prazo real
antes da aplicação da 015. A migration deriva a empresa do equipamento e
interrompe a operação inteira se encontrar prazo ausente, empresa cruzada,
datas/status inválidos ou dois empréstimos abertos para o mesmo equipamento.
Ela preserva os registros e não escolhe prazos ou vencedores automaticamente.
Empréstimos abertos válidos deixam o equipamento em `em_uso`.

Para regenerar o SVG e o PNG do diagrama:

```powershell
cd Database
npm install
npm run diagram
```

O comando termina com erro se o PNG não puder ser criado, evitando que a imagem
commitada fique desatualizada sem aviso.
