describe('CT-E2E-02 Login com senha incorreta', () => {
  let cenario;

  before(() => {
    cy.semearEmpresa().then((c) => {
      cenario = c;
    });
  });

  it('recusa a entrada, informa o motivo e mantem a tela de login', () => {
    cy.abrirApp();
    cy.preencher('login-email', cenario.emailEngenheiro);
    cy.preencher('login-senha', 'SenhaErrada#9');
    cy.get('[data-cy=login-entrar]').click();

    cy.get('[data-cy=login-erro]', { timeout: 30000 })
      .should('exist')
      .invoke('text')
      .should('match', /inv[aá]lid/i);

    cy.get('[data-cy=login-email]').should('exist');
    cy.get('[data-cy=nav-painel]').should('not.exist');
  });
});
