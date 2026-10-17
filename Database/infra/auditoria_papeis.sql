-- Operacao manual coordenada. Executar conectado como dono das migrations,
-- somente depois de validar em um banco descartavel. PostgreSQL 17+.
-- Nao define nem troca senhas; usar \password ou o cofre do ambiente.
BEGIN;
DO $$
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'Exige PostgreSQL 17 ou superior';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='constroi_api_execucao') THEN
    CREATE ROLE constroi_api_execucao LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
      NOINHERIT NOREPLICATION NOBYPASSRLS;
  END IF;
  IF current_user='constroi_api_execucao' OR EXISTS (
    SELECT FROM pg_roles WHERE rolname='constroi_api_execucao'
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
  ) OR pg_has_role('constroi_api_execucao',current_user,'MEMBER') THEN
    RAISE EXCEPTION 'Papel de execucao nao pode administrar nem assumir migrations';
  END IF;
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO constroi_api_execucao',current_database());
  EXECUTE format('REVOKE CREATE ON DATABASE %I FROM PUBLIC',current_database());
  EXECUTE format('ALTER ROLE constroi_api_execucao IN DATABASE %I SET transaction_timeout=''30s''',current_database());
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO constroi_api_execucao;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO constroi_api_execucao;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO constroi_api_execucao;

-- Tabelas futuras recebem so leitura/insercao, inclusive a auditoria ainda
-- nao criada. Reexecutar este script apos migrations para liberar CRUD normal.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT,INSERT ON TABLES TO constroi_api_execucao;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE,SELECT ON SEQUENCES TO constroi_api_execucao;

DO $$
BEGIN
  IF to_regclass('public.schema_migrations') IS NOT NULL THEN
    REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON schema_migrations FROM constroi_api_execucao;
    REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON schema_migrations FROM PUBLIC;
  END IF;
  IF to_regclass('public.movimentacao_estoque') IS NOT NULL THEN
    REVOKE UPDATE,DELETE,TRUNCATE,TRIGGER ON movimentacao_estoque FROM constroi_api_execucao;
    REVOKE UPDATE,DELETE,TRUNCATE,TRIGGER ON movimentacao_estoque FROM PUBLIC;
  END IF;
END $$;
COMMIT;
