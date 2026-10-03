# Banco e diagrama

`schema.sql` representa o estado consolidado do banco. Bancos existentes devem
ser atualizados pelas migrations em `constroi_api/migrations`.

Para regenerar o SVG e o PNG do diagrama:

```powershell
cd Database
npm install
npm run diagram
```

O comando termina com erro se o PNG não puder ser criado, evitando que a imagem
commitada fique desatualizada sem aviso.
