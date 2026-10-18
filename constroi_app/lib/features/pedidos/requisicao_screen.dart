import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import 'pedido.dart';
import 'pedidos_service.dart';

const _fundo = Color(0xFFF2F2F2);
const _tinta = Color(0xFF1A1C1C);
const _destaque = Color(0xFFFFD700);
const _perigo = Color(0xFFBA1A1A);
const _separador = Color(0xFFE2E2E2);
const _rotulo = Color(0xFF4D4732);
const _dica = Color(0xFF6B7280);
const _apoio = Color(0xFF5E5E5E);
const _inativo = Color(0xFFBDBDBD);

TextStyle _mini(Color cor, [double espaco = 1.2]) => TextStyle(
  color: cor,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: espaco,
);

enum _Passo { dados, revisao, confirmar }

class RequisicaoScreen extends StatefulWidget {
  const RequisicaoScreen({
    super.key,
    required this.service,
    required this.perfil,
  });

  final PedidosService service;
  final PerfilUsuario perfil;

  @override
  State<RequisicaoScreen> createState() => _RequisicaoScreenState();
}

class _RequisicaoScreenState extends State<RequisicaoScreen> {
  final _quantidade = TextEditingController();
  final _local = TextEditingController();
  final _especificacoes = TextEditingController();

  _Passo _passo = _Passo.dados;
  List<ObraDisponivel> _obras = const [];
  List<ProdutoDoCatalogo> _catalogo = const [];
  int? _obraId;
  int? _produtoId;
  Urgencia _urgencia = Urgencia.padrao;
  bool _carregando = true;
  bool _enviando = false;
  String? _erroDeCarga;
  String? _erroDoFormulario;
  Pedido? _criado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _quantidade.dispose();
    _local.dispose();
    _especificacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroDeCarga = null;
    });
    try {
      final obras = await widget.service.obras();
      final catalogo = await widget.service.catalogo();
      if (!mounted) return;
      setState(() {
        _obras = obras;
        _catalogo = catalogo;
        _obraId = obras.length == 1 ? obras.first.id : _obraId;
        _carregando = false;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _erroDeCarga = erro.message;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erroDeCarga = 'Não foi possível carregar os materiais.';
        _carregando = false;
      });
    }
  }

  ProdutoDoCatalogo? get _produto => _produtoId == null
      ? null
      : _catalogo.where((p) => p.id == _produtoId).firstOrNull;

  String? _validar() {
    if (_obraId == null) return 'Escolha a obra da requisição.';
    if (_produtoId == null) return 'Escolha o material.';
    final texto = _quantidade.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(texto);
    if (valor == null || valor <= 0) {
      return 'Informe uma quantidade maior que zero.';
    }
    if (texto.contains('.') && texto.split('.').last.length > 2) {
      return 'A quantidade aceita no máximo duas casas decimais.';
    }
    if (_local.text.trim().length > 120) {
      return 'O local da obra aceita até 120 caracteres.';
    }
    if (_especificacoes.text.trim().length > 255) {
      return 'As especificações aceitam até 255 caracteres.';
    }
    return null;
  }

  void _avancar() {
    final erro = _validar();
    setState(() => _erroDoFormulario = erro);
    if (erro == null) setState(() => _passo = _Passo.revisao);
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erroDoFormulario = null;
    });
    try {
      final pedido = await widget.service.criar(
        obraId: _obraId!,
        produtoId: _produtoId!,
        quantidade: num.parse(_quantidade.text.trim().replaceAll(',', '.')),
        urgencia: _urgencia,
        localObra: _local.text,
        justificativa: _especificacoes.text,
      );
      if (!mounted) return;
      setState(() {
        _criado = pedido;
        _passo = _Passo.confirmar;
        _enviando = false;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _erroDoFormulario = erro.message;
        _enviando = false;
        _passo = _Passo.dados;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erroDoFormulario = 'Não foi possível enviar a requisição agora.';
        _enviando = false;
        _passo = _Passo.dados;
      });
    }
  }

  void _sair() {
    _novaRequisicao();
    Navigator.of(context).pushReplacementNamed(AppRoute.painel.caminho);
  }

  void _novaRequisicao() {
    setState(() {
      _quantidade.clear();
      _local.clear();
      _especificacoes.clear();
      _produtoId = null;
      _urgencia = Urgencia.padrao;
      _criado = null;
      _erroDoFormulario = null;
      _passo = _Passo.dados;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    appBar: const AppHeader(),
    bottomNavigationBar: AppBottomNavigation(
      rotaAtual: AppRoute.requisicoes,
      perfil: widget.perfil,
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          _titulo(),
          const SizedBox(height: 22),
          _trilha(),
          const SizedBox(height: 22),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_tinta),
                ),
              ),
            )
          else if (_erroDeCarga != null)
            _aviso(_erroDeCarga!, aoTentar: _carregar)
          else
            _cartaoDoPasso(),
        ],
      ),
    ),
  );

  Widget _titulo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'REQUISIÇÃO\nDE MATERIAL',
        style: TextStyle(
          color: _tinta,
          fontSize: 30,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Solicite os materiais necessários para a frente de obra.',
        style: TextStyle(color: _apoio, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 18),
      Container(height: 1.5, color: _tinta),
    ],
  );

  Widget _trilha() => Row(
    children: [
      for (final passo in _Passo.values) ...[
        _marcoDaTrilha(passo),
        if (passo != _Passo.confirmar)
          Expanded(
            child: Container(
              height: 1.5,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: passo.index < _passo.index ? _tinta : _separador,
            ),
          ),
      ],
    ],
  );

  Widget _marcoDaTrilha(_Passo passo) {
    final atual = passo == _passo;
    final concluido = passo.index < _passo.index;
    final numero = '0${passo.index + 1}';
    final rotulos = {
      _Passo.dados: 'DADOS',
      _Passo.revisao: 'REVISÃO',
      _Passo.confirmar: 'CONFIRMAR',
    };
    return Semantics(
      identifier: 'requisicao-passo-${passo.name}',
      selected: atual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: concluido || atual ? _tinta : Colors.white,
              border: Border.all(
                color: concluido || atual ? _tinta : _separador,
                width: 2,
              ),
            ),
            child: Text(
              numero,
              style: TextStyle(
                color: concluido || atual ? Colors.white : _inativo,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 76),
            child: Text(
              rotulos[passo]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mini(atual || concluido ? _tinta : _inativo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoDoPasso() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _tinta, width: 2),
    ),
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
    child: switch (_passo) {
      _Passo.dados => _formulario(),
      _Passo.revisao => _revisao(),
      _Passo.confirmar => _confirmacao(),
    },
  );

  Widget _formulario() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_obras.length != 1) ...[
        Text('OBRA', style: _mini(_rotulo)),
        const SizedBox(height: 8),
        _seletor<int>(
          identificador: 'requisicao-obra',
          valor: _obraId,
          dica: 'Selecione a obra',
          itens: [
            for (final obra in _obras)
              DropdownMenuItem(value: obra.id, child: Text(obra.nome)),
          ],
          aoMudar: (valor) => setState(() => _obraId = valor),
        ),
        const SizedBox(height: 18),
      ],
      Text('MATERIAL', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      _seletor<int>(
        identificador: 'requisicao-material',
        valor: _produtoId,
        dica: 'Selecione o material',
        itens: [
          for (final produto in _catalogo)
            DropdownMenuItem(
              value: produto.id,
              child: Text(
                produto.identificacao,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        aoMudar: (valor) => setState(() => _produtoId = valor),
      ),
      const SizedBox(height: 18),
      Text('QUANTIDADE', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      _campo(
        identificador: 'requisicao-quantidade',
        controlador: _quantidade,
        dica: 'ex.: 500',
        teclado: const TextInputType.numberWithOptions(decimal: true),
        sufixo: _produto?.unidade,
      ),
      const SizedBox(height: 18),
      Text('LOCAL DA OBRA', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      _campo(
        identificador: 'requisicao-local',
        controlador: _local,
        dica: 'ex.: Setor 4 - Fundação',
      ),
      const SizedBox(height: 18),
      Text('NÍVEL DE URGÊNCIA', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      _seletor<Urgencia>(
        identificador: 'requisicao-urgencia',
        valor: _urgencia,
        dica: 'Selecione',
        itens: [
          for (final urgencia in Urgencia.values)
            DropdownMenuItem(
              value: urgencia,
              child: Text('${urgencia.rotulo} (${urgencia.prazo})'),
            ),
        ],
        aoMudar: (valor) =>
            setState(() => _urgencia = valor ?? Urgencia.padrao),
      ),
      const SizedBox(height: 18),
      Text('ESPECIFICAÇÕES ADICIONAIS', style: _mini(_rotulo)),
      const SizedBox(height: 8),
      _campo(
        identificador: 'requisicao-especificacoes',
        controlador: _especificacoes,
        dica: 'Marca, especificação técnica ou instruções de entrega...',
        linhas: 3,
      ),
      if (_erroDoFormulario != null) ...[
        const SizedBox(height: 14),
        _mensagemDeErro(_erroDoFormulario!),
      ],
      const SizedBox(height: 22),
      Container(height: 1, color: _separador),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: _botao(
              identificador: 'requisicao-cancelar',
              rotulo: 'CANCELAR',
              aoTocar: _sair,
              primario: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _botao(
              identificador: 'requisicao-avancar',
              rotulo: 'REVISAR',
              aoTocar: _avancar,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _revisao() {
    final obra = _obras.where((o) => o.id == _obraId).firstOrNull;
    final local = _local.text.trim();
    final especificacoes = _especificacoes.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CONFIRA ANTES DE ENVIAR', style: _mini(_rotulo)),
        const SizedBox(height: 16),
        _linhaDeRevisao('MATERIAL', _produto?.identificacao ?? '—'),
        _linhaDeRevisao(
          'QUANTIDADE',
          '${_quantidade.text.trim()} ${_produto?.unidade ?? ''}'.trim(),
        ),
        _linhaDeRevisao('OBRA', obra?.nome ?? '—'),
        _linhaDeRevisao('LOCAL DA OBRA', local.isEmpty ? '—' : local),
        _linhaDeRevisao(
          'URGÊNCIA',
          '${_urgencia.rotulo} · ${_urgencia.prazo}',
        ),
        _linhaDeRevisao(
          'ESPECIFICAÇÕES',
          especificacoes.isEmpty ? '—' : especificacoes,
        ),
        if (_erroDoFormulario != null) ...[
          const SizedBox(height: 14),
          _mensagemDeErro(_erroDoFormulario!),
        ],
        const SizedBox(height: 22),
        Container(height: 1, color: _separador),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _botao(
                identificador: 'requisicao-voltar',
                rotulo: 'VOLTAR',
                aoTocar: _enviando
                    ? null
                    : () => setState(() => _passo = _Passo.dados),
                primario: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _botao(
                identificador: 'requisicao-enviar',
                rotulo: _enviando ? 'ENVIANDO...' : 'ENVIAR',
                aoTocar: _enviando ? null : _enviar,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _confirmacao() {
    final pedido = _criado;
    return Semantics(
      identifier: 'requisicao-protocolo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline, color: _tinta, size: 40),
          const SizedBox(height: 14),
          const Text(
            'REQUISIÇÃO ENVIADA',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _tinta,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'O engenheiro responsável vai avaliar o pedido.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _apoio, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              color: _fundo,
              border: Border.all(color: _tinta, width: 2),
            ),
            child: Column(
              children: [
                Text('PROTOCOLO', style: _mini(_rotulo)),
                const SizedBox(height: 8),
                SelectableText(
                  pedido?.protocolo ?? '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _tinta,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _botao(
            identificador: 'requisicao-nova',
            rotulo: 'NOVA REQUISIÇÃO',
            aoTocar: _novaRequisicao,
          ),
        ],
      ),
    );
  }

  Widget _linhaDeRevisao(String rotulo, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: _mini(_rotulo)),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(color: _tinta, fontSize: 14, height: 1.35),
        ),
      ],
    ),
  );

  Widget _campo({
    required String identificador,
    required TextEditingController controlador,
    required String dica,
    String? sufixo,
    int linhas = 1,
    TextInputType teclado = TextInputType.text,
  }) => Semantics(
    identifier: identificador,
    textField: true,
    child: Container(
      constraints: BoxConstraints(minHeight: linhas == 1 ? 44 : 88),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _tinta, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controlador,
              keyboardType: teclado,
              maxLines: linhas,
              enabled: !_enviando,
              style: const TextStyle(color: _tinta, fontSize: 13),
              decoration: InputDecoration.collapsed(
                hintText: dica,
                hintStyle: const TextStyle(color: _dica, fontSize: 13),
              ),
            ),
          ),
          if (sufixo != null) ...[
            const SizedBox(width: 10),
            Text(sufixo, style: _mini(_apoio)),
          ],
        ],
      ),
    ),
  );

  Widget _seletor<T>({
    required String identificador,
    required T? valor,
    required String dica,
    required List<DropdownMenuItem<T>> itens,
    required ValueChanged<T?> aoMudar,
  }) => Semantics(
    identifier: identificador,
    button: true,
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _tinta, width: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: valor,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: _tinta),
          hint: Text(
            dica,
            style: const TextStyle(color: _dica, fontSize: 13),
          ),
          style: const TextStyle(color: _tinta, fontSize: 13),
          onChanged: _enviando ? null : aoMudar,
          items: itens,
        ),
      ),
    ),
  );

  Widget _botao({
    required String identificador,
    required String rotulo,
    required VoidCallback? aoTocar,
    bool primario = true,
  }) => Semantics(
    identifier: identificador,
    button: true,
    child: Material(
      color: primario ? _destaque : Colors.white,
      child: InkWell(
        onTap: aoTocar,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: _tinta, width: 2),
          ),
          child: Text(
            rotulo,
            style: const TextStyle(
              color: _tinta,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mensagemDeErro(String mensagem) => Semantics(
    identifier: 'requisicao-erro',
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFFFDAD6),
      child: Text(
        mensagem,
        style: const TextStyle(
          color: _perigo,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    ),
  );

  Widget _aviso(String texto, {required Future<void> Function() aoTentar}) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _tinta, width: 2),
        ),
        child: Column(
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _tinta, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _botao(
              identificador: 'requisicao-tentar',
              rotulo: 'TENTAR DE NOVO',
              aoTocar: aoTentar,
            ),
          ],
        ),
      );
}
