import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/catalogo/opcoes.dart';
import '../../navigation/perfil_usuario.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import 'cadastro_service.dart';

enum TipoDeItem { produto, equipamento }

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({
    super.key,
    required this.service,
    required this.perfil,
  });

  final CadastroService service;
  final PerfilUsuario perfil;

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  static const _tinta = Color(0xFF1A1C1C);
  static const _apoio = Color(0xFF5E5E5E);
  static const _perigo = Color(0xFFB3261E);

  final _formulario = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _codigo = TextEditingController();
  final _minimo = TextEditingController();

  TipoDeItem _tipo = TipoDeItem.produto;
  String _unidade = unidadesDoProduto.first.codigo;
  String _status = statusDoEquipamento.first.codigo;
  int? _categoria;
  List<CategoriaCusto> _categorias = [];
  bool _carregandoCategorias = true;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
  }

  @override
  void dispose() {
    _nome.dispose();
    _codigo.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _carregarCategorias() async {
    try {
      final lista = await widget.service.categorias();
      if (!mounted) return;
      setState(() {
        _categorias = lista;
        _carregandoCategorias = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoCategorias = false);
    }
  }

  bool get _ehProduto => _tipo == TipoDeItem.produto;

  void _trocarTipo(TipoDeItem novo) {
    if (_tipo == novo) return;
    setState(() {
      _tipo = novo;
      _erro = null;
      _formulario.currentState?.reset();
    });
  }

  void _gerarCodigo() {
    final base = _nome.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9 ]'), '')
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p.length > 3 ? p.substring(0, 3) : p)
        .join('-');
    if (base.isEmpty) {
      setState(() => _erro = 'Escreva o nome antes de gerar o código.');
      return;
    }
    final sufixo = DateTime.now().millisecondsSinceEpoch
        .remainder(10000)
        .toString()
        .padLeft(4, '0');
    setState(() {
      _erro = null;
      _codigo.text = '${_ehProduto ? base : 'EQP-$base'}-$sufixo';
    });
  }

  String? _validarNome(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Informe o nome do item.';
    if (texto.length < 2) return 'O nome precisa de pelo menos 2 letras.';
    if (texto.length > 150) return 'O nome passa de 150 caracteres.';
    return null;
  }

  String? _validarCodigo(String? valor) {
    final texto = (valor ?? '').trim();
    if (_ehProduto) {
      if (texto.isEmpty) return null;
      if (texto.length > 50) return 'O código passa de 50 caracteres.';
      return null;
    }
    if (texto.isEmpty) return 'O patrimônio é obrigatório no equipamento.';
    if (texto.length > 50) return 'O patrimônio passa de 50 caracteres.';
    return null;
  }

  String? _validarMinimo(String? valor) {
    final texto = (valor ?? '').trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(texto)) {
      return 'Use um número com até duas casas.';
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      final item = _ehProduto
          ? await widget.service.criarProduto(
              nome: _nome.text.trim(),
              unidade: _unidade,
              sku: _codigo.text.trim(),
              estoqueMinimo: _minimo.text.trim().replaceAll(',', '.'),
              categoriaId: _categoria,
            )
          : await widget.service.criarEquipamento(
              nome: _nome.text.trim(),
              patrimonio: _codigo.text.trim(),
              status: _status,
            );
      if (!mounted) return;
      Navigator.of(context).pop(item);
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = erro.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = 'Não foi possível salvar. Confira a conexão.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F2F2),
    appBar: AppHeader(perfil: widget.perfil),
    body: SafeArea(
      child: Form(
        key: _formulario,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _titulo(),
                    const SizedBox(height: 20),
                    _seletorDeTipo(),
                    const SizedBox(height: 20),
                    _campoNome(),
                    const SizedBox(height: 16),
                    _campoCodigo(),
                    if (_ehProduto) ...[
                      const SizedBox(height: 16),
                      _campoCategoria(),
                      const SizedBox(height: 16),
                      _campoUnidade(),
                      const SizedBox(height: 16),
                      _campoMinimo(),
                    ] else ...[
                      const SizedBox(height: 16),
                      _campoStatus(),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: 16),
                      _avisoDeErro(_erro!),
                    ],
                    const SizedBox(height: 24),
                    _acoes(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _titulo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        identifier: 'cadastro-titulo',
        child: const Text(
          'CADASTRO DE ITEM',
          style: TextStyle(
            color: _tinta,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Produtos e equipamentos do almoxarifado',
        style: TextStyle(color: _apoio, fontSize: 14),
      ),
    ],
  );

  Widget _seletorDeTipo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo('TIPO DE ITEM'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _botaoDeTipo(TipoDeItem.produto, 'PRODUTO', 'cadastro-tipo-produto'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _botaoDeTipo(
              TipoDeItem.equipamento,
              'EQUIPAMENTO',
              'cadastro-tipo-equipamento',
            ),
          ),
        ],
      ),
    ],
  );

  Widget _botaoDeTipo(TipoDeItem tipo, String texto, String identificador) {
    final ativo = _tipo == tipo;
    return Semantics(
      identifier: identificador,
      button: true,
      selected: ativo,
      child: InkWell(
        onTap: _salvando ? null : () => _trocarTipo(tipo),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: ativo ? AppTheme.accent : Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _tinta,
              fontWeight: ativo ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _campoNome() => _campo(
    identificador: 'cadastro-nome',
    rotulo: 'NOME DO ITEM',
    controle: _nome,
    dica: _ehProduto ? 'ex.: Cimento CP-II 50kg' : 'ex.: Betoneira 400L',
    validador: _validarNome,
  );

  Widget _campoCodigo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo(_ehProduto ? 'CÓDIGO / SKU' : 'PATRIMÔNIO'),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              identifier: 'cadastro-codigo',
              textField: true,
              child: TextFormField(
                controller: _codigo,
                enabled: !_salvando,
                decoration: _decoracao(
                  _ehProduto ? 'opcional' : 'ex.: EQP-BET-400L',
                ),
                validator: _validarCodigo,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            identifier: 'cadastro-gerar-codigo',
            button: true,
            child: OutlinedButton(
              onPressed: _salvando ? null : _gerarCodigo,
              style: OutlinedButton.styleFrom(
                foregroundColor: _tinta,
                side: const BorderSide(color: _tinta, width: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text(
                'GERAR',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _campoCategoria() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo('CATEGORIA'),
      const SizedBox(height: 8),
      Semantics(
        identifier: 'cadastro-categoria',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: _categoria,
              isExpanded: true,
              hint: Text(
                _carregandoCategorias
                    ? 'Carregando categorias...'
                    : 'Sem categoria',
                style: const TextStyle(color: _apoio),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  child: Text('Sem categoria'),
                ),
                for (final c in _categorias)
                  DropdownMenuItem<int?>(value: c.id, child: Text(c.nome)),
              ],
              onChanged: _salvando
                  ? null
                  : (valor) => setState(() => _categoria = valor),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _campoUnidade() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo('UNIDADE'),
      const SizedBox(height: 8),
      Semantics(
        identifier: 'cadastro-unidade',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _unidade,
              isExpanded: true,
              items: [
                for (final u in unidadesDoProduto)
                  DropdownMenuItem(value: u.codigo, child: Text(u.rotulo)),
              ],
              onChanged: _salvando
                  ? null
                  : (valor) => setState(() => _unidade = valor ?? _unidade),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _campoStatus() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo('STATUS'),
      const SizedBox(height: 8),
      Semantics(
        identifier: 'cadastro-status',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _tinta, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status,
              isExpanded: true,
              items: [
                for (final s in statusDoEquipamento)
                  DropdownMenuItem(value: s.codigo, child: Text(s.rotulo)),
              ],
              onChanged: _salvando
                  ? null
                  : (valor) => setState(() => _status = valor ?? _status),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _campoMinimo() => _campo(
    identificador: 'cadastro-minimo',
    rotulo: 'ESTOQUE MÍNIMO',
    controle: _minimo,
    dica: 'ex.: 2',
    validador: _validarMinimo,
    teclado: const TextInputType.numberWithOptions(decimal: true),
    formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
  );

  Widget _campo({
    required String identificador,
    required String rotulo,
    required TextEditingController controle,
    required String dica,
    required String? Function(String?) validador,
    TextInputType? teclado,
    List<TextInputFormatter>? formatadores,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rotulo(rotulo),
      const SizedBox(height: 8),
      Semantics(
        identifier: identificador,
        textField: true,
        child: TextFormField(
          controller: controle,
          enabled: !_salvando,
          keyboardType: teclado,
          inputFormatters: formatadores,
          decoration: _decoracao(dica),
          validator: validador,
        ),
      ),
    ],
  );

  Widget _rotulo(String texto) => Text(
    texto,
    style: const TextStyle(
      color: _apoio,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );

  InputDecoration _decoracao(String dica) => InputDecoration(
    hintText: dica,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: _tinta, width: 2),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: _tinta, width: 2),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: _tinta, width: 2),
    ),
  );

  Widget _avisoDeErro(String texto) => Semantics(
    identifier: 'cadastro-erro',
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE7E7),
        border: Border.all(color: _perigo, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _perigo, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: _perigo, fontSize: 13.5),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _acoes() => Row(
    children: [
      Expanded(
        child: Semantics(
          identifier: 'cadastro-cancelar',
          button: true,
          child: OutlinedButton(
            onPressed: _salvando ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _tinta,
              side: const BorderSide(color: _tinta, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: const RoundedRectangleBorder(),
            ),
            child: const Text(
              'CANCELAR',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: Semantics(
          identifier: 'cadastro-salvar',
          button: true,
          child: FilledButton(
            onPressed: _salvando ? null : _salvar,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: _tinta,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              _salvando ? 'SALVANDO...' : 'SALVAR ITEM',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    ],
  );
}
