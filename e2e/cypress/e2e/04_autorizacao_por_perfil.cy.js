import { navegacao } from '../pages/navegacao.page';

describe('CT-E2E-04 Navegacao respeita o perfil do usuario', () => {
  let cenario;

  before(() => {
    cy.semearCenario().then((c) => {
      cenario = c;
    });
  });

  it('mostra Custos para o engenheiro e esconde do pedreiro', () => {
    cy.abrirApp();
    cy.entrarComo(cenario.emailEngenheiro);

    navegacao.deveOferecer('painel', 'custos', 'estoque');
  });

  it('nao oferece Custos ao pedreiro, que mantem as rotas do seu nivel', () => {
    cy.abrirApp();
    cy.entrarComo(cenario.emailPedreiro);

    navegacao.deveOferecer('painel', 'estoque');
    navegacao.naoDeveOferecer('custos');
  });
});
