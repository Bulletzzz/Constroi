const api = () => Cypress.env('apiUrl');

const marca = () => Math.random().toString(36).slice(2, 8);

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

Cypress.Commands.add('entrarNaApi', (email, senha) =>
  cy.chamarApi('POST', '/login', { email, senha }).then((r) => r.body.token),
);

function criarEmpresa(cenario, modelo) {
  return cy.chamarApi('POST', '/empresas', {
    empresa: {
      nome: `${modelo.nomeEmpresa} ${cenario.marca}`,
      cnpj: `${modelo.prefixoCnpj}/${cenario.marca}`,
    },
    usuario: {
      nome: `Master ${cenario.marca}`,
      email: cenario.emailMaster,
      senha: cenario.senha,
    },
  });
}

function criarUsuario(cenario, tipo, email) {
  return cy
    .chamarApi(
      'POST',
      '/usuarios',
      {
        usuario: {
          nome: `${tipo} ${cenario.marca}`,
          email,
          senha: cenario.senha,
          tipo,
        },
      },
      cenario.tokenMaster,
    )
    .then((r) => r.body.id);
}

function criarObra(cenario, modelo) {
  return cy
    .chamarApi(
      'POST',
      '/obras',
      { obra: { ...modelo.obra, nome: `${modelo.obra.nome} ${cenario.marca}` } },
      cenario.tokenEngenheiro,
    )
    .then((r) => r.body);
}

function criarProduto(cenario, modelo) {
  return cy
    .chamarApi(
      'POST',
      '/produtos',
      {
        produto: {
          ...modelo.produto,
          nome: `${modelo.produto.nome} ${cenario.marca}`,
        },
      },
      cenario.tokenEngenheiro,
    )
    .then((r) => r.body);
}

function vincularPedreiro(cenario) {
  return cy.chamarApi(
    'POST',
    `/obras/${cenario.obra.id}/equipe`,
    { equipe: { usuario_id: cenario.idPedreiro } },
    cenario.tokenEngenheiro,
  );
}

Cypress.Commands.add('semearCenario', () =>
  cy.fixture('credenciais').then((credenciais) =>
    cy.fixture('empresa').then((modelo) => {
      const id = marca();
      const cenario = {
        marca: id,
        senha: credenciais.senhaPadrao,
        emailMaster: `master.${id}@teste.com`,
        emailEngenheiro: `eng.${id}@teste.com`,
        emailPedreiro: `ped.${id}@teste.com`,
      };

      return criarEmpresa(cenario, modelo)
        .then(() => cy.entrarNaApi(cenario.emailMaster, cenario.senha))
        .then((token) => {
          cenario.tokenMaster = token;
          return criarUsuario(cenario, 'engenheiro', cenario.emailEngenheiro);
        })
        .then(() => criarUsuario(cenario, 'pedreiro', cenario.emailPedreiro))
        .then((idPedreiro) => {
          cenario.idPedreiro = idPedreiro;
          return cy.entrarNaApi(cenario.emailEngenheiro, cenario.senha);
        })
        .then((token) => {
          cenario.tokenEngenheiro = token;
          return criarObra(cenario, modelo);
        })
        .then((obra) => {
          cenario.obra = obra;
          return criarProduto(cenario, modelo);
        })
        .then((produto) => {
          cenario.produto = produto;
          return vincularPedreiro(cenario);
        })
        .then(() => cy.entrarNaApi(cenario.emailPedreiro, cenario.senha))
        .then((token) => {
          cenario.tokenPedreiro = token;
          return cenario;
        });
    }),
  ),
);

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
