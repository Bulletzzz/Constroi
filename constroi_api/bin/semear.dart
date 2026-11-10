import 'dart:io';

import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/senha.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

const cnpjDaEmpresa = '00.000.000/0001-00';
const senhaDosNovos = 'Senha#Forte123';
const prefixoDoProtocolo = 'PED-5EED';

typedef Pessoa = ({
  String chave,
  String nome,
  String email,
  String tipo,
  bool ativo,
});
typedef Canteiro = ({
  String chave,
  String nome,
  String endereco,
  String status,
  int orcamento,
});
typedef Material = ({
  String sku,
  String nome,
  String unidade,
  int minimo,
  int categoria,
});
typedef Ferramenta = ({String patrimonio, String nome, String status});
typedef ItemComprado = ({String sku, int quantidade, int preco});
typedef Compra = ({
  String obra,
  int dias,
  String usuario,
  String nota,
  List<ItemComprado> itens,
});
typedef ItemPedido = ({String sku, int quantidade});
typedef Requisicao = ({
  String obra,
  int dias,
  String usuario,
  String urgencia,
  String? local,
  String status,
  String? decisor,
  String? motivo,
  String nota,
  List<ItemPedido> itens,
});
typedef Gasto = ({
  String obra,
  int dias,
  String usuario,
  int categoria,
  String descricao,
  int valor,
});
typedef Retirada = ({
  String patrimonio,
  String usuario,
  String obra,
  int dias,
  int diasPrevistos,
  int? diasDevolvido,
});

const pessoasNovas = <Pessoa>[
  (
    chave: 'carlos',
    nome: 'Carlos Lima',
    email: 'carlos@constroi.test',
    tipo: 'pedreiro',
    ativo: true,
  ),
  (
    chave: 'marcos',
    nome: 'Marcos Dias',
    email: 'marcos@constroi.test',
    tipo: 'pedreiro',
    ativo: true,
  ),
  (
    chave: 'rita',
    nome: 'Rita Alves',
    email: 'rita@constroi.test',
    tipo: 'engenheiro',
    ativo: true,
  ),
  (
    chave: 'fernanda',
    nome: 'Fernanda Souza',
    email: 'fernanda@constroi.test',
    tipo: 'pedreiro',
    ativo: false,
  ),
];

const emailsExistentes = <String, String>{
  'eduardo': 'eduardo@constroi.test',
  'joao': 'pedreiro@constroi.test',
  'ana': 'master@constroi.test',
};

const emailsOpcionais = <String, String>{
  'pedro': 'pedro@teste.com',
  'bisteca': 'bisteca@teste.com',
};

const canteiros = <Canteiro>[
  (
    chave: 'vista',
    nome: 'Residencial Vista Verde',
    endereco: 'Rua das Acacias, 450',
    status: 'ativa',
    orcamento: 25000000,
  ),
  (
    chave: 'aurora',
    nome: 'Edificio Aurora',
    endereco: 'Avenida Brasil, 1200',
    status: 'ativa',
    orcamento: 40000000,
  ),
  (
    chave: 'galpao',
    nome: 'Galpao Industrial Norte',
    endereco: 'Rodovia BR-277, km 18',
    status: 'ativa',
    orcamento: 5200000,
  ),
  (
    chave: 'escola',
    nome: 'Reforma Escola Central',
    endereco: 'Rua XV de Novembro, 88',
    status: 'concluida',
    orcamento: 1800000,
  ),
];

const materiais = <Material>[
  (
    sku: 'CIM-50',
    nome: 'Cimento CP-II 50kg',
    unidade: 'saco',
    minimo: 40,
    categoria: 2,
  ),
  (
    sku: 'CAL-20',
    nome: 'Cal hidratada 20kg',
    unidade: 'saco',
    minimo: 30,
    categoria: 2,
  ),
  (
    sku: 'ARG-AC',
    nome: 'Argamassa AC-II 20kg',
    unidade: 'saco',
    minimo: 50,
    categoria: 2,
  ),
  (sku: 'ARE-MD', nome: 'Areia media', unidade: 'm3', minimo: 10, categoria: 2),
  (sku: 'BRT-01', nome: 'Brita 1', unidade: 'm3', minimo: 12, categoria: 2),
  (
    sku: 'BLO-14',
    nome: 'Bloco ceramico 14x19x39',
    unidade: 'un',
    minimo: 500,
    categoria: 2,
  ),
  (
    sku: 'VRG-08',
    nome: 'Vergalhao CA-60 8mm',
    unidade: 'barra',
    minimo: 80,
    categoria: 1,
  ),
  (
    sku: 'VRG-10',
    nome: 'Vergalhao CA-50 10mm',
    unidade: 'barra',
    minimo: 60,
    categoria: 1,
  ),
  (
    sku: 'VRG-12',
    nome: 'Vergalhao CA-50 12,5mm',
    unidade: 'barra',
    minimo: 40,
    categoria: 1,
  ),
  (
    sku: 'ARA-18',
    nome: 'Arame recozido 18',
    unidade: 'kg',
    minimo: 25,
    categoria: 1,
  ),
  (
    sku: 'TAB-PI',
    nome: 'Tabua de pinus 30cm',
    unidade: 'm',
    minimo: 60,
    categoria: 4,
  ),
  (
    sku: 'CMP-18',
    nome: 'Compensado plastificado 18mm',
    unidade: 'pc',
    minimo: 15,
    categoria: 4,
  ),
  (
    sku: 'ESC-ME',
    nome: 'Escora metalica 3m',
    unidade: 'pc',
    minimo: 30,
    categoria: 3,
  ),
  (
    sku: 'EPI-LUV',
    nome: 'Luva de raspa',
    unidade: 'pc',
    minimo: 20,
    categoria: 5,
  ),
  (
    sku: 'EPI-CAP',
    nome: 'Capacete de seguranca',
    unidade: 'pc',
    minimo: 15,
    categoria: 5,
  ),
  (
    sku: 'EPI-BOT',
    nome: 'Bota de seguranca',
    unidade: 'pc',
    minimo: 10,
    categoria: 5,
  ),
  (
    sku: 'LON-PL',
    nome: 'Lona plastica 6x100m',
    unidade: 'rolo',
    minimo: 4,
    categoria: 5,
  ),
  (
    sku: 'FIO-25',
    nome: 'Cabo flexivel 2,5mm',
    unidade: 'rolo',
    minimo: 6,
    categoria: 5,
  ),
];

