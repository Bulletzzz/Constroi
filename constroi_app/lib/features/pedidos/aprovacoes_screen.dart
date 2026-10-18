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
const _perigoFundo = Color(0xFFFFDAD6);
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

class AprovacoesScreen extends StatefulWidget {
  const AprovacoesScreen({
    super.key,
    required this.service,
    required this.perfil,
  });

  final PedidosService service;
  final PerfilUsuario perfil;

  @override
  State<AprovacoesScreen> createState() => _AprovacoesScreenState();
}

class _AprovacoesScreenState extends State<AprovacoesScreen> {
  List<Pedido> _pendentes = const [];
  List<ObraDisponivel> _obras = const [];
  int? _obraId;
  bool _carregando = true;
  String? _erro;
  int? _decidindo;
  String? _erroDaDecisao;
  int _consultaAtual = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final consulta = ++_consultaAtual;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      if (_obras.isEmpty) {
        final obras = await widget.service.obras();
        if (!mounted || consulta != _consultaAtual) return;
        setState(() => _obras = obras);
      }
      final pendentes = await widget.service.pendentes(obraId: _obraId);
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _pendentes = pendentes;
        _carregando = false;
      });
    } on ApiException catch (erro) {
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _erro = erro.message;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted || consulta != _consultaAtual) return;
      setState(() {
        _erro = 'Não foi possível carregar a fila agora.';
        _carregando = false;
      });
    }
  }

  Future<void> _aprovar(Pedido pedido) async {
    setState(() {
      _decidindo = pedido.id;
      _erroDaDecisao = null;
    });
    await _decidir(() => widget.service.aprovar(pedido.id), pedido);
  }

  Future<void> _recusar(Pedido pedido) async {
    final motivo = await _pedirJustificativa(pedido);
    if (motivo == null || !mounted) return;
    setState(() {
      _decidindo = pedido.id;
      _erroDaDecisao = null;
    });
    await _decidir(() => widget.service.recusar(pedido.id, motivo), pedido);
  }

  Future<void> _decidir(Future<Pedido> Function() acao, Pedido pedido) async {
    try {
      await acao();
      if (!mounted) return;
      setState(() {
        _pendentes = _pendentes.where((p) => p.id != pedido.id).toList();
        _decidindo = null;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _decidindo = null;
        _erroDaDecisao = erro.statusCode == 409
            ? 'O pedido ${pedido.protocoloCurto} já foi decidido ou está sem saldo.'
            : erro.message;
      });
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _decidindo = null;
        _erroDaDecisao = 'Não foi possível concluir a decisão.';
      });
    }
  }

  Future<String?> _pedirJustificativa(Pedido pedido) {
    final controlador = TextEditingController();
    var faltaMotivo = false;
    return showDialog<String>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, redesenhar) => AlertDialog(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
          title: Text(
            'RECUSAR ${pedido.protocoloCurto}',
            style: const TextStyle(
              color: _tinta,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          content: Semantics(
            identifier: 'aprovacoes-justificativa',
            textField: true,
            child: TextField(
              controller: controlador,
              autofocus: true,
              maxLines: 3,
              maxLength: 255,
              onChanged: (_) {
                if (faltaMotivo) redesenhar(() => faltaMotivo = false);
              },
              style: const TextStyle(color: _tinta, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Explique o motivo da recusa',
                hintStyle: const TextStyle(color: _dica, fontSize: 13),
                border: const OutlineInputBorder(),
                errorText: faltaMotivo ? 'A recusa exige justificativa.' : null,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(),
              child: Text('CANCELAR', style: _mini(_apoio)),
            ),
            Semantics(
              identifier: 'aprovacoes-confirmar-recusa',
              button: true,
              child: TextButton(
                onPressed: () {
                  final texto = controlador.text.trim();
                  if (texto.isEmpty) {
                    redesenhar(() => faltaMotivo = true);
                    return;
                  }
                  Navigator.of(contexto).pop(texto);
                },
                child: Text('RECUSAR', style: _mini(_perigo)),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(controlador.dispose);
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
      child: RefreshIndicator(
        color: _tinta,
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            _titulo(),
            const SizedBox(height: 20),
            if (_obras.length > 1) ...[
              _seletorDeObra(),
              const SizedBox(height: 16),
            ],
            _faixaDaFila(),
            const SizedBox(height: 16),
            if (_erroDaDecisao != null) ...[
              _mensagemDeErro(_erroDaDecisao!),
              const SizedBox(height: 16),
            ],
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_tinta),
                  ),
                ),
              )
            else if (_erro != null)
              _aviso(_erro!)
            else if (_pendentes.isEmpty)
              _filaVazia()
            else
              for (final pedido in _pendentes) _cartao(pedido),
          ],
        ),
      ),
    ),
  );

  Widget _titulo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'APROVAÇÕES',
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
        'Fila do engenheiro: decida o que sai do estoque.',
        style: TextStyle(color: _apoio, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 18),
      Container(height: 1.5, color: _tinta),
    ],
  );

  Widget _seletorDeObra() => Semantics(
    identifier: 'aprovacoes-obra',
    button: true,
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _tinta, width: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _obraId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: _tinta),
          style: const TextStyle(color: _tinta, fontSize: 13),
          onChanged: _carregando
              ? null
              : (valor) {
                  setState(() => _obraId = valor);
                  _carregar();
                },
          items: [
            const DropdownMenuItem<int?>(child: Text('Todas as obras')),
            for (final obra in _obras)
              DropdownMenuItem<int?>(
                value: obra.id,
                child: Text(obra.nome, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _faixaDaFila() => Semantics(
    identifier: 'aprovacoes-contador',
    child: Container(
      color: _tinta,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'AGUARDANDO APROVAÇÃO',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mini(Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Text(_carregando ? '...' : _contagem(), style: _mini(_destaque)),
        ],
      ),
    ),
  );

  String _contagem() {
    final total = _pendentes.length;
    final palavra = total == 1 ? 'PENDENTE' : 'PENDENTES';
    return total >= limiteDaFila ? '$total+ $palavra' : '$total $palavra';
  }

  Widget _cartao(Pedido pedido) {
    final decidindo = _decidindo == pedido.id;
    final urgente = pedido.urgencia == Urgencia.urgente;
    return Semantics(
      identifier: 'aprovacoes-pedido',
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _tinta, width: 2),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pedido.protocoloCurto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _tinta,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  color: urgente ? _perigoFundo : _fundo,
                  child: Text(
                    pedido.urgencia.rotulo.toUpperCase(),
                    style: _mini(urgente ? _perigo : _apoio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in pedido.itens)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  item.descricao,
                  style: const TextStyle(
                    color: _tinta,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (pedido.itens.isEmpty)
              Text(
                'Sem itens registrados.',
                style: TextStyle(color: _apoio, fontSize: 13),
              ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _dado('SOLICITANTE', pedido.solicitante ?? '—'),
                ),
                Expanded(
                  child: _dado('LOCAL DA OBRA', pedido.localObra ?? '—'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _dado('PRAZO PEDIDO', pedido.urgencia.prazo)),
                Expanded(child: _dado('ENVIADO EM', _dataCurta(pedido.data))),
              ],
            ),
            if (pedido.justificativa != null) ...[
              const SizedBox(height: 12),
              _dado('OBSERVAÇÃO', pedido.justificativa!),
            ],
            const SizedBox(height: 16),
            Container(height: 1, color: _separador),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _botao(
                    identificador: 'aprovacoes-recusar',
                    rotulo: 'RECUSAR',
                    aoTocar: decidindo ? null : () => _recusar(pedido),
                    primario: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _botao(
                    identificador: 'aprovacoes-aprovar',
                    rotulo: decidindo ? '...' : 'APROVAR',
                    aoTocar: decidindo ? null : () => _aprovar(pedido),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dado(String rotulo, String valor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(rotulo, style: _mini(_rotulo)),
      const SizedBox(height: 4),
      Text(
        valor,
        style: const TextStyle(color: _tinta, fontSize: 13, height: 1.3),
      ),
    ],
  );

  String _dataCurta(DateTime? data) {
    if (data == null) return '—';
    String doisDigitos(int valor) => valor.toString().padLeft(2, '0');
    return '${doisDigitos(data.day)}/${doisDigitos(data.month)} '
        '${doisDigitos(data.hour)}:${doisDigitos(data.minute)}';
  }

  Widget _filaVazia() => Semantics(
    identifier: 'aprovacoes-vazio',
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _separador, width: 2),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, color: _apoio, size: 34),
          const SizedBox(height: 12),
          const Text(
            'Nenhuma requisição aguardando decisão.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _tinta, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Puxe para atualizar.',
            style: TextStyle(color: _apoio, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _mensagemDeErro(String mensagem) => Semantics(
    identifier: 'aprovacoes-erro',
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: _perigoFundo,
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

  Widget _aviso(String texto) => Container(
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
          identificador: 'aprovacoes-tentar',
          rotulo: 'TENTAR DE NOVO',
          aoTocar: _carregar,
        ),
      ],
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
          height: 48,
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
}
