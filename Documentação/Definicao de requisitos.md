# Definicao de requisitos

> Revisão de 08/11/2026: incluídos RF13 (Painel), RF14 (Custos), RF15 (Equipe) e RF16 (Logs),
> funcionalidades já implementadas que não tinham requisito. O PDF é gerado a partir deste arquivo.

## funcionais

- O administrador deve conseguir cadastrar a empresa
- Todos os usuarios devem conseguir fazer login
- O administrador deve ser capaz de manter todos os usuarios
- O administrador deve ter todos os poderes dos outros usuarios
- o engenheiro deve ter todos os poderes do pedreiro
- O pedreiro pode conferir o estoque
- O pedreiro deve poder fazer solicitacao de entrada de produtos
- O engenheiro pode aprovar ou recusar um pedido de produtos
- O engenheiro deve conseguir dar entrada de estoque sem nota fiscal
- O engenheiro deve conseguir anexar um xml e dar entrada em produtos
- O engenheiro deve conseguir anexar um xml a uma entrada ja existente
- O engenheiro deve conseguir manter um produto
- O engenheiro deve conseguir manter um equipamento
- O engenheiro deve poder registrar um emprestimo e devolucao de equipamento
- Todos os usuarios devem conseguir consultar o painel com os indicadores das obras
- O engenheiro deve conseguir consultar os custos e o orcamento de uma obra
- Todos os usuarios devem conseguir consultar a equipe de uma obra
- O administrador deve conseguir consultar o registro de alteracoes feitas pelos usuarios

## nao funcionais

- Toda comunicação entre aplicativo e servidor deve utilizar conexão criptografada
- Dados pessoais e sensíveis devem ser criptografados durante a transmissão e quando aplicável no armazenamento
- Senhas devem ser armazenadas exclusivamente utilizando algoritmo seguro de hash com salt e nunca em texto puro
- A política de senha deve exigir comprimento mínimo e impedir senhas comuns ou comprometidas Maiúsculas minúsculas números e símbolos podem ser exigidos mas o comprimento é mais importante
- O sistema deve bloquear ou limitar temporariamente novas tentativas após sucessivas falhas de login
- As sessões devem expirar após um período configurável de inatividade
- O sistema deve oferecer autenticação em dois fatores para administradores ao menos como opção
- Uma movimentação de estoque deve aparecer para os demais usuários conectados em até um segundo após sua confirmação em condições normais de conexão
- Consultas comuns devem responder em até dois segundos em condições normais de operação
- O sistema deve informar claramente quando o dispositivo estiver sem conexão ou com dados desatualizados
- O sistema deve evitar movimentações duplicadas quando uma requisição for reenviada devido a falhas de conexão
- Devem ser realizados backups automáticos e periódicos
- O processo de restauração dos backups deve ser testado periodicamente
- Deve ser estabelecida uma meta mensurável de disponibilidade como 99,5 por cento ao mês
- O aplicativo deve ser compatível com versões previamente definidas de Android e iOS
- A interface deve adaptar-se aos diferentes tamanhos e orientações de tela suportados
- O sistema deve oferecer mensagens de erro claras informando o problema e como corrigi-lo
- A interface deve considerar o uso em campo com botões adequados para toque alto contraste e fluxo simples
- O aplicativo deve seguir boas práticas de acessibilidade incluindo contraste redimensionamento de texto e identificação de elementos para leitores de tela

### Privacidade manutenção e confiabilidade

- O tratamento de dados pessoais deve considerar os princípios e obrigações aplicáveis da LGPD
- Valores de estoque e demais registros críticos devem manter consistência mesmo quando houver acessos simultâneos

## Requisitos funcionais

