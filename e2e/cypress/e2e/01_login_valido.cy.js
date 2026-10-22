import { loginPage } from '../pages/login.page';
import { navegacao } from '../pages/navegacao.page';
import { painelPage } from '../pages/painel.page';

describe('CT-E2E-01 Login com credenciais validas', () => {
  let cenario;

  before(() => {
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('autentica o engenheiro e abre o painel da empresa', () => {
    cy.abrirApp();
    cy.entrarComo(cenario.emailEngenheiro);

    navegacao.deveOferecer('painel');
    loginPage.naoDeveEstarVisivel();
    painelPage.esperarTela();
    loginPage.naoDeveMostrarErro();
  });
});