const ferramentas = <Ferramenta>[
  (patrimonio: 'BET-001', nome: 'Betoneira 400L', status: 'disponivel'),
  (patrimonio: 'BET-002', nome: 'Betoneira 150L', status: 'disponivel'),
  (patrimonio: 'MAR-001', nome: 'Martelete rompedor', status: 'disponivel'),
  (
    patrimonio: 'SER-001',
    nome: 'Serra circular de bancada',
    status: 'disponivel',
  ),
  (patrimonio: 'VIB-001', nome: 'Vibrador de imersao', status: 'manutencao'),
  (patrimonio: 'COM-001', nome: 'Compactador de solo', status: 'disponivel'),
  (
    patrimonio: 'AND-001',
    nome: 'Andaime fachadeiro 10m2',
    status: 'disponivel',
  ),
  (patrimonio: 'NIV-001', nome: 'Nivel a laser', status: 'disponivel'),
  (patrimonio: 'GER-001', nome: 'Gerador 5kVA', status: 'quebrado'),
];

const equipes = <({String usuario, String obra, int dias, int? diasFim})>[
  (usuario: 'joao', obra: 'vista', dias: 70, diasFim: null),
  (usuario: 'carlos', obra: 'vista', dias: 64, diasFim: null),
  (usuario: 'eduardo', obra: 'vista', dias: 70, diasFim: null),
  (usuario: 'rita', obra: 'vista', dias: 40, diasFim: null),
  (usuario: 'ana', obra: 'vista', dias: 70, diasFim: null),
  (usuario: 'marcos', obra: 'aurora', dias: 58, diasFim: null),
  (usuario: 'carlos', obra: 'aurora', dias: 30, diasFim: null),
  (usuario: 'eduardo', obra: 'aurora', dias: 58, diasFim: null),
  (usuario: 'joao', obra: 'galpao', dias: 45, diasFim: null),
  (usuario: 'rita', obra: 'galpao', dias: 45, diasFim: null),
  (usuario: 'marcos', obra: 'escola', dias: 68, diasFim: 22),
  (usuario: 'eduardo', obra: 'escola', dias: 68, diasFim: 22),
  (usuario: 'fernanda', obra: 'vista', dias: 60, diasFim: 18),
];

const compras = <Compra>[
  (
    obra: 'escola',
    dias: 66,
    usuario: 'eduardo',
    nota: 'NF 40012 - Deposito Sao Jorge',
    itens: [
      (sku: 'CIM-50', quantidade: 12000, preco: 3850),
      (sku: 'ARG-AC', quantidade: 9000, preco: 2400),
      (sku: 'EPI-LUV', quantidade: 6000, preco: 1250),
    ],
  ),
  (
    obra: 'vista',
    dias: 62,
    usuario: 'eduardo',
    nota: 'NF 10432 - Deposito Sao Jorge',
    itens: [
      (sku: 'CIM-50', quantidade: 30000, preco: 3850),
      (sku: 'ARE-MD', quantidade: 4000, preco: 9500),
      (sku: 'BRT-01', quantidade: 3000, preco: 11000),
      (sku: 'BLO-14', quantidade: 800000, preco: 235),
    ],
  ),
  (
    obra: 'aurora',
    dias: 55,
    usuario: 'eduardo',
    nota: 'NF 20110 - Deposito Sao Jorge',
    itens: [
      (sku: 'CIM-50', quantidade: 50000, preco: 3790),
      (sku: 'ARE-MD', quantidade: 6000, preco: 9500),
      (sku: 'BLO-14', quantidade: 1200000, preco: 228),
    ],
  ),
  (
    obra: 'vista',
    dias: 48,
    usuario: 'eduardo',
    nota: 'NF 10598 - Aco Forte Distribuidora',
    itens: [
      (sku: 'VRG-08', quantidade: 40000, preco: 2870),
      (sku: 'VRG-10', quantidade: 32000, preco: 4490),
      (sku: 'VRG-12', quantidade: 18000, preco: 6250),
      (sku: 'ARA-18', quantidade: 12000, preco: 1480),
    ],
  ),
  (
    obra: 'galpao',
    dias: 44,
    usuario: 'rita',
    nota: 'NF 30077 - Deposito Sao Jorge',
    itens: [
      (sku: 'CIM-50', quantidade: 18000, preco: 3920),
      (sku: 'BRT-01', quantidade: 8000, preco: 11000),
      (sku: 'ARE-MD', quantidade: 5000, preco: 9500),
    ],
  ),
  (
    obra: 'aurora',
    dias: 40,
    usuario: 'eduardo',
    nota: 'NF 20245 - Aco Forte Distribuidora',
    itens: [
      (sku: 'VRG-10', quantidade: 50000, preco: 4420),
      (sku: 'VRG-12', quantidade: 30000, preco: 6190),
    ],
  ),
  (
    obra: 'vista',
    dias: 35,
    usuario: 'eduardo',
    nota: 'NF 10711 - Casa do Construtor',
    itens: [
      (sku: 'EPI-LUV', quantidade: 12000, preco: 1250),
      (sku: 'EPI-CAP', quantidade: 4000, preco: 3400),
      (sku: 'EPI-BOT', quantidade: 3000, preco: 8990),
      (sku: 'LON-PL', quantidade: 1000, preco: 21500),
    ],
  ),
  (
    obra: 'galpao',
    dias: 30,
    usuario: 'rita',
    nota: 'NF 30155 - Aco Forte Distribuidora',
    itens: [
      (sku: 'VRG-12', quantidade: 22000, preco: 6250),
      (sku: 'ARA-18', quantidade: 9000, preco: 1480),
    ],
  ),
  (
    obra: 'aurora',
    dias: 26,
    usuario: 'eduardo',
    nota: 'NF 20388 - Madeireira Pinho Real',
    itens: [
      (sku: 'CMP-18', quantidade: 8000, preco: 14800),
      (sku: 'TAB-PI', quantidade: 60000, preco: 2140),
      (sku: 'ESC-ME', quantidade: 12000, preco: 8900),
    ],
  ),
  (
    obra: 'vista',
    dias: 21,
    usuario: 'rita',
    nota: 'NF 10890 - Deposito Sao Jorge',
    itens: [
      (sku: 'CIM-50', quantidade: 20000, preco: 3990),
      (sku: 'ARG-AC', quantidade: 15000, preco: 2400),
      (sku: 'CAL-20', quantidade: 8000, preco: 1890),
    ],
  ),
  (
    obra: 'aurora',
    dias: 12,
    usuario: 'eduardo',
    nota: 'NF 20501 - Casa do Construtor',
    itens: [
      (sku: 'EPI-CAP', quantidade: 6000, preco: 3400),
      (sku: 'EPI-BOT', quantidade: 4500, preco: 8990),
      (sku: 'FIO-25', quantidade: 2000, preco: 18900),
      (sku: 'ARG-AC', quantidade: 20000, preco: 2350),
    ],
  ),
  (
    obra: 'vista',
    dias: 9,
    usuario: 'rita',
    nota: 'NF 11024 - Madeireira Pinho Real',
    itens: [
      (sku: 'TAB-PI', quantidade: 40000, preco: 2140),
      (sku: 'ESC-ME', quantidade: 6000, preco: 8900),
    ],
  ),
  (
    obra: 'galpao',
    dias: 6,
    usuario: 'rita',
    nota: 'NF 30290 - Casa do Construtor',
    itens: [
      (sku: 'LON-PL', quantidade: 1400, preco: 21500),
      (sku: 'FIO-25', quantidade: 1200, preco: 18900),
      (sku: 'EPI-BOT', quantidade: 2000, preco: 8990),
    ],
  ),
];