| ID | Nome | Descrição | Ator |
|---|---|---|---|
| RF01 | Cadastro de Empresa | O sistema deve permitir o cadastro dos dados da empresa. | Administrador |
| RF02 | Autenticação | O sistema deve permitir que todos os usuários realizem login seguro. | Todos |
| RF03 | Manutenção de Usuários | O sistema deve permitir gerenciar (cadastrar, visualizar, editar, inativar) todos os usuários. | Administrador |
| RF04 | Consulta de Estoque | O sistema deve permitir a visualização da disponibilidade e níveis de estoque. | Pedreiro |
| RF05 | Solicitação de Produtos | O sistema deve permitir solicitar a entrada (ou requisição) de produtos no estoque. | Pedreiro |
| RF06 | Avaliação de Pedidos | O sistema deve permitir aprovar ou recusar solicitações de produtos pendentes. | Engenheiro |
| RF07 | Entrada de Estoque Manual | O sistema deve permitir registrar entradas de produtos no estoque sem a exigência de uma Nota Fiscal. | Engenheiro |
| RF08 | Entrada via XML | O sistema deve permitir o upload de um arquivo XML para automatizar a entrada de produtos. | Engenheiro |
| RF09 | Anexar XML a Registro Existente | O sistema deve permitir vincular um arquivo XML a um registro de entrada previamente inserido no sistema. | Engenheiro |
| RF10 | Manutenção de Produtos | O sistema deve permitir o gerenciamento (cadastro, edição, visualização) do catálogo de produtos. | Engenheiro |
| RF11 | Manutenção de Equipamentos | O sistema deve permitir o gerenciamento do catálogo de equipamentos. | Engenheiro |
| RF12 | Controle de Empréstimos | O sistema deve permitir registrar a saída (empréstimo) e a devolução de equipamentos. | Engenheiro |
| RF13 | Painel da Obra | O sistema deve exibir indicadores de estoque, requisições pendentes e movimentações recentes das obras a que o usuário tem acesso. | Todos |
| RF14 | Consulta de Custos | O sistema deve permitir consultar custos, orçamento e lançamentos por obra e período. | Engenheiro |
| RF15 | Consulta de Equipe | O sistema deve permitir consultar as pessoas vinculadas a cada obra a que o usuário tem acesso e seus perfis. | Todos |
| RF16 | Consulta de Logs | O sistema deve permitir consultar o registro das alterações feitas pelos usuários da empresa, com filtro por usuário e período. | Administrador |

## Requisitos não funcionais

| ID | Categoria | Descrição |
|---|---|---|
| RNF01 | Segurança | Toda comunicação entre o aplicativo e o servidor deve utilizar conexão criptografada. |
| RNF02 | Segurança | Dados pessoais e sensíveis devem ser criptografados durante a transmissão e no armazenamento. |
| RNF03 | Segurança | Senhas devem ser armazenadas exclusivamente utilizando algoritmo seguro de hash com salt. |
| RNF04 | Segurança | A política de senhas deve exigir comprimento mínimo e bloquear senhas comuns, priorizando o comprimento à complexidade de caracteres. |
| RNF05 | Segurança | O sistema deve bloquear ou aplicar rate-limiting temporário após sucessivas falhas de login. |
| RNF06 | Segurança | As sessões ativas devem expirar automaticamente após um período configurável de inatividade. |
| RNF07 | Segurança | Oferecer Autenticação em Dois Fatores (2FA) de forma opcional para perfis administradores. |
| RNF08 | Desempenho | Atualizações de movimentação de estoque devem ser refletidas aos demais usuários em até 1 segundo (em condições normais de rede). |
| RNF09 | Desempenho | Consultas sistêmicas comuns devem responder em até 2 segundos em condições normais de operação. |
| RNF10 | Usabilidade | O sistema deve exibir alertas visuais claros quando o dispositivo perder conexão (offline) ou estiver com dados desatualizados. |
| RNF11 | Confiabilidade | A API deve evitar movimentações de estoque duplicadas no caso de reenvio de requisições por instabilidade de rede. |
| RNF12 | Disponibilidade | Devem ser realizados backups automatizados e periódicos, com processo de restauração testado periodicamente. |
| RNF13 | Disponibilidade | Estabelecer e monitorar a disponibilidade sistêmica de no mínimo 99,5% ao mês. |
| RNF14 | Compatibilidade | O aplicativo móvel deve ser retrocompatível com versões previamente documentadas de Android e iOS. |
| RNF15 | Usabilidade | A interface deve ser totalmente responsiva, adaptando-se a variados tamanhos e orientações de tela. |
| RNF16 | Usabilidade | As mensagens de erro devem ser claras, orientativas e sugerir como o usuário pode corrigir o problema. |
| RNF17 | Usabilidade / Campo | A interface deve ser desenhada para uso em canteiros de obra (alto contraste, botões grandes e fluxos simples e curtos). |
| RNF18 | Acessibilidade | Seguir diretrizes de acessibilidade (ex: WCAG), incluindo contraste, redimensionamento dinâmico de texto e suporte a leitores de tela. |
| RNF19 | Conformidade | O tratamento e a coleta de dados devem respeitar as diretrizes de privacidade estabelecidas pela LGPD. |
| RNF20 | Integridade (ACID) | Garantir consistência matemática e prevenção de concorrência ("Race Conditions") ao processar baixas ou entradas simultâneas de estoque. |
