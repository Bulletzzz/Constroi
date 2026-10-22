const seletores = {
  busca: 'estoque-busca',
  linha: 'estoque-linha',
  vazio: 'estoque-vazio',
};

export const estoquePage = {
  seletores,

  busca: (opcoes = {}) => cy.porIdentificador(seletores.busca, opcoes),

  esperarTela(opcoes = {}) {
    return cy.porIdentificador(seletores.busca, opcoes).should('exist');
  },

  naoDeveEstarVisivel() {
    cy.naoExiste(seletores.busca);
    return this;
  },
};