const requisicoes = <Requisicao>[
  (
    obra: 'escola',
    dias: 60,
    usuario: 'marcos',
    urgencia: 'padrao',
    local: 'Bloco de salas',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Alvenaria das salas 4 a 8',
    itens: [
      (sku: 'CIM-50', quantidade: 10000),
      (sku: 'ARG-AC', quantidade: 7000),
      (sku: 'EPI-LUV', quantidade: 5000),
    ],
  ),
  (
    obra: 'vista',
    dias: 58,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Torre A - 3o pavimento',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Concretagem marcada para amanha de manha',
    itens: [
      (sku: 'CIM-50', quantidade: 4000),
      (sku: 'ARE-MD', quantidade: 600),
    ],
  ),
  (
    obra: 'vista',
    dias: 52,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Torre A - 2o pavimento',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Alvenaria externa',
    itens: [
      (sku: 'BLO-14', quantidade: 120000),
      (sku: 'ARE-MD', quantidade: 400),
    ],
  ),
  (
    obra: 'aurora',
    dias: 50,
    usuario: 'marcos',
    urgencia: 'padrao',
    local: 'Bloco 1 - subsolo',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Contrapiso do subsolo',
    itens: [
      (sku: 'CIM-50', quantidade: 9000),
      (sku: 'ARE-MD', quantidade: 1000),
    ],
  ),
  (
    obra: 'vista',
    dias: 44,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Torre B - fundacao',
    status: 'recusado',
    decisor: 'eduardo',
    motivo: 'Quantidade acima do previsto para a etapa. Refaca com 10 sacos.',
    nota: 'Sapatas da Torre B',
    itens: [(sku: 'CIM-50', quantidade: 25000)],
  ),
  (
    obra: 'aurora',
    dias: 42,
    usuario: 'marcos',
    urgencia: 'urgente',
    local: 'Bloco 1 - terreo',
    status: 'recusado',
    decisor: 'eduardo',
    motivo: 'Sem saldo de aco liberado para esta etapa.',
    nota: 'Armacao dos pilares do terreo',
    itens: [(sku: 'VRG-12', quantidade: 40000)],
  ),
  (
    obra: 'galpao',
    dias: 40,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Area de carga',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Base da doca de carga',
    itens: [
      (sku: 'CIM-50', quantidade: 5000),
      (sku: 'BRT-01', quantidade: 2000),
    ],
  ),
  (
    obra: 'vista',
    dias: 38,
    usuario: 'carlos',
    urgencia: 'urgente',
    local: 'Torre A - laje',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Armacao da laje do 4o pavimento',
    itens: [
      (sku: 'VRG-10', quantidade: 9000),
      (sku: 'ARA-18', quantidade: 2500),
    ],
  ),
  (
    obra: 'aurora',
    dias: 34,
    usuario: 'marcos',
    urgencia: 'padrao',
    local: 'Bloco 1 - 1o pavimento',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Armacao de pilares e vigas',
    itens: [
      (sku: 'VRG-10', quantidade: 12000),
      (sku: 'VRG-12', quantidade: 7000),
    ],
  ),
  (
    obra: 'vista',
    dias: 31,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Torre B - pilares',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Pilares do primeiro pavimento',
    itens: [
      (sku: 'VRG-08', quantidade: 15000),
      (sku: 'VRG-12', quantidade: 4000),
    ],
  ),
  (
    obra: 'galpao',
    dias: 28,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Pilares metalicos',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Chumbadores dos pilares metalicos',
    itens: [
      (sku: 'VRG-12', quantidade: 6000),
      (sku: 'ARA-18', quantidade: 2000),
    ],
  ),
  (
    obra: 'aurora',
    dias: 27,
    usuario: 'marcos',
    urgencia: 'urgente',
    local: 'Bloco 1 - laje',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Concretagem da laje do 2o pavimento',
    itens: [
      (sku: 'CIM-50', quantidade: 12000),
      (sku: 'BLO-14', quantidade: 250000),
    ],
  ),
  (
    obra: 'vista',
    dias: 24,
    usuario: 'fernanda',
    urgencia: 'padrao',
    local: 'Torre A - acabamento',
    status: 'recusado',
    decisor: 'eduardo',
    motivo:
        'Material ja retirado nesta semana. Confira o saldo antes de pedir.',
    nota: 'Reboco interno dos apartamentos 201 a 204',
    itens: [(sku: 'ARG-AC', quantidade: 6000)],
  ),
  (
    obra: 'aurora',
    dias: 20,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Bloco 2 - formas',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Formas das vigas do Bloco 2',
    itens: [
      (sku: 'CMP-18', quantidade: 3000),
      (sku: 'TAB-PI', quantidade: 25000),
      (sku: 'ESC-ME', quantidade: 5000),
    ],
  ),
  (
    obra: 'vista',
    dias: 19,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Torre A - alvenaria',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Alvenaria do 5o pavimento',
    itens: [
      (sku: 'CIM-50', quantidade: 6000),
      (sku: 'ARG-AC', quantidade: 5000),
      (sku: 'CAL-20', quantidade: 3000),
    ],
  ),
  (
    obra: 'galpao',
    dias: 16,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Cobertura',
    status: 'recusado',
    decisor: 'ana',
    motivo: 'Fora do escopo do mes. Reapresente em dezembro.',
    nota: 'Telhas e acessorios de cobertura',
    itens: [(sku: 'LON-PL', quantidade: 1000)],
  ),
  (
    obra: 'vista',
    dias: 13,
    usuario: 'carlos',
    urgencia: 'urgente',
    local: 'Torre B - laje',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Concretagem da laje do 2o pavimento da Torre B',
    itens: [
      (sku: 'CIM-50', quantidade: 8000),
      (sku: 'ARE-MD', quantidade: 1200),
      (sku: 'BRT-01', quantidade: 1000),
    ],
  ),
  (
    obra: 'aurora',
    dias: 11,
    usuario: 'marcos',
    urgencia: 'padrao',
    local: 'Bloco 2 - alvenaria',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Alvenaria do terreo do Bloco 2',
    itens: [
      (sku: 'BLO-14', quantidade: 300000),
      (sku: 'ARG-AC', quantidade: 8000),
    ],
  ),
  (
    obra: 'galpao',
    dias: 10,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Piso industrial',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Primeira faixa do piso industrial',
    itens: [
      (sku: 'CIM-50', quantidade: 7000),
      (sku: 'ARE-MD', quantidade: 2000),
      (sku: 'BRT-01', quantidade: 3000),
    ],
  ),
  (
    obra: 'vista',
    dias: 8,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Deposito',
    status: 'recusado',
    decisor: 'ana',
    motivo: 'Pedido duplicado. Use o protocolo anterior.',
    nota: 'Reposicao do deposito',
    itens: [(sku: 'EPI-LUV', quantidade: 2000)],
  ),
  (
    obra: 'aurora',
    dias: 7,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Bloco 2 - eletrica',
    status: 'recusado',
    decisor: 'ana',
    motivo: 'Aguardando projeto eletrico revisado.',
    nota: 'Infra eletrica do Bloco 2',
    itens: [(sku: 'FIO-25', quantidade: 800)],
  ),
  (
    obra: 'vista',
    dias: 6,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Torre A - reboco',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Reboco do 3o pavimento',
    itens: [
      (sku: 'CAL-20', quantidade: 3000),
      (sku: 'EPI-LUV', quantidade: 1000),
    ],
  ),
  (
    obra: 'vista',
    dias: 5,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Torre A - cobertura',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Formas do oitao da cobertura',
    itens: [
      (sku: 'TAB-PI', quantidade: 18000),
      (sku: 'ESC-ME', quantidade: 2400),
    ],
  ),
  (
    obra: 'galpao',
    dias: 4,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Piso industrial',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Segunda faixa do piso industrial',
    itens: [(sku: 'CIM-50', quantidade: 3500)],
  ),
  (
    obra: 'vista',
    dias: 4,
    usuario: 'carlos',
    urgencia: 'urgente',
    local: 'Torre A - cobertura',
    status: 'aprovado',
    decisor: 'rita',
    motivo: null,
    nota: 'Escoramento do oitao',
    itens: [(sku: 'ESC-ME', quantidade: 3600)],
  ),
  (
    obra: 'aurora',
    dias: 3,
    usuario: 'marcos',
    urgencia: 'urgente',
    local: 'Bloco 1 - eletrica',
    status: 'aprovado',
    decisor: 'eduardo',
    motivo: null,
    nota: 'Passagem de cabos dos quadros',
    itens: [(sku: 'FIO-25', quantidade: 2000)],
  ),
  (
    obra: 'vista',
    dias: 3,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Torre B - 4o pavimento',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Concretagem marcada para segunda-feira',
    itens: [
      (sku: 'CIM-50', quantidade: 5000),
      (sku: 'ARG-AC', quantidade: 4000),
    ],
  ),
  (
    obra: 'vista',
    dias: 2,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Torre A - eletrica',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'EPI para a equipe de eletrica',
    itens: [
      (sku: 'EPI-LUV', quantidade: 2000),
      (sku: 'EPI-CAP', quantidade: 800),
    ],
  ),
  (
    obra: 'aurora',
    dias: 4,
    usuario: 'marcos',
    urgencia: 'urgente',
    local: 'Bloco 1 - cobertura',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Contrapiso da casa de maquinas',
    itens: [
      (sku: 'CIM-50', quantidade: 10000),
      (sku: 'ARE-MD', quantidade: 1500),
    ],
  ),
  (
    obra: 'aurora',
    dias: 2,
    usuario: 'carlos',
    urgencia: 'padrao',
    local: 'Bloco 2 - formas',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Formas das escadas',
    itens: [
      (sku: 'CMP-18', quantidade: 2000),
      (sku: 'TAB-PI', quantidade: 12000),
    ],
  ),
  (
    obra: 'galpao',
    dias: 5,
    usuario: 'joao',
    urgencia: 'padrao',
    local: 'Cobertura',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Protecao das telhas antes da chuva',
    itens: [(sku: 'LON-PL', quantidade: 600)],
  ),
  (
    obra: 'galpao',
    dias: 2,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Area de carga',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Rampa de acesso da doca',
    itens: [(sku: 'CIM-50', quantidade: 4000)],
  ),
  (
    obra: 'vista',
    dias: 1,
    usuario: 'joao',
    urgencia: 'urgente',
    local: 'Torre B - laje',
    status: 'pendente',
    decisor: null,
    motivo: null,
    nota: 'Armacao da laje do 3o pavimento',
    itens: [
      (sku: 'VRG-10', quantidade: 6000),
      (sku: 'ARA-18', quantidade: 1500),
    ],
  ),
];

