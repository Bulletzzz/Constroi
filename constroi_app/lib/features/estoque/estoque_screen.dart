import '../../core/catalogo/opcoes.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import '../painel/painel_model.dart';
import '../painel/painel_service.dart';
import 'baixar_arquivo.dart';
import 'estoque_service.dart';
import 'exportacao.dart';
import 'item_estoque.dart';

const _fundo = Color(0xFFF2F2F2);
const _tinta = Color(0xFF1A1C1C);
const _destaque = Color(0xFFFFD700);
const _perigo = Color(0xFFBA1A1A);
const _perigoFundo = Color(0xFFFFDAD6);
const _linhaPar = Color(0xFFF9F9F9);
const _separador = Color(0xFFE2E2E2);
const _rotulo = Color(0xFF4D4732);
const _dica = Color(0xFF6B7280);
const _apoio = Color(0xFF5E5E5E);

TextStyle _mini(Color cor, [double espaco = 1.2]) => TextStyle(
  color: cor,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: espaco,
);

class EstoqueScreen extends StatefulWidget {
  const EstoqueScreen({
    super.key,
    required this.service,
    required this.perfil,
    this.painel,
    this.obraId,
    this.buscaInicial,
    this.saldoInicial = FiltroDeSaldo.todos,
    this.aoCadastrar,
  });

  final EstoqueService service;
  final PainelService? painel;
  final PerfilUsuario perfil;
  final int? obraId;
  final String? buscaInicial;
  final FiltroDeSaldo saldoInicial;
  final Future<void> Function(BuildContext)? aoCadastrar;

  @override
  State<EstoqueScreen> createState() => _EstoqueScreenState();
}

class _EstoqueScreenState extends State<EstoqueScreen> {
  final _busca = TextEditingController();
  final _inicioDaTabela = GlobalKey();
  final _itens = <ItemEstoque>[];

