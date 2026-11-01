import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import 'administracao_service.dart';

const _tinta = Color(0xFF1A1C1C);
const _amarelo = Color(0xFFFFD700);
const _fundo = Color(0xFFF2F2F2);
const _apoio = Color(0xFF5E5E5E);
const _perigo = Color(0xFFB3261E);

enum AbaAdmin { usuarios, logs }

class AdministracaoScreen extends StatefulWidget {
  const AdministracaoScreen({
    super.key,
    required this.service,
    required this.perfil,
    this.usuarioAtualId,
  });

  final AdministracaoService service;
  final PerfilUsuario perfil;
  final int? usuarioAtualId;

  @override
  State<AdministracaoScreen> createState() => _AdministracaoScreenState();
}

class _AdministracaoScreenState extends State<AdministracaoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();

  AbaAdmin _aba = AbaAdmin.usuarios;

  List<UsuarioAdmin> _usuarios = [];
  bool _carregandoUsuarios = true;
  String? _erroUsuarios;
  int _consultaUsuarios = 0;
  int? _inativando;

  bool _abrindoFormulario = false;
  bool _salvando = false;
  String? _erroFormulario;
  PerfilUsuario _perfilNovo = PerfilUsuario.pedreiro;

  PaginaDeLogs? _logs;
  bool _carregandoLogs = false;
  String? _erroLogs;
  int _consultaLogs = 0;
  int _pagina = 0;
  int? _autorFiltrado;
  DateTime? _inicio;
  DateTime? _fim;

  @override
  void initState() {
    super.initState();
    _carregarUsuarios();
  }

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Map<int, String> get _nomesPorId => {
    for (final usuario in _usuarios) usuario.id: usuario.nome,
  };

  bool get _podeAvancar =>
      (_logs?.temMais ?? false) &&
      (_pagina + 1) * AdministracaoService.tamanhoDaPagina <=
          AdministracaoService.offsetMaximo;

  Future<void> _carregarUsuarios() async {
    final consulta = ++_consultaUsuarios;
    setState(() {
      _carregandoUsuarios = true;
      _erroUsuarios = null;
    });
    try {
      final lista = await widget.service.usuarios();
      if (!mounted || consulta != _consultaUsuarios) return;
      setState(() {
        _usuarios = lista;
        _carregandoUsuarios = false;
      });
    } catch (erro) {
      if (!mounted || consulta != _consultaUsuarios) return;
      setState(() {
        _carregandoUsuarios = false;
        _erroUsuarios = _mensagem(
          erro,
          'Não foi possível carregar os usuários. Confira a conexão.',
        );
      });
    }
  }

  Future<void> _carregarLogs() async {
    final consulta = ++_consultaLogs;
    setState(() {
      _carregandoLogs = true;
      _erroLogs = null;
    });
    try {
      final pagina = await widget.service.logs(
        usuarioId: _autorFiltrado,
        inicio: _inicio,
        fim: _fim,
        pagina: _pagina,
      );
      if (!mounted || consulta != _consultaLogs) return;
      setState(() {
        _logs = pagina;
        _carregandoLogs = false;
      });
    } catch (erro) {
      if (!mounted || consulta != _consultaLogs) return;
      setState(() {
        _carregandoLogs = false;
        _erroLogs = _mensagem(
          erro,
          'Não foi possível carregar os registros. Confira a conexão.',
        );
      });
    }
  }

  String _mensagem(Object erro, String padrao) =>
      erro is ApiException ? erro.message : padrao;

  void _trocarAba(AbaAdmin nova) {
    if (_aba == nova) return;
    setState(() => _aba = nova);
    if (nova == AbaAdmin.logs && _logs == null && !_carregandoLogs) {
      _carregarLogs();
    }
  }

  void _refazerFiltro() {
    _pagina = 0;
    _carregarLogs();
  }

  void _descartarLogs() {
    _logs = null;
    _pagina = 0;
  }

  Future<void> _escolherData({required bool inicial}) async {
    final hoje = DateTime.now();
    final atual = inicial ? _inicio : _fim;
    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual ?? hoje,
      firstDate: DateTime(hoje.year - 5),
      lastDate: DateTime(hoje.year + 1, 12, 31),
    );
    if (escolhida == null) return;
    setState(() {
      if (inicial) {
        _inicio = escolhida;
        if (_fim != null && _fim!.isBefore(escolhida)) _fim = escolhida;
      } else {
        _fim = escolhida;
        if (_inicio != null && _inicio!.isAfter(escolhida)) _inicio = escolhida;
      }
    });
    _refazerFiltro();
  }

  void _limparFiltros() {
    setState(() {
      _autorFiltrado = null;
      _inicio = null;
      _fim = null;
    });
    _refazerFiltro();
  }

  void _abrirFormulario() {
    setState(() {
      _abrindoFormulario = true;
      _erroFormulario = null;
      _perfilNovo = PerfilUsuario.pedreiro;
      _nome.clear();
      _email.clear();
      _senha.clear();
    });
  }

  void _fecharFormulario() {
    setState(() {
      _abrindoFormulario = false;
      _erroFormulario = null;
    });
  }

  String? _validarNome(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Informe o nome do usuário.';
    if (texto.length > 150) return 'O nome passa de 150 caracteres.';
    return null;
  }

  String? _validarEmail(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Informe o e-mail do usuário.';
    if (texto.length > 150) return 'O e-mail passa de 150 caracteres.';
    if (!texto.contains('@') || !texto.contains('.')) {
      return 'Use um e-mail com @ e domínio.';
    }
    return null;
  }

  String? _validarSenha(String? valor) {
    final texto = valor ?? '';
    if (texto.length < 8) return 'A senha precisa de pelo menos 8 caracteres.';
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    setState(() {
      _salvando = true;
      _erroFormulario = null;
    });
    try {
      final criado = await widget.service.criar(
        nome: _nome.text.trim(),
        email: _email.text.trim(),
        senha: _senha.text,
        perfil: _perfilNovo,
      );
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _abrindoFormulario = false;
        _usuarios = [..._usuarios, criado]
          ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
        _descartarLogs();
      });
      _avisar('${criado.nome} foi cadastrado.');
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erroFormulario = _mensagem(
          erro,
          'Não foi possível cadastrar. Confira a conexão.',
        );
      });
    }
  }

  Future<void> _inativar(UsuarioAdmin usuario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Inativar usuário',
          style: TextStyle(color: _tinta, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${usuario.nome} perde o acesso ao sistema. '
          'O histórico de ações continua registrado.',
          style: const TextStyle(color: _tinta),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar', style: TextStyle(color: _tinta)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Inativar', style: TextStyle(color: _perigo)),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _inativando = usuario.id);
    try {
      final atualizado = await widget.service.inativar(usuario.id);
      if (!mounted) return;
      setState(() {
        _inativando = null;
        _usuarios = [
          for (final item in _usuarios)
            if (item.id == atualizado.id) atualizado else item,
        ];
        _descartarLogs();
      });
      _avisar('${atualizado.nome} foi inativado.');
    } catch (erro) {
      if (!mounted) return;
      setState(() => _inativando = null);
      _avisar(
        _mensagem(erro, 'Não foi possível inativar. Confira a conexão.'),
      );
    }
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    appBar: AppHeader(perfil: widget.perfil),
    bottomNavigationBar: AppBottomNavigation(
      rotaAtual: AppRoute.administracao,
      perfil: widget.perfil,
    ),
    body: RefreshIndicator(
      onRefresh: () async {
        await _carregarUsuarios();
        if (_aba == AbaAdmin.logs) await _carregarLogs();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    identifier: 'admin-titulo',
                    header: true,
                    child: const Text(
                      'ADMINISTRAÇÃO',
                      style: TextStyle(
                        color: _tinta,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gestão de usuários e consulta de eventos do sistema',
                    style: TextStyle(color: _apoio, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _abas(),
                  const Divider(color: _tinta, thickness: 2, height: 28),
                  if (_aba == AbaAdmin.usuarios)
                    ..._conteudoUsuarios()
                  else
                    ..._conteudoLogs(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _abas() => Row(
    children: [
      _botaoAba(AbaAdmin.usuarios, 'USUÁRIOS', 'admin-aba-usuarios'),
      const SizedBox(width: 8),
      _botaoAba(AbaAdmin.logs, 'LOGS', 'admin-aba-logs'),
    ],
  );

  Widget _botaoAba(AbaAdmin aba, String rotulo, String identificador) {
    final ativa = _aba == aba;
    return Expanded(
      child: Semantics(
        identifier: identificador,
        button: true,
        selected: ativa,
        child: Material(
          color: ativa ? _tinta : Colors.white,
          child: InkWell(
            onTap: () => _trocarAba(aba),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: _tinta, width: 2),
              ),
              child: Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ativa ? _amarelo : _tinta,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _conteudoUsuarios() => [
    if (_abrindoFormulario) _formularioDeUsuario() else _botaoNovoUsuario(),
    const SizedBox(height: 20),
    _faixa('PESSOAS', _carregandoUsuarios || _erroUsuarios != null
        ? null
        : '${_usuarios.where((u) => u.ativo).length} ativos de '
              '${_usuarios.length}'),
    if (_carregandoUsuarios)
      _girando()
    else if (_erroUsuarios != null)
      _aviso(_erroUsuarios!, aoTentar: _carregarUsuarios)
    else if (_usuarios.isEmpty)
      _aviso('Nenhum usuário cadastrado nesta empresa.')
    else
      for (var i = 0; i < _usuarios.length; i++) _linhaUsuario(_usuarios[i], i),
  ];

  Widget _botaoNovoUsuario() => Semantics(
    identifier: 'admin-novo-usuario',
    button: true,
    child: Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        onPressed: _abrirFormulario,
        style: ElevatedButton.styleFrom(
          backgroundColor: _tinta,
          foregroundColor: _amarelo,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('NOVO USUÁRIO'),
      ),
    ),
  );

  Widget _formularioDeUsuario() => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formulario,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'NOVO USUÁRIO',
            style: TextStyle(
              color: _apoio,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _campo(
            identificador: 'admin-nome',
            rotulo: 'NOME',
            controle: _nome,
            dica: 'ex.: Maria Souza',
            validador: _validarNome,
          ),
          const SizedBox(height: 12),
          _campo(
            identificador: 'admin-email',
            rotulo: 'E-MAIL',
            controle: _email,
            dica: 'ex.: maria@empresa.com.br',
            validador: _validarEmail,
            teclado: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _campo(
            identificador: 'admin-senha',
            rotulo: 'SENHA',
            controle: _senha,
            dica: 'pelo menos 8 caracteres',
            validador: _validarSenha,
            escondido: true,
          ),
          const SizedBox(height: 12),
          const Text(
            'PERFIL',
            style: TextStyle(
              color: _apoio,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'admin-tipo',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _tinta, width: 2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PerfilUsuario>(
                  value: _perfilNovo,
                  isExpanded: true,
                  style: const TextStyle(color: _tinta, fontSize: 14),
                  items: const [
                    DropdownMenuItem(
                      value: PerfilUsuario.pedreiro,
                      child: Text('Pedreiro'),
                    ),
                    DropdownMenuItem(
                      value: PerfilUsuario.engenheiro,
                      child: Text('Engenheiro'),
                    ),
                    DropdownMenuItem(
                      value: PerfilUsuario.master,
                      child: Text('Master'),
                    ),
                  ],
                  onChanged: _salvando
                      ? null
                      : (valor) =>
                            setState(() => _perfilNovo = valor ?? _perfilNovo),
                ),
              ),
            ),
          ),
          if (_erroFormulario != null) ...[
            const SizedBox(height: 12),
            Semantics(
              identifier: 'admin-form-erro',
              liveRegion: true,
              child: Text(
                _erroFormulario!,
                style: const TextStyle(color: _perigo, height: 1.3),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'admin-cancelar',
                  button: true,
                  child: OutlinedButton(
                    onPressed: _salvando ? null : _fecharFormulario,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _tinta,
                      side: const BorderSide(color: _tinta, width: 2),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('CANCELAR'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  identifier: 'admin-salvar',
                  button: true,
                  child: ElevatedButton(
                    onPressed: _salvando ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tinta,
                      foregroundColor: _amarelo,
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(_salvando ? 'SALVANDO...' : 'SALVAR'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _campo({
    required String identificador,
    required String rotulo,
    required TextEditingController controle,
    required String dica,
    required String? Function(String?) validador,
    TextInputType? teclado,
    bool escondido = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        rotulo,
        style: const TextStyle(
          color: _apoio,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        identifier: identificador,
        textField: true,
        child: TextFormField(
          controller: controle,
          enabled: !_salvando,
          keyboardType: teclado,
          obscureText: escondido,
          validator: validador,
          decoration: InputDecoration(
            hintText: dica,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
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
          ),
        ),
      ),
    ],
  );

  Widget _linhaUsuario(UsuarioAdmin usuario, int indice) {
    final ehVoce = usuario.id == widget.usuarioAtualId;
    return Semantics(
      identifier: 'admin-usuario',
      container: true,
      child: Container(
        color: indice.isEven ? Colors.white : const Color(0xFFEAEAEA),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    usuario.nome,
                    style: const TextStyle(
                      color: _tinta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    usuario.email,
                    style: const TextStyle(color: _apoio, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                usuario.papel,
                style: const TextStyle(color: _tinta, fontSize: 13),
              ),
            ),
            if (!usuario.ativo)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                color: _apoio,
                child: const Text(
                  'INATIVO',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              )
            else if (ehVoce)
              const Text(
                'Você',
                style: TextStyle(color: _apoio, fontSize: 12),
              )
            else
              Semantics(
                identifier: 'admin-usuario-inativar',
                button: true,
                child: TextButton(
                  onPressed: _inativando == null
                      ? () => _inativar(usuario)
                      : null,
                  child: Text(
                    _inativando == usuario.id ? 'INATIVANDO...' : 'INATIVAR',
                    style: const TextStyle(color: _perigo, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _conteudoLogs() {
    final registros = _logs?.registros ?? const <RegistroLog>[];
    final nomes = _nomesPorId;
    return [
      _filtrosDeLog(),
      const SizedBox(height: 20),
      _faixa(
        'EVENTOS',
        _carregandoLogs || _erroLogs != null
            ? null
            : 'página ${_pagina + 1}',
      ),
      if (_carregandoLogs)
        _girando()
      else if (_erroLogs != null)
        _aviso(_erroLogs!, aoTentar: _carregarLogs)
      else if (registros.isEmpty)
        _aviso('Nenhum evento registrado para este filtro.')
      else ...[
        for (var i = 0; i < registros.length; i++)
          _linhaLog(registros[i], i, nomes),
        _paginacao(),
      ],
    ];
  }

  Widget _filtrosDeLog() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        identifier: 'admin-log-usuario',
        container: true,
        child: DropdownButton<int?>(
          value: _autorFiltrado,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(color: _tinta, fontSize: 14),
          iconEnabledColor: _tinta,
          hint: const Text(
            'Todos os autores',
            style: TextStyle(color: _apoio, fontSize: 14),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos os autores')),
            for (final usuario in _usuarios)
              DropdownMenuItem(
                value: usuario.id,
                child: Text(usuario.nome, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (valor) {
            setState(() => _autorFiltrado = valor);
            _refazerFiltro();
          },
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _botaoData(
              identificador: 'admin-log-inicio',
              rotulo: 'De',
              valor: _inicio,
              aoTocar: () => _escolherData(inicial: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _botaoData(
              identificador: 'admin-log-fim',
              rotulo: 'Até',
              valor: _fim,
              aoTocar: () => _escolherData(inicial: false),
            ),
          ),
        ],
      ),
      if (_autorFiltrado != null || _inicio != null || _fim != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            identifier: 'admin-log-limpar',
            button: true,
            child: TextButton.icon(
              onPressed: _limparFiltros,
              icon: const Icon(Icons.close, color: _tinta, size: 18),
              label: const Text(
                'Limpar filtros',
                style: TextStyle(color: _tinta),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _botaoData({
    required String identificador,
    required String rotulo,
    required DateTime? valor,
    required VoidCallback aoTocar,
  }) => Semantics(
    identifier: identificador,
    button: true,
    child: OutlinedButton.icon(
      onPressed: aoTocar,
      style: OutlinedButton.styleFrom(
        foregroundColor: _tinta,
        side: const BorderSide(color: _tinta, width: 2),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: const Icon(Icons.event, size: 18),
      label: Text(
        valor == null
            ? rotulo
            : '$rotulo ${valor.day.toString().padLeft(2, '0')}/'
                  '${valor.month.toString().padLeft(2, '0')}/${valor.year}',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _linhaLog(RegistroLog registro, int indice, Map<int, String> nomes) =>
      Semantics(
        identifier: 'admin-log',
        container: true,
        child: Container(
          color: indice.isEven ? Colors.white : const Color(0xFFEAEAEA),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    registro.evento,
                    style: const TextStyle(
                      color: _tinta,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    registro.momento,
                    style: const TextStyle(color: _apoio, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                nomes[registro.usuarioId] ?? 'Usuário #${registro.usuarioId}',
                style: const TextStyle(color: _tinta, fontSize: 13),
              ),
              if (registro.detalhe.isNotEmpty)
                Text(
                  registro.detalhe,
                  style: const TextStyle(color: _apoio, fontSize: 12),
                ),
            ],
          ),
        ),
      );

  Widget _paginacao() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      children: [
        Semantics(
          identifier: 'admin-log-anterior',
          button: true,
          child: TextButton(
            onPressed: _pagina == 0
                ? null
                : () {
                    _pagina--;
                    _carregarLogs();
                  },
            child: const Text('Anterior', style: TextStyle(color: _tinta)),
          ),
        ),
        Semantics(
          identifier: 'admin-log-proxima',
          button: true,
          child: TextButton(
            onPressed: !_podeAvancar
                ? null
                : () {
                    _pagina++;
                    _carregarLogs();
                  },
            child: const Text('Próxima', style: TextStyle(color: _tinta)),
          ),
        ),
      ],
    ),
  );

  Widget _faixa(String titulo, String? contador) => Container(
    color: _tinta,
    padding: const EdgeInsets.all(12),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (contador != null)
          Text(contador, style: const TextStyle(color: _amarelo)),
      ],
    ),
  );

  Widget _girando() => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator(color: _tinta)),
  );

  Widget _aviso(String texto, {Future<void> Function()? aoTentar}) => Semantics(
    identifier: aoTentar == null ? 'admin-vazio' : 'admin-erro',
    container: true,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _apoio, height: 1.4),
          ),
          if (aoTentar != null)
            TextButton(
              onPressed: aoTentar,
              child: const Text(
                'Tentar novamente',
                style: TextStyle(color: _tinta),
              ),
            ),
        ],
      ),
    ),
  );
}