const gastos = <Gasto>[
  (
    obra: 'escola',
    dias: 62,
    usuario: 'eduardo',
    categoria: 4,
    descricao: 'Servico de troca do telhado',
    valor: 890000,
  ),
  (
    obra: 'vista',
    dias: 56,
    usuario: 'eduardo',
    categoria: 3,
    descricao: 'Locacao de grua - mes 1',
    valor: 1850000,
  ),
  (
    obra: 'aurora',
    dias: 50,
    usuario: 'eduardo',
    categoria: 3,
    descricao: 'Locacao de grua - mes 1',
    valor: 2450000,
  ),
  (
    obra: 'vista',
    dias: 42,
    usuario: 'eduardo',
    categoria: 3,
    descricao: 'Locacao de andaime fachadeiro',
    valor: 420000,
  ),
  (
    obra: 'galpao',
    dias: 38,
    usuario: 'rita',
    categoria: 3,
    descricao: 'Locacao de retroescavadeira',
    valor: 740000,
  ),
  (
    obra: 'aurora',
    dias: 33,
    usuario: 'eduardo',
    categoria: 4,
    descricao: 'Servico de montagem de formas',
    valor: 1280000,
  ),
  (
    obra: 'vista',
    dias: 28,
    usuario: 'rita',
    categoria: 5,
    descricao: 'Reposicao de EPI da equipe terceirizada',
    valor: 96500,
  ),
  (
    obra: 'galpao',
    dias: 21,
    usuario: 'rita',
    categoria: 5,
    descricao: 'Treinamento NR-35 para seis colaboradores',
    valor: 230000,
  ),
  (
    obra: 'aurora',
    dias: 18,
    usuario: 'eduardo',
    categoria: 3,
    descricao: 'Locacao de elevador cremalheira',
    valor: 1550000,
  ),
  (
    obra: 'vista',
    dias: 14,
    usuario: 'rita',
    categoria: 3,
    descricao: 'Locacao de bomba de concreto',
    valor: 680000,
  ),
  (
    obra: 'galpao',
    dias: 7,
    usuario: 'rita',
    categoria: 3,
    descricao: 'Locacao de plataforma elevatoria',
    valor: 390000,
  ),
];