  Timer? _aguardandoDigitacao;
  int _consultaAtual = 0;
  IndicadoresPainel? _indicadores;
  final _obras = <ObraPainel>[];
  final _categoriasVistas = <int, String>{};
  int? _obra;
  int? _categoria;
  late FiltroDeSaldo _saldo = widget.saldoInicial;
  bool _carregando = true;
  bool _exportando = false;
  bool _temMais = false;
  int _pagina = 0;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _busca.text = widget.buscaInicial ?? '';
    unawaited(_carregarIndicadores());
    _buscar();
  }

  @override
  void dispose() {
    _aguardandoDigitacao?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    _aguardandoDigitacao?.cancel();
    final consulta = ++_consultaAtual;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final pagina = await widget.service.listar(
        obraId: _obraAtual,
        busca: _busca.text,
        categoriaId: _categoria,
        saldo: _saldo,
        deslocamento: _pagina * limitePadrao,
      );
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _itens
          ..clear()
          ..addAll(pagina.itens);
        for (final item in pagina.itens) {
          final id = item.categoriaId;
          if (id != null) {
            _categoriasVistas[id] = item.categoriaNome ?? 'Categoria $id';
          }
        }
        _temMais = pagina.temMais;
        _carregando = false;
        _erro = null;
      });
    } on ApiException catch (erro) {
      _registrarFalha(consulta, erro.message);
    } catch (_) {
      _registrarFalha(
        consulta,
        'Não foi possível falar com o servidor. Confira a conexão.',
      );
    }
  }

  Future<void> _irParaPagina(int destino) async {
    if (destino < 0 || destino == _pagina) return;
    setState(() => _pagina = destino);
    await _buscar();
    final inicio = _inicioDaTabela.currentContext;
    if (inicio != null && inicio.mounted) {
      await Scrollable.ensureVisible(inicio, duration: Duration.zero);
    }
  }

  void _refazerBusca() {
    _pagina = 0;
    _buscar();
  }

  Future<void> _carregarIndicadores() async {
    final painel = widget.painel;
    if (painel == null) return;
    final alvo = _obraAtual;
    try {
      final dados = await painel.carregar(obraId: alvo);
      if (!mounted || alvo != _obraAtual) return;
      setState(() {
        _indicadores = dados.indicadores;
        if (dados.obras.isNotEmpty) {
          _obras
            ..clear()
            ..addAll(dados.obras);
        }
      });
    } catch (_) {
      if (!mounted || alvo != _obraAtual) return;
      setState(() => _indicadores = null);
    }
  }

  int? get _obraAtual => widget.obraId ?? _obra;

  String _detalheDaLinha(ItemEstoque item) =>
      _obraAtual != null ? '' : _nomeDeObra(item.obraId);

  String _saldoEmTexto(ItemEstoque item) {
    final quantidade = formatarQuantidade(item.quantidade);
    return '$quantidade ${unidadeParaQuantidade(item.unidade, item.quantidade)}'
        .trim();
  }

  Widget _saldoDaLinha(ItemEstoque item) {
    final zerado = num.tryParse(item.quantidade) == 0;
    return Expanded(
      flex: 2,
      child: Semantics(
        identifier: 'estoque-saldo',
        label: '${_saldoEmTexto(item)} de ${item.produtoNome}',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                zerado ? 'SEM SALDO' : _saldoEmTexto(item),
                style: TextStyle(
                  color: item.baixo ? _perigo : _tinta,
                  fontSize: zerado ? 13 : 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'mín. ${formatarQuantidade(item.estoqueMinimo)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: item.baixo ? _perigo : _apoio,
                fontSize: 10,
                fontWeight: item.baixo ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nomeDeObra(int id) {
    for (final obra in _obras) {
      if (obra.id == id) return obra.nome;
    }
    return 'Obra $id';
  }

  String get _nomeDaObra {
    final atual = _obraAtual;
    if (atual == null) return 'Todas as obras';
    for (final obra in _obras) {
      if (obra.id == atual) return obra.nome;
    }
    return 'Obra $atual';
  }

  String _numero(int? valor) => valor == null ? '—' : '$valor';

  void _registrarFalha(int consulta, String mensagem) {
    if (!mounted || consulta != _consultaAtual) return;
    setState(() {
      _erro = mensagem;
      _carregando = false;
    });
  }

  Future<void> _atualizarTudo() async {
    await Future.wait([_carregarIndicadores(), _buscar()]);
  }

  void _digitou(String _) {
    _aguardandoDigitacao?.cancel();
    _aguardandoDigitacao = Timer(
      const Duration(milliseconds: 400),
      _refazerBusca,
    );
  }

  List<DropdownMenuItem<int?>> get _categorias {
    final nomes = _categoriasVistas.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('Todos os materiais'),
      ),
      for (final e in nomes)
        DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    appBar: AppHeader(perfil: widget.perfil),
    bottomNavigationBar: AppBottomNavigation(
      rotaAtual: AppRoute.estoque,
      perfil: widget.perfil,
    ),
    body: RefreshIndicator(
      onRefresh: _atualizarTudo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'INVENTÁRIO DE MATERIAIS',
            style: TextStyle(
              color: _tinta,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          _seletorDeObra(),
          const SizedBox(height: 18),
          _acoes(),
          if (widget.perfil.possuiNivel(PerfilUsuario.engenheiro)) ...[
            const SizedBox(height: 12),
            Semantics(
              identifier: 'estoque-importar-nfe',
              child: _botao(
                rotulo: 'IMPORTAR NF-e / ANEXAR XML',
                icone: Icons.upload_file,
                aoTocar: () async {
                  await Navigator.of(
                    context,
                  ).pushNamed(AppRoute.importacaoNfe.caminho);
                  if (mounted) await _atualizarTudo();
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(height: 2, color: _tinta),
          const SizedBox(height: 16),
          if (widget.aoCadastrar != null &&
              widget.perfil.possuiNivel(PerfilUsuario.engenheiro)) ...[
            _botaoDeCadastro(),
            const SizedBox(height: 16),
          ],
          _campoDeBusca(),
          const SizedBox(height: 16),
          _filtroDeCategoria(),
          const SizedBox(height: 16),
          _filtroDeSaldo(),
          const SizedBox(height: 16),
          Container(height: 2, color: _tinta),
          const SizedBox(height: 14),
          _tabela(key: _inicioDaTabela),
          const SizedBox(height: 24),
          _cartaoResumo(
            rotulo: 'ITENS MONITORADOS',
            identificador: 'estoque-resumo-itens',
            valor: _numero(_indicadores?.totalItens),
            icone: Icons.inventory_2_outlined,
            aoTocar: () => _aplicarSaldo(FiltroDeSaldo.todos),
          ),
          const SizedBox(height: 16),
          _cartaoResumo(
            rotulo: 'RUPTURAS CRÍTICAS',
            identificador: 'estoque-resumo-rupturas',
            valor: _numero(_indicadores?.rupturasCriticas),
            icone: Icons.warning_rounded,
            alerta: true,
            aoTocar: () => _aplicarSaldo(FiltroDeSaldo.zerado),
          ),
          const SizedBox(height: 16),
          _cartaoResumo(
            rotulo: 'ENTREGAS PENDENTES',
            identificador: 'estoque-resumo-pendentes',
            valor: _numero(_indicadores?.requisicoesPendentes),
            icone: Icons.local_shipping_outlined,
            aoTocar: () => Navigator.of(context).pushReplacementNamed(
              AppRoute.requisicoes.caminho,
              arguments: {'obra_id': _obraAtual},
            ),
          ),
        ],
      ),
    ),
  );

  Widget _seletorDeObra() {
    if (widget.obraId != null || _obras.isEmpty) {
      return Text(
        _nomeDaObra,
        style: const TextStyle(color: _apoio, fontSize: 15),
      );
    }
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 18, color: _apoio),
        const SizedBox(width: 6),
        Flexible(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              dropdownColor: Colors.white,
              value: _obra,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: _apoio),
              style: const TextStyle(color: _apoio, fontSize: 15),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todas as obras'),
                ),
                for (final obra in _obras)
                  DropdownMenuItem<int?>(
                    value: obra.id,
                    child: Text(obra.nome, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (valor) {
                setState(() {
                  _obra = valor;
                  _categoriasVistas.clear();
                  _categoria = null;
                });
                unawaited(_carregarIndicadores());
                _refazerBusca();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _acoes() => Semantics(
    identifier: 'estoque-exportar',
    button: true,
    child: _botao(
      rotulo: _exportando ? 'EXPORTANDO...' : 'EXPORTAR',
      icone: Icons.download,
      aoTocar: _exportando ? null : _exportar,
    ),
  );

  Future<void> _exportar() async {
    if (_itens.isEmpty) {
      _avisar('Não há itens para exportar.');
      return;
    }
    setState(() => _exportando = true);
    try {
      final recado = await baixarTexto(
        nomeDoArquivo(DateTime.now()),
        csvDoEstoque(_itens),
      );
      if (!mounted) return;
      setState(() => _exportando = false);
      _avisar(recado);
    } catch (_) {
      if (!mounted) return;
      setState(() => _exportando = false);
      _avisar('Não foi possível gerar a planilha.');
    }
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Widget _botao({
    required String rotulo,
    required IconData icone,
    required VoidCallback? aoTocar,
    bool destacado = false,
  }) => SizedBox(
    height: 44,
    child: Material(
      color: destacado ? _destaque : Colors.white,
      child: InkWell(
        onTap: aoTocar,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _tinta, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 18, color: _tinta),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  rotulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _tinta,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _botaoDeCadastro() => Semantics(
    identifier: 'estoque-novo-item',
    button: true,
    child: OutlinedButton.icon(
      onPressed: () async {
        await widget.aoCadastrar!(context);
        if (mounted) _refazerBusca();
      },
      icon: const Icon(Icons.add, size: 20),
      label: const Text(
        'NOVO ITEM',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _tinta,
        side: const BorderSide(color: _tinta, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: const RoundedRectangleBorder(),
      ),
    ),
  );

  Widget _campoDeBusca() => Container(
    height: 44,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _tinta, width: 2),
    ),
    child: Row(
      children: [
        const SizedBox(width: 13),
        const Icon(Icons.search, size: 20, color: _tinta),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            identifier: 'estoque-busca',
            textField: true,
            child: TextField(
              controller: _busca,
              onChanged: _digitou,
              onSubmitted: (_) => _refazerBusca(),
              style: const TextStyle(color: _tinta, fontSize: 13),
              decoration: const InputDecoration.collapsed(
                hintText: 'Buscar SKU ou nome',
                hintStyle: TextStyle(color: _dica, fontSize: 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );

  Widget _filtroDeCategoria() => Row(
    children: [
      Text('CATEGORIA:', style: _mini(_rotulo)),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              dropdownColor: Colors.white,
              value: _categoria,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: _tinta),
              style: const TextStyle(color: _tinta, fontSize: 13),
              items: _categorias,
              onChanged: (valor) {
                setState(() => _categoria = valor);
                _refazerBusca();
              },
            ),
          ),
        ),
      ),
    ],
  );

  Widget _filtroDeSaldo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('SALDO:', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final filtro in FiltroDeSaldo.values) _chipDeSaldo(filtro),
        ],
      ),
    ],
  );

  Widget _chipDeSaldo(FiltroDeSaldo filtro) {
    final ativo = _saldo == filtro;
    return Semantics(
      identifier: 'estoque-filtro-${filtro.name}',
      button: true,
      selected: ativo,
      child: InkWell(
        onTap: ativo ? null : () => _aplicarSaldo(filtro),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: ativo ? _tinta : Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: Text(
            filtro.rotulo,
            style: _mini(ativo ? Colors.white : _tinta),
          ),
        ),
      ),
    );
  }

  Widget _tabela({Key? key}) => Container(
    key: key,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _tinta, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          color: _fundo,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(width: 48, child: Text('STS', style: _mini(_rotulo, 1))),
              SizedBox(
                width: 104,
                child: Text('SKU / ID', style: _mini(_rotulo, 1)),
              ),
              Expanded(
                flex: 3,
                child: Text('DESCRIÇÃO', style: _mini(_rotulo, 1)),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'SALDO',
                  textAlign: TextAlign.right,
                  style: _mini(_rotulo, 1),
                ),
              ),
            ],
          ),
        ),
        Container(height: 2, color: _tinta),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(_tinta),
              ),
            ),
          )
        else if (_erro != null)
          _aviso(_erro!, aoTentar: _buscar)
        else if (_itens.isEmpty)
          Semantics(
            identifier: 'estoque-vazio',
            child: _aviso('Nenhum material encontrado com esses filtros.'),
          )
        else ...[
          for (var i = 0; i < _itens.length; i++) _linha(_itens[i], i.isOdd),
          if (_temMais || _pagina > 0) _paginacao(),
        ],
      ],
    ),
  );

  Widget _linha(ItemEstoque item, bool alternada) => Semantics(
    identifier: 'estoque-linha',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: alternada ? _linhaPar : Colors.white,
        border: const Border(bottom: BorderSide(color: _separador)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              color: item.baixo ? _perigo : _tinta,
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 35,
              child: Semantics(
                label: item.baixo
                    ? 'No mínimo ou abaixo (${item.estoqueMinimo})'
                    : 'Saldo normal',
                child: Icon(
                  item.baixo ? Icons.warning_rounded : Icons.square_rounded,
                  size: item.baixo ? 18 : 12,
                  color: item.baixo ? _perigo : _tinta,
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                item.identificacao,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _tinta,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.produtoNome,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _tinta, fontSize: 13),
                  ),
                  if (_detalheDaLinha(item).isNotEmpty)
                    Text(
                      _detalheDaLinha(item),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _apoio, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _saldoDaLinha(item),
            const SizedBox(width: 12),
          ],
        ),
      ),
    ),
  );

  Widget _aviso(String texto, {Future<void> Function()? aoTentar}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
    child: Column(
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _apoio, fontSize: 13, height: 1.4),
        ),
        if (aoTentar != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => aoTentar(),
            child: Text('TENTAR DE NOVO', style: _mini(_tinta)),
          ),
        ],
      ],
    ),
  );

  Widget _paginacao() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _tinta, width: 2)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Semantics(
          identifier: 'estoque-pagina-anterior',
          button: true,
          child: TextButton(
            onPressed: _pagina == 0 ? null : () => _irParaPagina(_pagina - 1),
            child: Text('ANTERIOR', style: _mini(_tinta)),
          ),
        ),
        Text('PÁGINA ${_pagina + 1}', style: _mini(_rotulo)),
        Semantics(
          identifier: 'estoque-pagina-proxima',
          button: true,
          child: TextButton(
            onPressed: !_temMais ? null : () => _irParaPagina(_pagina + 1),
            child: Text('PRÓXIMA', style: _mini(_tinta)),
          ),
        ),
      ],
    ),
  );

  Widget _cartaoResumo({
    required String rotulo,
    required String valor,
    required IconData icone,
    required String identificador,
    bool alerta = false,
    VoidCallback? aoTocar,
  }) => Semantics(
    identifier: identificador,
    button: aoTocar != null,
    child: InkWell(
      onTap: aoTocar,
      child: Container(
        decoration: BoxDecoration(
          color: alerta ? _perigoFundo : _linhaPar,
          border: Border.all(color: _separador),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: alerta ? _perigo : _tinta),
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 22, 22, 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rotulo, style: _mini(_rotulo)),
                        const SizedBox(height: 10),
                        Text(
                          valor,
                          style: TextStyle(
                            color: alerta ? _perigo : _tinta,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(icone, size: 20, color: alerta ? _perigo : _tinta),
                  if (aoTocar != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: alerta ? _perigo : _tinta,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _aplicarSaldo(FiltroDeSaldo filtro) {
    if (_saldo == filtro) return;
    setState(() => _saldo = filtro);
    _refazerBusca();
  }
}
