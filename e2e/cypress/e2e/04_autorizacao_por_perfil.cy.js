describe('CT-E2E-04 Navegacao respeita o perfil do usuario', () => {
  let cenario;

  before(() => {
    cy.semearEmpresa().then((c) => {
      cenario = c;
    });
  });

  it('mostra Custos para o engenheiro e esconde do pedreiro', () => {
    cy.abrirApp();
    cy.entrarNaTela(cenario.emailEngenheiro);

    cy.get('[data-cy=nav-painel]', { timeout: 30000 }).should('exist');
    cy.get('[data-cy=nav-custos]').should('exist');
    cy.get('[data-cy=nav-estoque]').should('exist');
  });

  it('nao oferece Custos ao pedreiro, que mantem as rotas do seu nivel', () => {
    cy.abrirApp();
    cy.entrarNaTela(cenario.emailPedreiro);

    cy.get('[data-cy=nav-painel]', { timeout: 30000 }).should('exist');
    cy.get('[data-cy=nav-estoque]').should('exist');
    cy.get('[data-cy=nav-custos]').should('not.exist');
  });
});