const retiradas = <Retirada>[
  (
    patrimonio: 'SER-001',
    usuario: 'marcos',
    obra: 'aurora',
    dias: 30,
    diasPrevistos: 23,
    diasDevolvido: 25,
  ),
  (
    patrimonio: 'NIV-001',
    usuario: 'rita',
    obra: 'galpao',
    dias: 26,
    diasPrevistos: 19,
    diasDevolvido: 20,
  ),
  (
    patrimonio: 'AND-001',
    usuario: 'carlos',
    obra: 'aurora',
    dias: 20,
    diasPrevistos: 6,
    diasDevolvido: null,
  ),
  (
    patrimonio: 'BET-001',
    usuario: 'joao',
    obra: 'vista',
    dias: 18,
    diasPrevistos: 4,
    diasDevolvido: 6,
  ),
  (
    patrimonio: 'MAR-001',
    usuario: 'carlos',
    obra: 'vista',
    dias: 12,
    diasPrevistos: 5,
    diasDevolvido: 7,
  ),
  (
    patrimonio: 'BET-002',
    usuario: 'joao',
    obra: 'vista',
    dias: 9,
    diasPrevistos: -5,
    diasDevolvido: null,
  ),
  (
    patrimonio: 'COM-001',
    usuario: 'joao',
    obra: 'galpao',
    dias: 4,
    diasPrevistos: -10,
    diasDevolvido: null,
  ),
];

const acessos = <String, List<int>>{
  'ana': [62, 48, 30, 21, 12, 6, 3, 1],
  'eduardo': [66, 62, 55, 48, 40, 34, 26, 20, 12, 7, 3],
  'rita': [44, 40, 30, 28, 21, 19, 13, 10, 6, 4],
  'joao': [58, 44, 40, 31, 28, 19, 16, 10, 8, 6, 4, 3, 2, 1],
  'carlos': [52, 38, 24, 20, 13, 7, 5, 4, 2],
  'marcos': [60, 50, 42, 34, 27, 11, 4, 3, 2],
  'fernanda': [60, 40, 24, 18],
  'pedro': [30, 15, 5],
  'bisteca': [28, 9],
};

final agora = DateTime.now();

DateTime emDias(int dias) => DateTime(
  agora.year,
  agora.month,
  agora.day - dias,
  7 + dias.abs() % 10,
  dias.abs() * 7 % 60,
);

String numerico(int centesimos) =>
    '${centesimos ~/ 100}.${(centesimos % 100).toString().padLeft(2, '0')}';

String protocoloDe(int indice) =>
    prefixoDoProtocolo +
    indice.toRadixString(16).toUpperCase().padLeft(28, '0');

Future<void> main(List<String> argumentos) async {
  if (!argumentos.contains('--confirmar')) {
    stdout.writeln(
      'Semeia a empresa Constroi Teste com um historico de 70 dias.\n'
      '\n'
      'Apaga antes, somente dessa empresa: entradas, movimentacoes,\n'
      'despesas, emprestimos, pedidos, saldos de estoque, vinculos de\n'
      'equipe e eventos. Mantem a empresa, os usuarios, os produtos e os\n'
      'equipamentos que ja existem.\n'
      '\n'
      'Rode com --confirmar para aplicar.',
    );
    return;
  }

  final ambiente = DotEnv(includePlatformEnvironment: true)
    ..load(File('.env').existsSync() ? ['.env'] : []);
  final databaseUrl = ambiente['DATABASE_URL']?.trim();
  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('DATABASE_URL nao configurada');
    exitCode = 1;
    return;
  }

  final conexao = await Connection.openFromUrl(
    normalizarDatabaseUrl(databaseUrl),
  );
  try {
    await conexao.runTx(semear);
  } finally {
    await conexao.close();
  }
}

Future<void> semear(Session tx) async {
  final empresas = await tx.execute(
    Sql.named('SELECT id FROM empresa WHERE cnpj = @cnpj'),
    parameters: {'cnpj': cnpjDaEmpresa},
  );
  if (empresas.isEmpty) {
    throw StateError('Empresa $cnpjDaEmpresa nao encontrada.');
  }
  final empresaId = empresas.first[0]! as int;

  await limpar(tx, empresaId);

  final pessoas = await prepararPessoas(tx, empresaId);
  final obras = await prepararObras(tx, empresaId);
  final produtos = await prepararProdutos(tx, empresaId);
  final equipamentos = await prepararEquipamentos(tx, empresaId);

  await registrarCatalogo(
    tx,
    empresaId,
    pessoas,
    obras,
    produtos,
    equipamentos,
  );
  await montarEquipes(tx, empresaId, pessoas, obras);
  await registrarAcessos(tx, empresaId, pessoas);

  final pedidos = await criarPedidos(tx, empresaId, pessoas, obras, produtos);
  await aplicarMovimentos(tx, empresaId, pessoas, obras, produtos, pedidos);
  await lancarGastos(tx, empresaId, pessoas, obras);
  await registrarRetiradas(tx, empresaId, pessoas, obras, equipamentos);

  await resumir(tx, empresaId);
}

Future<void> limpar(Session tx, int empresaId) async {
  const obrasDaEmpresa = 'SELECT id FROM obra WHERE empresa_id = @empresa';
  const entradasDaEmpresa =
      'SELECT id FROM entrada_estoque WHERE obra_id IN ($obrasDaEmpresa)';
  const pedidosDaEmpresa =
      'SELECT id FROM pedido WHERE obra_id IN ($obrasDaEmpresa)';
  final comandos = [
    'DELETE FROM movimentacao_estoque WHERE empresa_id = @empresa',
    'DELETE FROM item_entrada WHERE entrada_id IN ($entradasDaEmpresa)',
    'DELETE FROM entrada_estoque WHERE obra_id IN ($obrasDaEmpresa)',
    'DELETE FROM despesa_obra WHERE empresa_id = @empresa',
    'DELETE FROM emprestimo WHERE empresa_id = @empresa',
    'DELETE FROM item_pedido WHERE pedido_id IN ($pedidosDaEmpresa)',
    'DELETE FROM pedido WHERE obra_id IN ($obrasDaEmpresa)',
    'DELETE FROM estoque WHERE obra_id IN ($obrasDaEmpresa)',
    'DELETE FROM usuario_obra WHERE empresa_id = @empresa',
    'DELETE FROM log_sistema WHERE empresa_id = @empresa',
  ];
  for (final comando in comandos) {
    await tx.execute(Sql.named(comando), parameters: {'empresa': empresaId});
  }
}

