describe('CT-E2E-05 Rota protegida exige sessao', () => {
  let cenario;

  before(() => {
    cy.semearEmpresa().then((c) => {
      cenario = c;
    });
  });

  it('devolve ao login quando o estoque e aberto sem sessao', () => {
    cy.abrirApp('/estoque');

    cy.get('[data-cy=login-email]').should('exist');
    cy.get('[data-cy=nav-estoque]').should('not.exist');
    cy.get('[data-cy=estoque-busca]').should('not.exist');
  });

  it('libera o estoque pela navegacao depois da autenticacao', () => {
    cy.abrirApp();
    cy.entrarNaTela(cenario.emailEngenheiro);

    cy.get('[data-cy=nav-estoque]', { timeout: 30000 }).click();
    cy.get('[data-cy=estoque-busca]', { timeout: 30000 }).should('exist');
    cy.get('[data-cy=login-email]').should('not.exist');
  });
});
