const seletores = {
  email: 'login-email',
  senha: 'login-senha',
  entrar: 'login-entrar',
  erro: 'login-erro',
};

export const loginPage = {
  seletores,

  campoEmail: () => cy.porIdentificador(seletores.email),
  campoSenha: () => cy.porIdentificador(seletores.senha),
  botaoEntrar: () => cy.porIdentificador(seletores.entrar),
  erro: () => cy.porIdentificador(seletores.erro),

  esperarTela(opcoes = {}) {
    return cy.porIdentificador(seletores.email, opcoes).should('exist');
  },

  preencher(email, senha) {
    cy.digitar(seletores.email, email);
    cy.digitar(seletores.senha, senha);
    return this;
  },

  enviar() {
    this.botaoEntrar().click();
    return this;
  },

  deveMostrarErro(padrao) {
    this.erro().should('exist').invoke('text').should('match', padrao);
    return this;
  },

  naoDeveMostrarErro() {
    cy.naoExiste(seletores.erro);
    return this;
  },

  naoDeveEstarVisivel() {
    cy.naoExiste(seletores.email);
    return this;
  },
};