Future<Map<String, int>> prepararPessoas(Session tx, int empresaId) async {
  final pessoas = <String, int>{};
  for (final entrada in emailsExistentes.entries) {
    final achadas = await tx.execute(
      Sql.named('SELECT id FROM usuario WHERE LOWER(email) = LOWER(@email)'),
      parameters: {'email': entrada.value},
    );
    if (achadas.isEmpty) {
      throw StateError('Usuario ${entrada.value} nao encontrado.');
    }
    pessoas[entrada.key] = achadas.first[0]! as int;
  }

  for (final entrada in emailsOpcionais.entries) {
    final achadas = await tx.execute(
      Sql.named('SELECT id FROM usuario WHERE LOWER(email) = LOWER(@email)'),
      parameters: {'email': entrada.value},
    );
    if (achadas.isNotEmpty) pessoas[entrada.key] = achadas.first[0]! as int;
  }

  final hash = gerarHash(senhaDosNovos);
  for (final pessoa in pessoasNovas) {
    final criada = await tx.execute(
      Sql.named('''
        INSERT INTO usuario (empresa_id, nome, email, senha_hash, tipo, ativo)
        VALUES (@empresa, @nome, @email, @hash, @tipo, @ativo)
        ON CONFLICT (LOWER(email)) DO UPDATE
        SET nome = EXCLUDED.nome,
            tipo = EXCLUDED.tipo,
            ativo = EXCLUDED.ativo,
            senha_hash = EXCLUDED.senha_hash,
            atualizado_em = CURRENT_TIMESTAMP
        RETURNING id
      '''),
      parameters: {
        'empresa': empresaId,
        'nome': pessoa.nome,
        'email': pessoa.email,
        'hash': hash,
        'tipo': pessoa.tipo,
        'ativo': pessoa.ativo,
      },
    );
    pessoas[pessoa.chave] = criada.first[0]! as int;
  }
  return pessoas;
}

Future<Map<String, int>> prepararObras(Session tx, int empresaId) async {
  final obras = <String, int>{};
  for (final canteiro in canteiros) {
    final achadas = await tx.execute(
      Sql.named(
        'SELECT id FROM obra WHERE empresa_id = @empresa AND nome = @nome',
      ),
      parameters: {'empresa': empresaId, 'nome': canteiro.nome},
    );
    final id = achadas.isNotEmpty
        ? achadas.first[0]! as int
        : (await tx.execute(
                Sql.named('''
            INSERT INTO obra (empresa_id, nome, endereco, status)
            VALUES (@empresa, @nome, @endereco, @status) RETURNING id
          '''),
                parameters: {
                  'empresa': empresaId,
                  'nome': canteiro.nome,
                  'endereco': canteiro.endereco,
                  'status': canteiro.status,
                },
              )).first[0]!
              as int;
    await tx.execute(
      Sql.named('''
        UPDATE obra SET endereco = @endereco, status = @status,
          orcamento_total = @orcamento::numeric
        WHERE id = @id
      '''),
      parameters: {
        'id': id,
        'endereco': canteiro.endereco,
        'status': canteiro.status,
        'orcamento': numerico(canteiro.orcamento),
      },
    );
    obras[canteiro.chave] = id;
  }
  return obras;
}

Future<Map<String, int>> prepararProdutos(Session tx, int empresaId) async {
  final produtos = <String, int>{};
  for (final material in materiais) {
    final criado = await tx.execute(
      Sql.named('''
        INSERT INTO produto (empresa_id, nome, unidade, sku, estoque_minimo,
          categoria_custo_id)
        VALUES (@empresa, @nome, @unidade, @sku, @minimo::numeric, @categoria)
        ON CONFLICT (empresa_id, LOWER(sku)) WHERE sku IS NOT NULL
        DO UPDATE SET nome = EXCLUDED.nome,
          unidade = EXCLUDED.unidade,
          estoque_minimo = EXCLUDED.estoque_minimo,
          categoria_custo_id = EXCLUDED.categoria_custo_id,
          atualizado_em = CURRENT_TIMESTAMP
        RETURNING id
      '''),
      parameters: {
        'empresa': empresaId,
        'nome': material.nome,
        'unidade': material.unidade,
        'sku': material.sku,
        'minimo': numerico(material.minimo * 100),
        'categoria': material.categoria,
      },
    );
    produtos[material.sku] = criado.first[0]! as int;
  }
  return produtos;
}

Future<Map<String, int>> prepararEquipamentos(
  Session tx,
  int empresaId,
) async {
  final equipamentos = <String, int>{};
  for (final ferramenta in ferramentas) {
    final criado = await tx.execute(
      Sql.named('''
        INSERT INTO equipamento (empresa_id, nome, patrimonio, status)
        VALUES (@empresa, @nome, @patrimonio, @status)
        ON CONFLICT (empresa_id, patrimonio) DO UPDATE
        SET nome = EXCLUDED.nome, status = EXCLUDED.status,
            atualizado_em = CURRENT_TIMESTAMP
        RETURNING id
      '''),
      parameters: {
        'empresa': empresaId,
        'nome': ferramenta.nome,
        'patrimonio': ferramenta.patrimonio,
        'status': ferramenta.status,
      },
    );
    equipamentos[ferramenta.patrimonio] = criado.first[0]! as int;
  }
  return equipamentos;
}

Future<void> anotar(
  Session tx,
  int empresaId,
  int usuarioId,
  String acao,
  DateTime quando,
) => tx.execute(
  Sql.named('''
    INSERT INTO log_sistema (empresa_id, usuario_id, acao, data)
    VALUES (@empresa, @usuario, @acao, @data)
  '''),
  parameters: {
    'empresa': empresaId,
    'usuario': usuarioId,
    'acao': acao,
    'data': quando,
  },
);

Future<void> registrarCatalogo(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
  Map<String, int> produtos,
  Map<String, int> equipamentos,
) async {
  final ana = pessoas['ana']!;
  final abertura = emDias(72);
  var passo = 0;
  Future<void> evento(String acao, int autor) async {
    await anotar(
      tx,
      empresaId,
      autor,
      acao,
      abertura.add(Duration(minutes: passo++)),
    );
  }

  for (final pessoa in pessoasNovas) {
    await evento('CRIACAO_USUARIO usuario=${pessoas[pessoa.chave]}', ana);
  }
  for (final canteiro in canteiros) {
    await evento('CRIACAO_OBRA obra=${obras[canteiro.chave]}', ana);
  }
  for (final material in materiais) {
    await evento('CRIACAO_PRODUTO produto=${produtos[material.sku]}', ana);
  }
  for (final ferramenta in ferramentas) {
    await evento(
      'CRIACAO_EQUIPAMENTO equipamento=${equipamentos[ferramenta.patrimonio]}',
      ana,
    );
  }

  await anotar(
    tx,
    empresaId,
    pessoas['eduardo']!,
    'ALTERACAO_PRODUTO produto=${produtos['CIM-50']}',
    emDias(46),
  );
  await anotar(
    tx,
    empresaId,
    ana,
    'ALTERACAO_OBRA obra=${obras['escola']}',
    emDias(22),
  );
  await anotar(
    tx,
    empresaId,
    ana,
    'ALTERACAO_EQUIPAMENTO equipamento=${equipamentos['VIB-001']}',
    emDias(15),
  );
  await anotar(
    tx,
    empresaId,
    ana,
    'INATIVACAO_USUARIO usuario=${pessoas['fernanda']}',
    emDias(18),
  );
}

