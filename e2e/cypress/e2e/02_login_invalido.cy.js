import { loginPage } from '../pages/login.page';
import { navegacao } from '../pages/navegacao.page';
import { TEMPO_CARGA_APP } from '../support/comandos';

describe('CT-E2E-02 Login com senha incorreta', () => {
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

  it('recusa a entrada, informa o motivo e mantem a tela de login', () => {
    cy.abrirApp();
    loginPage
      .preencher(cenario.emailEngenheiro, credenciais.senhaErrada)
      .enviar();

    loginPage.erro(TEMPO_CARGA_APP).should('exist');
    loginPage.deveMostrarErro(/inv[aá]lid/i);

    loginPage.esperarTela();
    navegacao.naoDeveOferecer('painel');
  });
});
