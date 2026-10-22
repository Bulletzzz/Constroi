const seletores = {
  totalItens: 'painel-total-itens',
  rupturas: 'painel-rupturas-criticas',
  estoqueBaixo: 'painel-estoque-baixo',
  requisicoes: 'painel-requisicoes-pendentes',
  valorEstimado: 'painel-valor-estimado',
};

export const painelPage = {
  seletores,

  indicador: (nome, opcoes = {}) =>
    cy.porIdentificador(seletores[nome], opcoes),

  esperarTela(opcoes = {}) {
    return cy.porIdentificador(seletores.totalItens, opcoes).should('exist');
  },

  deveMostrar(nome, numero) {
    this.indicador(nome)
      .invoke('text')
      .should('match', new RegExp(`\\b${numero}\\b`));
    return this;
  },
};