Future<void> montarEquipes(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
) async {
  for (final vinculo in equipes) {
    final criado = await tx.execute(
      Sql.named('''
        INSERT INTO usuario_obra
          (empresa_id, usuario_id, obra_id, data_inicio, data_fim)
        VALUES (@empresa, @usuario, @obra, @inicio, @fim)
        RETURNING id
      '''),
      parameters: {
        'empresa': empresaId,
        'usuario': pessoas[vinculo.usuario],
        'obra': obras[vinculo.obra],
        'inicio': emDias(vinculo.dias),
        'fim': vinculo.diasFim == null ? null : emDias(vinculo.diasFim!),
      },
    );
    final id = criado.first[0]! as int;
    await anotar(
      tx,
      empresaId,
      pessoas['ana']!,
      'VINCULO_EQUIPE vinculo=$id',
      emDias(vinculo.dias),
    );
    if (vinculo.diasFim != null) {
      await anotar(
        tx,
        empresaId,
        pessoas['ana']!,
        'ENCERRAMENTO_EQUIPE vinculo=$id',
        emDias(vinculo.diasFim!),
      );
    }
  }
}

Future<void> registrarAcessos(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
) async {
  for (final entrada in acessos.entries) {
    final usuarioId = pessoas[entrada.key];
    if (usuarioId == null) continue;
    for (final dias in entrada.value) {
      await anotar(
        tx,
        empresaId,
        usuarioId,
        'LOGIN usuario=$usuarioId',
        emDias(dias).subtract(const Duration(hours: 1)),
      );
    }
  }
}

typedef PedidoCriado = ({int id, String protocolo, int indice});

Future<List<PedidoCriado?>> criarPedidos(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
  Map<String, int> produtos,
) async {
  final criados = <PedidoCriado?>[];
  for (var indice = 0; indice < requisicoes.length; indice++) {
    final requisicao = requisicoes[indice];
    final protocolo = protocoloDe(indice + 1);
    final autor = pessoas[requisicao.usuario]!;
    final obraId = obras[requisicao.obra]!;
    final abertura = emDias(requisicao.dias);
    final pedido = await tx.execute(
      Sql.named('''
        INSERT INTO pedido (usuario_id, obra_id, protocolo, status,
          justificativa, justificativa_recusa, local_obra, urgencia, data)
        VALUES (@usuario, @obra, @protocolo, @status, @nota, @motivo,
          @local, @urgencia, @data)
        RETURNING id
      '''),
      parameters: {
        'usuario': autor,
        'obra': obraId,
        'protocolo': protocolo,
        'status': requisicao.status,
        'nota': requisicao.nota,
        'motivo': requisicao.motivo,
        'local': requisicao.local,
        'urgencia': requisicao.urgencia,
        'data': abertura,
      },
    );
    final pedidoId = pedido.first[0]! as int;
    for (final item in requisicao.itens) {
      await tx.execute(
        Sql.named('''
          INSERT INTO item_pedido (pedido_id, produto_id, quantidade)
          VALUES (@pedido, @produto, @quantidade::numeric)
        '''),
        parameters: {
          'pedido': pedidoId,
          'produto': produtos[item.sku],
          'quantidade': numerico(item.quantidade),
        },
      );
    }
    await anotar(
      tx,
      empresaId,
      autor,
      'CRIACAO_PEDIDO pedido=$pedidoId obra=$obraId protocolo=$protocolo',
      abertura,
    );
    if (requisicao.status == 'recusado') {
      await anotar(
        tx,
        empresaId,
        pessoas[requisicao.decisor]!,
        'RECUSA_PEDIDO pedido=$pedidoId obra=$obraId protocolo=$protocolo',
        abertura.add(const Duration(hours: 3)),
      );
    }
    criados.add((id: pedidoId, protocolo: protocolo, indice: indice));
  }
  return criados;
}

Future<void> aplicarMovimentos(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
  Map<String, int> produtos,
  List<PedidoCriado?> pedidos,
) async {
  final unidades = {for (final m in materiais) m.sku: m.unidade};
  final nomes = {for (final m in materiais) m.sku: m.nome};
  final categorias = {for (final m in materiais) m.sku: m.categoria};
  final saldos = <String, int>{};

  final linhaDoTempo = <({DateTime quando, int tipo, int alvo})>[
    for (var i = 0; i < compras.length; i++)
      (quando: emDias(compras[i].dias), tipo: 0, alvo: i),
    for (var i = 0; i < requisicoes.length; i++)
      if (requisicoes[i].status == 'aprovado')
        (
          quando: emDias(requisicoes[i].dias).add(const Duration(hours: 3)),
          tipo: 1,
          alvo: i,
        ),
  ]..sort((a, b) => a.quando.compareTo(b.quando));

  for (final momento in linhaDoTempo) {
    if (momento.tipo == 0) {
      final compra = compras[momento.alvo];
      final obraId = obras[compra.obra]!;
      final autor = pessoas[compra.usuario]!;
      final entrada = await tx.execute(
        Sql.named('''
          INSERT INTO entrada_estoque (usuario_id, obra_id, justificativa, data)
          VALUES (@usuario, @obra, @nota, @data) RETURNING id
        '''),
        parameters: {
          'usuario': autor,
          'obra': obraId,
          'nota': compra.nota,
          'data': momento.quando,
        },
      );
      final entradaId = entrada.first[0]! as int;
      for (final item in compra.itens) {
        final produtoId = produtos[item.sku]!;
        await tx.execute(
          Sql.named('''
            INSERT INTO item_entrada (entrada_id, produto_id, quantidade,
              valor_unitario, categoria_custo_id)
            VALUES (@entrada, @produto, @quantidade::numeric,
              @preco::numeric, @categoria)
          '''),
          parameters: {
            'entrada': entradaId,
            'produto': produtoId,
            'quantidade': numerico(item.quantidade),
            'preco': numerico(item.preco),
            'categoria': categorias[item.sku],
          },
        );
        final chave = '$obraId:$produtoId';
        saldos[chave] = (saldos[chave] ?? 0) + item.quantidade;
        await tx.execute(
          Sql.named('''
            INSERT INTO estoque (obra_id, produto_id, quantidade)
            VALUES (@obra, @produto, @quantidade::numeric)
            ON CONFLICT (obra_id, produto_id) DO UPDATE
            SET quantidade = @quantidade::numeric
          '''),
          parameters: {
            'obra': obraId,
            'produto': produtoId,
            'quantidade': numerico(saldos[chave]!),
          },
        );
        await anotar(
          tx,
          empresaId,
          autor,
          'ENTRADA_MANUAL entrada=$entradaId obra=$obraId '
          'produto=$produtoId quantidade=${numerico(item.quantidade)} '
          'saldo=${numerico(saldos[chave]!)}',
          momento.quando,
        );
      }
      continue;
    }

    final requisicao = requisicoes[momento.alvo];
    final pedido = pedidos[momento.alvo]!;
    final obraId = obras[requisicao.obra]!;
    final decisor = pessoas[requisicao.decisor]!;
    for (final item in requisicao.itens) {
      final produtoId = produtos[item.sku]!;
      final chave = '$obraId:$produtoId';
      final anterior = saldos[chave] ?? 0;
      final posterior = anterior - item.quantidade;
      if (posterior < 0) {
        throw StateError(
          'Saldo insuficiente em ${requisicao.obra}/${item.sku}: '
          'tem ${numerico(anterior)}, pedido ${numerico(item.quantidade)} '
          'no protocolo ${pedido.protocolo}.',
        );
      }
      saldos[chave] = posterior;
      await tx.execute(
        Sql.named('''
          UPDATE estoque SET quantidade = @quantidade::numeric
          WHERE obra_id = @obra AND produto_id = @produto
        '''),
        parameters: {
          'obra': obraId,
          'produto': produtoId,
          'quantidade': numerico(posterior),
        },
      );
      await anotar(
        tx,
        empresaId,
        decisor,
        'BAIXA_ESTOQUE pedido=${pedido.id} obra=$obraId produto=$produtoId '
        'quantidade=${numerico(item.quantidade)} '
        'saldo=${numerico(posterior)} protocolo=${pedido.protocolo}',
        momento.quando,
      );
      await tx.execute(
        Sql.named('''
          INSERT INTO movimentacao_estoque (empresa_id, obra_id, produto_id,
            pedido_id, registrado_por_usuario_id, tipo, quantidade,
            saldo_anterior, saldo_posterior, ocorrido_em, protocolo_pedido,
            produto_nome, unidade)
          VALUES (@empresa, @obra, @produto, @pedido, @usuario, 'saida_pedido',
            @quantidade::numeric, @anterior::numeric, @posterior::numeric,
            @quando, @protocolo, @nome, @unidade)
        '''),
        parameters: {
          'empresa': empresaId,
          'obra': obraId,
          'produto': produtoId,
          'pedido': pedido.id,
          'usuario': decisor,
          'quantidade': numerico(item.quantidade),
          'anterior': numerico(anterior),
          'posterior': numerico(posterior),
          'quando': momento.quando,
          'protocolo': pedido.protocolo,
          'nome': nomes[item.sku],
          'unidade': unidades[item.sku],
        },
      );
    }
  }
}

