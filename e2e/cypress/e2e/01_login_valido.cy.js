describe('CT-E2E-01 Login com credenciais validas', () => {
  let cenario;

  before(() => {
    cy.semearEmpresa().then((c) => {
      cenario = c;
    });
  });

  it('autentica o engenheiro e abre o painel da empresa', () => {
    cy.abrirApp();
    cy.entrarNaTela(cenario.emailEngenheiro);

    cy.get('[data-cy=nav-painel]', { timeout: 30000 }).should('exist');
    cy.get('[data-cy=login-email]').should('not.exist');
    cy.get('[data-cy=painel-total-itens]').should('exist');
    cy.get('[data-cy=login-erro]').should('not.exist');
  });
});
