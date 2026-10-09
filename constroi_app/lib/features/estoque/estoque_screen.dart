import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import '../painel/painel_model.dart';
import '../painel/painel_service.dart';
import 'estoque_service.dart';
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
    this.contexto,
  });

  final EstoqueService service;
  final PainelService? painel;
  final PerfilUsuario perfil;
  final int? obraId;
  final String? contexto;

  @override
  State<EstoqueScreen> createState() => _EstoqueScreenState();
}

class _EstoqueScreenState extends State<EstoqueScreen> {
  final _busca = TextEditingController();
  final _itens = <ItemEstoque>[];

  Timer? _aguardandoDigitacao;
  int _consultaAtual = 0;
  IndicadoresPainel? _indicadores;
  final _obras = <ObraPainel>[];
  final _categoriasVistas = <int, String>{};
  int? _obra;
  int? _categoria;
  bool _somenteBaixo = false;
  bool _carregando = true;
  bool _carregandoMais = false;
  bool _temMais = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    unawaited(_carregarIndicadores());
    _buscar();
  }

  @override
  void dispose() {
    _aguardandoDigitacao?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _buscar({bool continuando = false}) async {
    final consulta = ++_consultaAtual;
    setState(() {
      if (continuando) {
        _carregandoMais = true;
      } else {
        _carregando = true;
        _erro = null;
      }
    });

    try {
      final pagina = await widget.service.listar(
        obraId: _obraAtual,
        busca: _busca.text,
        categoriaId: _categoria,
        somenteBaixo: _somenteBaixo,
        deslocamento: continuando ? _itens.length : 0,
      );
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        if (!continuando) _itens.clear();
        _itens.addAll(pagina.itens);
        for (final item in pagina.itens) {
          final id = item.categoriaId;
          if (id != null) {
            _categoriasVistas[id] = item.categoriaNome ?? 'Categoria $id';
          }
        }
        _temMais = pagina.temMais;
        _carregando = false;
        _carregandoMais = false;
        _erro = null;
      });
    } on ApiException catch (erro) {
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _erro = erro.message;
        _carregando = false;
        _carregandoMais = false;
      });
    } catch (_) {
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _erro = 'Não foi possível falar com o servidor. Confira a conexão.';
        _carregando = false;
        _carregandoMais = false;
      });
    }
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

  void _digitou(String _) {
    _aguardandoDigitacao?.cancel();
    _aguardandoDigitacao = Timer(
      const Duration(milliseconds: 400),
      () => _buscar(),
    );
  }

  List<DropdownMenuItem<int?>> get _categorias {
    final nomes = _categoriasVistas.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const DropdownMenuItem<int?>(value: null, child: Text('Todos os materiais')),
      for (final e in nomes)
        DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
    ];
  }

  void _emBreve(String recurso) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$recurso ainda não está disponível.')),
    );
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
      onRefresh: _buscar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'INVENTÁRIO DE MATERIAIS',
              style: TextStyle(
                color: _tinta,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _seletorDeObra(),
          const SizedBox(height: 18),
          _acoes(),
          const SizedBox(height: 16),
          Container(height: 2, color: _tinta),
          const SizedBox(height: 16),
          _campoDeBusca(),
          const SizedBox(height: 16),
          _filtroDeCategoria(),
          const SizedBox(height: 16),
          _caixaEstoqueBaixo(),
          const SizedBox(height: 16),
          Container(height: 2, color: _tinta),
          const SizedBox(height: 14),
          _tabela(),
          const SizedBox(height: 24),
          _cartaoResumo(
            rotulo: 'ITENS MONITORADOS',
            valor: _numero(_indicadores?.totalItens),
            icone: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 16),
          _cartaoResumo(
            rotulo: 'RUPTURAS CRÍTICAS',
            valor: _numero(_indicadores?.rupturasCriticas),
            icone: Icons.warning_rounded,
            alerta: true,
          ),
          const SizedBox(height: 16),
          _cartaoResumo(
            rotulo: 'ENTREGAS PENDENTES',
            valor: _numero(_indicadores?.requisicoesPendentes),
            icone: Icons.local_shipping_outlined,
          ),
        ],
      ),
    ),
  );

  Widget _seletorDeObra() {
    if (widget.obraId != null || _obras.isEmpty) {
      return Text(
        widget.contexto ?? _nomeDaObra,
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
                _buscar();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _acoes() => Row(
    children: [
      Expanded(
        child: _botao(
          rotulo: 'EXPORTAR',
          icone: Icons.download,
          aoTocar: () => _emBreve('A exportação'),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: _botao(
          rotulo: 'NOVO ITEM',
          icone: Icons.add,
          destacado: true,
          aoTocar: () => _emBreve('O cadastro de item'),
        ),
      ),
    ],
  );

  Widget _botao({
    required String rotulo,
    required IconData icone,
    required VoidCallback aoTocar,
    bool destacado = false,
  }) => SizedBox(
    height: 44,
    child: Material(
      color: destacado ? _destaque : Colors.white,
      child: InkWell(
        onTap: aoTocar,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: _tinta, width: 2)),
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
          child: TextField(
            controller: _busca,
            onChanged: _digitou,
            onSubmitted: (_) => _buscar(),
            style: const TextStyle(color: _tinta, fontSize: 13),
            decoration: const InputDecoration.collapsed(
              hintText: 'Buscar SKU ou nome',
              hintStyle: TextStyle(color: _dica, fontSize: 13),
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
              value: _categoria,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: _tinta),
              style: const TextStyle(color: _tinta, fontSize: 13),
              items: _categorias,
              onChanged: (valor) {
                setState(() => _categoria = valor);
                _buscar();
              },
            ),
          ),
        ),
      ),
    ],
  );

  Widget _caixaEstoqueBaixo() => Row(
    children: [
      SizedBox(
        width: 20,
        height: 20,
        child: Checkbox(
          value: _somenteBaixo,
          onChanged: (valor) {
            setState(() => _somenteBaixo = valor ?? false);
            _buscar();
          },
          fillColor: WidgetStateProperty.resolveWith(
            (estados) =>
                estados.contains(WidgetState.selected) ? _tinta : Colors.white,
          ),
          checkColor: Colors.white,
          side: const BorderSide(color: _tinta, width: 2),
          shape: const RoundedRectangleBorder(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
      const SizedBox(width: 11),
      Flexible(
        child: Text(
          'SOMENTE ESTOQUE BAIXO',
          overflow: TextOverflow.ellipsis,
          style: _mini(_tinta),
        ),
      ),
    ],
  );

  Widget _tabela() => Container(
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
              Expanded(child: Text('DESCRIÇÃO', style: _mini(_rotulo, 1))),
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
          _aviso('Nenhum material encontrado com esses filtros.')
        else ...[
          for (var i = 0; i < _itens.length; i++) _linha(_itens[i], i.isOdd),
          if (_temMais) _carregarMais(),
        ],
      ],
    ),
  );

  Widget _linha(ItemEstoque item, bool alternada) => DecoratedBox(
    decoration: BoxDecoration(
      color: alternada ? _linhaPar : Colors.white,
      border: const Border(bottom: BorderSide(color: _separador)),
    ),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            color: item.baixo ? _perigo : _tinta,
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 35,
            child: Icon(
              item.baixo ? Icons.warning_rounded : Icons.square_rounded,
              size: item.baixo ? 18 : 12,
              color: item.baixo ? _perigo : _tinta,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.produtoNome,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _tinta, fontSize: 13),
                ),
                if (_obraAtual == null)
                  Text(
                    _nomeDeObra(item.obraId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _apoio, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
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

  Widget _carregarMais() => SizedBox(
    height: 52,
    child: _carregandoMais
        ? const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(_tinta),
              ),
            ),
          )
        : TextButton(
            onPressed: () => _buscar(continuando: true),
            child: Text('CARREGAR MAIS', style: _mini(_tinta)),
          ),
  );

  Widget _cartaoResumo({
    required String rotulo,
    required String valor,
    required IconData icone,
    bool alerta = false,
  }) => Container(
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
            ],
          ),
        ),
      ],
    ),
  );
}
