import { painelPage } from '../pages/painel.page';

describe('CT-E2E-06 Painel mostra o que a API responde', () => {
  let cenario;

  before(() => {
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('exibe os numeros da resposta, sem depender do estado do banco', () => {
    cy.intercept('GET', '**/painel*', { fixture: 'painel.json' }).as('painel');

    cy.abrirApp();
    cy.entrarComo(cenario.emailEngenheiro);
    cy.wait('@painel');

    cy.fixture('painel').then(({ indicadores }) => {
      painelPage.deveMostrar('totalItens', indicadores.total_itens);
      painelPage.deveMostrar('rupturas', indicadores.rupturas_criticas);
      painelPage.deveMostrar('requisicoes', indicadores.requisicoes_pendentes);
    });
  });
});
