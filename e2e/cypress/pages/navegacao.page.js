const seletores = {
  painel: 'nav-painel',
  estoque: 'nav-estoque',
  custos: 'nav-custos',
  equipe: 'nav-equipe',
  requisicoes: 'nav-requisicoes',
};

export const navegacao = {
  seletores,

  item: (secao) => cy.porIdentificador(seletores[secao]),

  esperarMenu(opcoes = {}) {
    return cy.porIdentificador(seletores.painel, opcoes).should('exist');
  },

  abrir(secao) {
    this.item(secao).click();
    return this;
  },

  deveOferecer(...secoes) {
    secoes.forEach((secao) => this.item(secao).should('exist'));
    return this;
  },

  naoDeveOferecer(...secoes) {
    secoes.forEach((secao) => cy.naoExiste(seletores[secao]));
    return this;
  },
};
