import 'package:flutter/material.dart';

import '../../widgets/app_header.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../theme/app_theme.dart';
import 'painel_model.dart';
import 'painel_service.dart';

const _fundo = Color(0xFFF2F2F2);
const _tinta = AppTheme.background;
const _amarelo = AppTheme.accent;
const _cinza = Color(0xFF626262);
const _verde = Color(0xFF087D2C);

class AppHome extends StatefulWidget {
  const AppHome({
    super.key,
    required this.service,
    required this.perfil,
    required this.onSair,
  });
  final PainelService service;
  final PerfilUsuario perfil;
  final Future<void> Function() onSair;

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  final _busca = TextEditingController();
  PainelDados? _dados;
  List<ObraPainel> _obras = [];
  List<MovimentacaoPainel> _movimentos = [];
  int? _obraId;
  int _versao = 0;
  bool _carregando = true;
  bool _carregandoMais = false;
  String? _erro;
  String? _erroMais;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool mais = false}) async {
    final versao = ++_versao;
    final offset = mais ? _movimentos.length : 0;
    setState(() {
      _carregando = !mais;
      _carregandoMais = mais;
      _erro = null;
      _erroMais = null;
    });
    try {
      final dados = await widget.service.carregar(
        obraId: _obraId,
        offset: offset,
      );
      if (!mounted || versao != _versao) return;
      setState(() {
        _dados = dados;
        _obras = dados.obras;
        _movimentos = mais
            ? [..._movimentos, ...dados.movimentacoes]
            : dados.movimentacoes;
        _carregando = false;
        _carregandoMais = false;
      });
    } catch (_) {
      if (!mounted || versao != _versao) return;
      setState(() {
        if (mais) {
          _erroMais = 'Não foi possível carregar mais movimentações.';
        } else {
          _erro = _dados == null
              ? 'Não foi possível carregar o painel. Confira sua conexão e tente novamente.'
              : 'Não foi possível atualizar. Os dados abaixo são da última consulta.';
        }
        _carregando = false;
        _carregandoMais = false;
      });
    }
  }

  void _abrirEstoque() => Navigator.of(context).pushReplacementNamed(
    AppRoute.estoque.caminho,
    arguments: {'busca': _busca.text.trim(), 'obra_id': _obraId},
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: const ColorScheme.light(
        primary: _amarelo,
        onPrimary: _tinta,
        surface: _fundo,
        onSurface: _tinta,
      ),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: _tinta, displayColor: _tinta),
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _tinta, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _tinta, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    ),
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: _fundo,
        appBar: AppHeader(perfil: widget.perfil, onSair: widget.onSair),
        body: RefreshIndicator(
          color: _tinta,
          backgroundColor: _amarelo,
          onRefresh: _carregar,
          child: CustomScrollView(
            key: const ValueKey('painel-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'VISÃO GERAL\nDO ESTOQUE',
                            style: TextStyle(
                              fontSize: 36,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              color: _tinta,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _dados == null
                                ? 'Acompanhe os dados das suas obras'
                                : 'Atualizado às ${_hora(_dados!.atualizadoEm)} • Puxe para atualizar',
                            style: const TextStyle(color: _cinza),
                          ),
                          const SizedBox(height: 16),
                          if (_obras.isNotEmpty) ...[
                            DropdownButtonFormField<int>(
                              key: ValueKey(_obraId),
                              initialValue: _obraId,
                              isExpanded: true,
                              dropdownColor: _fundo,
                              style: const TextStyle(
                                color: _tinta,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Obra',
                                labelStyle: TextStyle(color: _cinza),
                              ),
                              items: [
                                const DropdownMenuItem<int>(
                                  child: Text('Todas as obras disponíveis'),
                                ),
                                for (final obra in _obras)
                                  DropdownMenuItem(
                                    value: obra.id,
                                    child: Text(
                                      obra.nome,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (id) {
                                setState(() {
                                  _obraId = id;
                                  _dados = null;
                                  _movimentos = [];
                                });
                                _carregar();
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final busca = TextField(
                                controller: _busca,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => _abrirEstoque(),
                                style: const TextStyle(
                                  color: _tinta,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Buscar no estoque...',
                                  hintStyle: const TextStyle(
                                    color: _cinza,
                                    fontSize: 12,
                                  ),
                                  prefixIcon: IconButton(
                                    tooltip: 'Buscar no estoque',
                                    onPressed: _abrirEstoque,
                                    icon: const Icon(
                                      Icons.search,
                                      color: _tinta,
                                    ),
                                  ),
                                ),
                              );
                              final nova = ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _amarelo,
                                  foregroundColor: _tinta,
                                  elevation: 0,
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    side: BorderSide(color: _tinta, width: 2),
                                  ),
                                ),
                                onPressed: () =>
                                    Navigator.of(context).pushReplacementNamed(
                                      AppRoute.requisicoes.caminho,
                                      arguments: {'obra_id': _obraId},
                                    ),
                                icon: const Icon(Icons.add),
                                label: const Text(
                                  'NOVA\nREQUISIÇÃO',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                              if (constraints.maxWidth < 320) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    busca,
                                    const SizedBox(height: 10),
                                    nova,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: busca),
                                  const SizedBox(width: 14),
                                  nova,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: _tinta, thickness: 2, height: 2),
                          const SizedBox(height: 16),
                          if (_erro != null)
                            _Mensagem(texto: _erro!, onTentar: _carregar),
                          if (_carregando && _dados == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 64),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(color: _tinta),
                                  SizedBox(height: 16),
                                  Text('Carregando painel...'),
                                ],
                              ),
                            ),
                          if (_carregando && _dados != null)
                            const LinearProgressIndicator(
                              color: _tinta,
                              backgroundColor: _amarelo,
                            ),
                          if (_dados != null) ..._conteudo(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNavigation(
          rotaAtual: AppRoute.painel,
          perfil: widget.perfil,
        ),
      ),
    ),
  );

  List<Widget> _conteudo() {
    final dados = _dados!;
    final indicadores = dados.indicadores;
    if (dados.obras.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Text(
            'Você ainda não tem obras disponíveis. Peça ao administrador para conferir seu vínculo.',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      _Indicador(
        titulo: 'TOTAL DE ITENS',
        valor: formatarNumero(indicadores.totalItens),
        apoio: 'Materiais distintos cadastrados no estoque',
        icone: Icons.inventory_2,
      ),
      _Indicador(
        titulo: 'RUPTURAS CRÍTICAS',
        valor: formatarNumero(indicadores.rupturasCriticas),
        apoio: indicadores.rupturasCriticas == 0
            ? 'Nenhum saldo zerado'
            : 'Saldos zerados • requer atenção',
        icone: Icons.warning_amber_rounded,
        destaque: true,
      ),
      _Indicador(
        titulo: 'REQUISIÇÕES PENDENTES',
        valor: formatarNumero(indicadores.requisicoesPendentes),
        apoio: widget.perfil == PerfilUsuario.pedreiro
            ? 'Suas requisições aguardando aprovação'
            : 'Aguardando aprovação nas obras selecionadas',
        icone: Icons.assignment_outlined,
      ),
      if (widget.perfil.possuiNivel(PerfilUsuario.engenheiro))
        _Indicador(
          titulo: 'VALOR ESTIMADO',
          valor: indicadores.valorEstimado == null
              ? 'Não informado'
              : 'R\$ ${formatarNumero(indicadores.valorEstimado!, casas: 2)}',
          apoio: indicadores.itensSemPreco > 0
              ? 'Parcial • ${indicadores.itensSemPreco} saldos sem preço informado'
              : 'Último preço registrado • ${indicadores.obrasAtivas} obras ativas',
          icone: Icons.payments_outlined,
        ),
      const SizedBox(height: 8),
      Container(
        color: _tinta,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'MOVIMENTAÇÕES\nRECENTES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (dados.temMais)
              TextButton(
                onPressed: _carregandoMais || _carregando
                    ? null
                    : () => _carregar(mais: true),
                child: const Text(
                  'VER TUDO →',
                  style: TextStyle(
                    color: _amarelo,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_movimentos.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'Nenhuma movimentação registrada para estas obras.',
            textAlign: TextAlign.center,
          ),
        )
      else ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text('ID', style: _rotuloTabela)),
              Expanded(flex: 4, child: Text('DESCRIÇÃO', style: _rotuloTabela)),
              Expanded(
                flex: 2,
                child: Text(
                  'AÇÃO',
                  textAlign: TextAlign.center,
                  style: _rotuloTabela,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'QTD',
                  textAlign: TextAlign.right,
                  style: _rotuloTabela,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: _tinta, height: 1),
        for (var i = 0; i < _movimentos.length; i++)
          _LinhaMovimento(movimento: _movimentos[i], alternada: i.isEven),
        const SizedBox(height: 8),
      ],
      if (_erroMais != null)
        _Mensagem(texto: _erroMais!, onTentar: () => _carregar(mais: true)),
      if (_carregandoMais)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(color: _tinta)),
        )
      else if (dados.temMais)
        OutlinedButton(
          onPressed: _carregando ? null : () => _carregar(mais: true),
          child: const Text('CARREGAR MAIS', style: TextStyle(color: _tinta)),
        ),
    ];
  }
}

