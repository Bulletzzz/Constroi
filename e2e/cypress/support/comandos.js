import { loginPage } from '../pages/login.page';
import { navegacao } from '../pages/navegacao.page';
import { painelPage } from '../pages/painel.page';
import { estoquePage } from '../pages/estoque.page';

export const TEMPO_CARGA_APP = { timeout: 60000 };

const telas = {
  painel: painelPage,
  estoque: estoquePage,
};

Cypress.Commands.add('porIdentificador', (identificador, opcoes = {}) =>
  cy.get(`[data-cy=${identificador}]`, opcoes),
);

Cypress.Commands.add('naoExiste', (identificador) =>
  cy.get(`[data-cy=${identificador}]`).should('not.exist'),
);

Cypress.Commands.add('digitar', (identificador, texto) => {
  cy.porIdentificador(identificador).click();
  cy.porIdentificador(`${identificador}-campo`).clear().type(texto);
});

Cypress.Commands.add('abrirApp', (caminho = '/') => {
  cy.visit(caminho);
  loginPage.esperarTela(TEMPO_CARGA_APP);
});

Cypress.Commands.add('entrarComo', (email, senha) => {
  const comSenha = (valor) => {
    loginPage.preencher(email, valor).enviar();
    navegacao.esperarMenu(TEMPO_CARGA_APP);
  };
  if (senha) return cy.then(() => comSenha(senha));
  return cy.fixture('credenciais').then((c) => comSenha(c.senhaPadrao));
});

Cypress.Commands.add('irPara', (secao) => {
  navegacao.abrir(secao);
  const tela = telas[secao];
  if (tela) tela.esperarTela();
});
