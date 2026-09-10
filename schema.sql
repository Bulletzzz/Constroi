-- primeiro esquema do banco segundo o diagrama

CREATE TABLE empresa (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    cnpj VARCHAR(18) NOT NULL
);

CREATE TABLE obra (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresa(id),
    nome VARCHAR(150) NOT NULL,
    endereco VARCHAR(255) NOT NULL,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE produto (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresa(id),
    nome VARCHAR(150) NOT NULL,
    unidade VARCHAR(30) NOT NULL
);

CREATE TABLE usuario (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresa(id),
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    tipo VARCHAR(30) NOT NULL
);

CREATE TABLE equipamento (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresa(id),
    nome VARCHAR(150) NOT NULL,
    patrimonio VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE estoque (
    id SERIAL PRIMARY KEY,
    obra_id INTEGER NOT NULL REFERENCES obra(id),
    produto_id INTEGER NOT NULL REFERENCES produto(id),
    quantidade DECIMAL(10, 2) NOT NULL
);

CREATE TABLE pedido (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id),
    obra_id INTEGER NOT NULL REFERENCES obra(id),
    protocolo VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    justificativa VARCHAR(255),
    data TIMESTAMP NOT NULL
);

CREATE TABLE item_pedido (
    id SERIAL PRIMARY KEY,
    pedido_id INTEGER NOT NULL REFERENCES pedido(id),
    produto_id INTEGER NOT NULL REFERENCES produto(id),
    quantidade DECIMAL(10, 2) NOT NULL
);

CREATE TABLE entrada_estoque (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id),
    obra_id INTEGER NOT NULL REFERENCES obra(id),
    xml_nota_fiscal TEXT,
    justificativa VARCHAR(255),
    data TIMESTAMP NOT NULL
);

CREATE TABLE item_entrada (
    id SERIAL PRIMARY KEY,
    entrada_id INTEGER NOT NULL REFERENCES entrada_estoque(id),
    produto_id INTEGER NOT NULL REFERENCES produto(id),
    quantidade DECIMAL(10, 2) NOT NULL
);

CREATE TABLE emprestimo (
    id SERIAL PRIMARY KEY,
    equipamento_id INTEGER NOT NULL REFERENCES equipamento(id),
    usuario_id INTEGER NOT NULL REFERENCES usuario(id),
    obra_id INTEGER NOT NULL REFERENCES obra(id),
    data_emprestimo TIMESTAMP NOT NULL,
    data_devolucao TIMESTAMP,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE log_sistema (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id),
    acao VARCHAR(255) NOT NULL,
    data TIMESTAMP NOT NULL
);