Future<void> lancarGastos(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
) async {
  for (final gasto in gastos) {
    await tx.execute(
      Sql.named('''
        INSERT INTO despesa_obra (empresa_id, obra_id,
          registrado_por_usuario_id, categoria_custo_id, descricao, valor,
          data_lancamento)
        VALUES (@empresa, @obra, @usuario, @categoria, @descricao,
          @valor::numeric, @data)
      '''),
      parameters: {
        'empresa': empresaId,
        'obra': obras[gasto.obra],
        'usuario': pessoas[gasto.usuario],
        'categoria': gasto.categoria,
        'descricao': gasto.descricao,
        'valor': numerico(gasto.valor),
        'data': emDias(gasto.dias),
      },
    );
  }
}

Future<void> registrarRetiradas(
  Session tx,
  int empresaId,
  Map<String, int> pessoas,
  Map<String, int> obras,
  Map<String, int> equipamentos,
) async {
  for (final retirada in retiradas) {
    final equipamentoId = equipamentos[retirada.patrimonio]!;
    final usuarioId = pessoas[retirada.usuario]!;
    final obraId = obras[retirada.obra]!;
    final saida = emDias(retirada.dias);
    final prevista = emDias(retirada.diasPrevistos);
    final devolvida = retirada.diasDevolvido == null
        ? null
        : emDias(retirada.diasDevolvido!);
    final dias = prevista.difference(saida).inDays;
    final criado = await tx.execute(
      Sql.named('''
        INSERT INTO emprestimo (empresa_id, equipamento_id, usuario_id,
          obra_id, data_emprestimo, data_prevista, data_devolucao, status)
        VALUES (@empresa, @equipamento, @usuario, @obra, @saida, @prevista,
          @devolucao, @status)
        RETURNING id
      '''),
      parameters: {
        'empresa': empresaId,
        'equipamento': equipamentoId,
        'usuario': usuarioId,
        'obra': obraId,
        'saida': saida,
        'prevista': prevista,
        'devolucao': devolvida,
        'status': devolvida == null ? 'aberto' : 'devolvido',
      },
    );
    final id = criado.first[0]! as int;
    await anotar(
      tx,
      empresaId,
      usuarioId,
      'EMPRESTIMO_EQUIPAMENTO emprestimo=$id equipamento=$equipamentoId '
      'usuario=$usuarioId obra=$obraId dias=$dias',
      saida,
    );
    if (devolvida != null) {
      await anotar(
        tx,
        empresaId,
        usuarioId,
        'DEVOLUCAO_EQUIPAMENTO emprestimo=$id equipamento=$equipamentoId '
        'usuario=$usuarioId obra=$obraId',
        devolvida,
      );
    } else {
      await tx.execute(
        Sql.named('''
          UPDATE equipamento SET status = 'em_uso',
            atualizado_em = CURRENT_TIMESTAMP
          WHERE id = @id
        '''),
        parameters: {'id': equipamentoId},
      );
    }
  }
}

Future<void> resumir(Session tx, int empresaId) async {
  const contagens = <String, String>{
    'obras': 'SELECT COUNT(*) FROM obra WHERE empresa_id = @empresa',
    'usuarios': 'SELECT COUNT(*) FROM usuario WHERE empresa_id = @empresa',
    'produtos': 'SELECT COUNT(*) FROM produto WHERE empresa_id = @empresa',
    'equipamentos':
        'SELECT COUNT(*) FROM equipamento WHERE empresa_id = @empresa',
    'saldos de estoque':
        'SELECT COUNT(*) FROM estoque e JOIN obra o'
        ' ON o.id = e.obra_id WHERE o.empresa_id = @empresa',
    'pedidos':
        'SELECT COUNT(*) FROM pedido p JOIN obra o ON o.id = p.obra_id'
        ' WHERE o.empresa_id = @empresa',
    'entradas':
        'SELECT COUNT(*) FROM entrada_estoque e JOIN obra o'
        ' ON o.id = e.obra_id WHERE o.empresa_id = @empresa',
    'movimentacoes':
        'SELECT COUNT(*) FROM movimentacao_estoque WHERE empresa_id = @empresa',
    'despesas': 'SELECT COUNT(*) FROM despesa_obra WHERE empresa_id = @empresa',
    'emprestimos':
        'SELECT COUNT(*) FROM emprestimo WHERE empresa_id = @empresa',
    'eventos': 'SELECT COUNT(*) FROM log_sistema WHERE empresa_id = @empresa',
  };
  stdout.writeln('Empresa $empresaId semeada:');
  for (final contagem in contagens.entries) {
    final total = await tx.execute(
      Sql.named(contagem.value),
      parameters: {'empresa': empresaId},
    );
    stdout.writeln('  ${contagem.key}: ${total.first[0]}');
  }
  stdout.writeln('Senha dos usuarios novos: $senhaDosNovos');
}
