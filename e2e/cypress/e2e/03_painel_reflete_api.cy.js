function indicador(identificador) {
  return cy
    .get(`[data-cy=${identificador}]`, { timeout: 60000 })
    .invoke('text');
}

describe('CT-E2E-03 Painel reflete os pedidos registrados na API', () => {
  let cenario;

  before(() => {
    cy.semearEmpresa().then((c) => {
      cenario = c;
    });
  });

  it('sai de zero requisicoes pendentes para duas apos criar dois pedidos', () => {
    cy.abrirApp();
    cy.entrarNaTela(cenario.emailEngenheiro);

    cy.get('[data-cy=nav-painel]', { timeout: 30000 }).should('exist');
    indicador('painel-requisicoes-pendentes').should('match', /\b0\b/);

    cy.criarPedido(cenario, 2).its('status').should('eq', 201);
    cy.criarPedido(cenario, 3).its('status').should('eq', 201);

    cy.get('[data-cy=nav-estoque]').click();
    cy.get('[data-cy=estoque-busca]', { timeout: 30000 }).should('exist');
    cy.get('[data-cy=nav-painel]').click();

    cy.get('[data-cy=painel-requisicoes-pendentes]', { timeout: 60000 }).should(
      'exist',
    );
    indicador('painel-requisicoes-pendentes').should('match', /\b2\b/);
  });
});