const _rotuloTabela = TextStyle(
  color: Color(0xFF4D4732),
  fontSize: 9,
  fontWeight: FontWeight.w700,
);
String _hora(DateTime data) {
  final local = data.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.titulo,
    required this.valor,
    required this.apoio,
    required this.icone,
    this.destaque = false,
  });
  final String titulo;
  final String valor;
  final String apoio;
  final IconData icone;
  final bool destaque;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFF9F9F9),
      border: Border(
        top: BorderSide(color: destaque ? _amarelo : _tinta, width: 4),
        left: const BorderSide(color: Color(0xFFE5E5E5)),
        right: const BorderSide(color: Color(0xFFE5E5E5)),
        bottom: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  color: Color(0xFF4D4732),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              icone,
              color: destaque ? const Color(0xFF9B7200) : _tinta,
              size: 22,
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: const TextStyle(
              color: _tinta,
              fontSize: 38,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(apoio, style: const TextStyle(color: _cinza, fontSize: 11)),
      ],
    ),
  );
}

class _LinhaMovimento extends StatelessWidget {
  const _LinhaMovimento({required this.movimento, required this.alternada});
  final MovimentacaoPainel movimento;
  final bool alternada;

  @override
  Widget build(BuildContext context) {
    final entrada = movimento.acao == 'entrada';
    final saida = movimento.acao == 'saida';
    final quantidade = entrada
        ? '+${formatarNumero(movimento.quantidade)}'
        : saida
        ? '-${formatarNumero(movimento.quantidade.abs())}'
        : formatarNumero(movimento.quantidade);
    final data = movimento.data.toLocal();
    return Container(
      color: alternada ? Colors.white : const Color(0xFFF9F9F9),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              movimento.id,
              style: const TextStyle(color: _tinta, fontSize: 9),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movimento.produtoNome,
                    style: const TextStyle(color: _tinta, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${movimento.obraNome}\n${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} • ${_hora(data)}',
                    style: const TextStyle(color: _cinza, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: saida
                    ? _tinta
                    : entrada
                    ? Colors.white
                    : _amarelo,
                border: Border.all(color: _tinta),
              ),
              child: Text(
                entrada
                    ? 'ENTRADA'
                    : saida
                    ? 'SAÍDA'
                    : 'AJUSTE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: saida ? Colors.white : _tinta,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    quantidade,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: entrada ? _verde : _tinta,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    movimento.unidade,
                    style: const TextStyle(color: _cinza, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mensagem extends StatelessWidget {
  const _Mensagem({required this.texto, required this.onTentar});
  final String texto;
  final VoidCallback onTentar;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Color(0xFFFFF1D6),
      border: Border(left: BorderSide(color: _amarelo, width: 4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: const TextStyle(color: _tinta)),
        TextButton(
          onPressed: onTentar,
          child: const Text(
            'TENTAR NOVAMENTE',
            style: TextStyle(color: _tinta),
          ),
        ),
      ],
    ),
  );
}
