# Banco e diagrama

`schema.sql` representa o estado consolidado do banco. Bancos existentes devem
ser atualizados pelas migrations em `constroi_api/migrations`.

A migration `014_log_empresa.sql` preenche a empresa dos logs existentes pelo
usuário e adiciona a FK composta e os índices de consulta por empresa/período
e por empresa/usuário/período. Nos dois índices, `data` e `id` usam ordem DESC;
`schema.sql` contém a definição completa dessa ordenação.

Para regenerar o SVG e o PNG do diagrama:

```powershell
cd Database
npm install
npm run diagram
```

O comando termina com erro se o PNG não puder ser criado, evitando que a imagem
commitada fique desatualizada sem aviso.
