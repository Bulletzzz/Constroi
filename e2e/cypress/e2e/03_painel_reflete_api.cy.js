import { painelPage } from '../pages/painel.page';

describe('CT-E2E-03 Painel reflete os pedidos registrados na API', () => {
  let cenario;

  before(() => {
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('sai de zero requisicoes pendentes para duas apos criar dois pedidos', () => {
    cy.abrirApp();
    cy.entrarComo(cenario.emailEngenheiro);

    painelPage.esperarTela();
    painelPage.deveMostrar('requisicoes', 0);

    cy.criarPedido(cenario, 2).its('status').should('eq', 201);
    cy.criarPedido(cenario, 3).its('status').should('eq', 201);

    cy.irPara('estoque');
    cy.irPara('painel');

    painelPage.deveMostrar('requisicoes', 2);
  });
});
