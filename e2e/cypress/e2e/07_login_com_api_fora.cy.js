import { loginPage } from '../pages/login.page';
import { navegacao } from '../pages/navegacao.page';
import { TEMPO_CARGA_APP } from '../support/comandos';

describe('CT-E2E-07 Login quando a API falha', () => {
  let cenario;
  let credenciais;

  before(() => {
    cy.fixture('credenciais').then((c) => {
      credenciais = c;
    });
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('avisa o usuario e nao deixa entrar quando a API responde erro', () => {
    cy.intercept('POST', '**/login*', {
      statusCode: 503,
      body: { erro: 'Servico indisponivel. Tente novamente.' },
    }).as('loginFora');

    cy.abrirApp();
    loginPage
      .preencher(cenario.emailEngenheiro, credenciais.senhaPadrao)
      .enviar();
    cy.wait('@loginFora');

    loginPage.erro(TEMPO_CARGA_APP).should('exist');
    loginPage.esperarTela();
    navegacao.naoDeveOferecer('painel');
  });
});
