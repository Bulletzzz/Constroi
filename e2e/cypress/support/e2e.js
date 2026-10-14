const api = () => Cypress.env('apiUrl');
const senha = () => Cypress.env('senhaPadrao');

afterEach(() => {
  if (Cypress.config('video')) cy.wait(1500);
});

function marca() {
  return Math.random().toString(36).slice(2, 8);
}

Cypress.Commands.add('chamarApi', (metodo, rota, corpo, token) => {
  const opcoes = {
    method: metodo,
    url: `${api()}${rota}`,
    failOnStatusCode: false,
  };
  if (corpo) opcoes.body = corpo;
  if (token) opcoes.headers = { Authorization: `Bearer ${token}` };
  return cy.request(opcoes);
});

Cypress.Commands.add('entrarNaApi', (email) =>
  cy
    .chamarApi('POST', '/login', { email, senha: senha() })
    .then((r) => r.body.token),
);

Cypress.Commands.add('semearEmpresa', () => {
  const id = marca();
  const cenario = {
    marca: id,
    emailMaster: `master.${id}@teste.com`,
    emailEngenheiro: `eng.${id}@teste.com`,
    emailPedreiro: `ped.${id}@teste.com`,
    senha: senha(),
  };

  return cy
    .chamarApi('POST', '/empresas', {
      empresa: { nome: `Construtora E2E ${id}`, cnpj: `44.444.444/${id}` },
      usuario: {
        nome: `Master ${id}`,
        email: cenario.emailMaster,
        senha: senha(),
      },
    })
    .then(() => cy.entrarNaApi(cenario.emailMaster))
    .then((tokenMaster) => {
      cenario.tokenMaster = tokenMaster;
      return cy.chamarApi(
        'POST',
        '/usuarios',
        {
          usuario: {
            nome: `Eng ${id}`,
            email: cenario.emailEngenheiro,
            senha: senha(),
            tipo: 'engenheiro',
          },
        },
        tokenMaster,
      );
    })
    .then(() =>
      cy.chamarApi(
        'POST',
        '/usuarios',
        {
          usuario: {
            nome: `Ped ${id}`,
            email: cenario.emailPedreiro,
            senha: senha(),
            tipo: 'pedreiro',
          },
        },
        cenario.tokenMaster,
      ),
    )
    .then((r) => {
      cenario.idPedreiro = r.body.id;
      return cy.entrarNaApi(cenario.emailEngenheiro);
    })
    .then((tokenEngenheiro) => {
      cenario.tokenEngenheiro = tokenEngenheiro;
      return cy.chamarApi(
        'POST',
        '/obras',
        {
          obra: {
            nome: `Obra E2E ${id}`,
            endereco: 'Rua de teste, 100',
            status: 'ativa',
          },
        },
        tokenEngenheiro,
      );
    })
    .then((r) => {
      cenario.obra = r.body;
      return cy.chamarApi(
        'POST',
        '/produtos',
        { produto: { nome: `Cimento ${id}`, unidade: 'saco' } },
        cenario.tokenEngenheiro,
      );
    })
    .then((r) => {
      cenario.produto = r.body;
      return cy.chamarApi(
        'POST',
        `/obras/${cenario.obra.id}/equipe`,
        { equipe: { usuario_id: cenario.idPedreiro } },
        cenario.tokenEngenheiro,
      );
    })
    .then(() => cy.entrarNaApi(cenario.emailPedreiro))
    .then((tokenPedreiro) => {
      cenario.tokenPedreiro = tokenPedreiro;
      return cenario;
    });
});

Cypress.Commands.add('criarPedido', (cenario, quantidade = 1) =>
  cy.chamarApi(
    'POST',
    '/pedidos',
    {
      pedido: {
        obra_id: cenario.obra.id,
        itens: [{ produto_id: cenario.produto.id, quantidade }],
      },
    },
    cenario.tokenPedreiro,
  ),
);

Cypress.Commands.add('abrirApp', (caminho = '/') => {
  cy.visit(caminho);
  cy.get('[data-cy=login-email]', { timeout: 60000 }).should('exist');
});

Cypress.Commands.add('preencher', (identificador, texto) => {
  cy.get(`[data-cy=${identificador}]`).click();
  cy.get(`[data-cy=${identificador}-campo]`).clear().type(texto);
});

Cypress.Commands.add('entrarNaTela', (email) => {
  cy.preencher('login-email', email);
  cy.preencher('login-senha', senha());
  cy.get('[data-cy=login-entrar]').click();
});
