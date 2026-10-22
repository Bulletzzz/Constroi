import { loginPage } from '../pages/login.page';
import { navegacao } from '../pages/navegacao.page';
import { estoquePage } from '../pages/estoque.page';

describe('CT-E2E-05 Rota protegida exige sessao', () => {
  let cenario;

  before(() => {
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('devolve ao login quando o estoque e aberto sem sessao', () => {
    cy.abrirApp('/estoque');

    loginPage.esperarTela();
    navegacao.naoDeveOferecer('estoque');
    estoquePage.naoDeveEstarVisivel();
  });

  it('libera o estoque pela navegacao depois da autenticacao', () => {
    cy.abrirApp();
    cy.entrarComo(cenario.emailEngenheiro);

    cy.irPara('estoque');
    loginPage.naoDeveEstarVisivel();
  });
});
