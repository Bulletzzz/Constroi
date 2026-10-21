import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import 'equipe_service.dart';

const _tinta = Color(0xFF1A1C1C);
const _amarelo = Color(0xFFFFD700);
const _fundo = Color(0xFFF2F2F2);
const _apoio = Color(0xFF5E5E5E);

class EquipeScreen extends StatefulWidget {
  const EquipeScreen({super.key, required this.service, required this.perfil});
  final EquipeService service;
  final PerfilUsuario perfil;

  @override
  State<EquipeScreen> createState() => _EquipeScreenState();
}

class _EquipeScreenState extends State<EquipeScreen> {
  final _busca = TextEditingController();
  List<ObraEquipe> _obras = [];
  List<PessoaEquipe> _pessoas = [];
  int? _obra;
  int _consulta = 0;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar(recarregarObras: true);
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool recarregarObras = false}) async {
    final consulta = ++_consulta;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      if (recarregarObras) {
        final obras = await widget.service.obras();
        if (!mounted || consulta != _consulta) return;
        setState(() {
          _obras = obras;
          if (!obras.any((o) => o.id == _obra)) {
            _obra = obras.isEmpty ? null : obras.first.id;
          }
        });
      }
      final pessoas = _obra == null
          ? <PessoaEquipe>[]
          : await widget.service.listar(_obra!);
      if (!mounted || consulta != _consulta) return;
      setState(() {
        _pessoas = pessoas;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted || consulta != _consulta) return;
      setState(() {
        _carregando = false;
        _erro = erro is ApiException
            ? erro.message
            : 'Não foi possível carregar a equipe. Confira a conexão.';
      });
    }
  }

  List<PessoaEquipe> get _filtradas {
    final termo = _busca.text.trim().toLowerCase();
    return _pessoas
        .where(
          (p) =>
              '${p.nome} ${p.email} ${p.papel}'.toLowerCase().contains(termo),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    appBar: AppHeader(perfil: widget.perfil),
    bottomNavigationBar: AppBottomNavigation(
      rotaAtual: AppRoute.equipe,
      perfil: widget.perfil,
    ),
    body: RefreshIndicator(
      onRefresh: () => _carregar(recarregarObras: true),
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
                  const Text(
                    'EQUIPE DA OBRA',
                    style: TextStyle(
                      color: _tinta,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pessoas e perfis vinculados à obra',
                    style: TextStyle(color: _apoio, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  if (_obras.isNotEmpty)
                    Semantics(
                      identifier: 'equipe-obra',
                      container: true,
                      child: DropdownButton<int>(
                        value: _obra,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: _tinta, fontSize: 14),
                        iconEnabledColor: _tinta,
                        items: [
                          for (final obra in _obras)
                            DropdownMenuItem(
                              value: obra.id,
                              child: Text(
                                obra.nome,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (obra) {
                          if (obra == null) return;
                          setState(() {
                            _obra = obra;
                            _busca.clear();
                          });
                          _carregar();
                        },
                      ),
                    ),
                  const Divider(color: _tinta, thickness: 2, height: 28),
                  Semantics(
                    identifier: 'equipe-busca',
                    container: true,
                    child: TextField(
                      controller: _busca,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: _tinta),
                      cursorColor: _tinta,
                      decoration: InputDecoration(
                        labelText: 'Buscar pessoa ou perfil',
                        labelStyle: const TextStyle(color: _apoio),
                        prefixIcon: const Icon(Icons.search, color: _tinta),
                        fillColor: Colors.white,
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _tinta),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _tinta, width: 2),
                        ),
                        suffixIcon: _busca.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar busca',
                                icon: const Icon(Icons.close, color: _tinta),
                                onPressed: () => setState(_busca.clear),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    color: _tinta,
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'PESSOAS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!_carregando && _erro == null)
                          Text(
                            '${_filtradas.length} de ${_pessoas.length}',
                            style: const TextStyle(color: _amarelo),
                          ),
                      ],
                    ),
                  ),
                  if (_carregando)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: _tinta),
                      ),
                    )
                  else if (_erro != null)
                    _aviso(_erro!, tentar: true)
                  else if (_obras.isEmpty)
                    _aviso('Nenhuma obra disponível para consultar a equipe.')
                  else if (_pessoas.isEmpty)
                    _aviso('Esta obra ainda não tem equipe vinculada.')
                  else if (_filtradas.isEmpty)
                    _aviso('Nenhuma pessoa encontrada para esta busca.')
                  else ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'NOME',
                              style: TextStyle(color: _apoio, fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'PERFIL',
                              style: TextStyle(color: _apoio, fontSize: 12),
                            ),
                          ),
                          SizedBox(width: 24),
                        ],
                      ),
                    ),
                    for (var i = 0; i < _filtradas.length; i++)
                      _pessoa(_filtradas[i], i),
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Toque em uma pessoa para ver seu perfil.',
                        style: TextStyle(color: _apoio, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pessoa(PessoaEquipe pessoa, int indice) => Semantics(
    identifier: 'equipe-pessoa',
    container: true,
    button: true,
    child: Material(
      color: indice.isEven ? Colors.white : const Color(0xFFEAEAEA),
      child: InkWell(
        onTap: () => _mostrarPerfil(pessoa),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  pessoa.nome,
                  style: const TextStyle(
                    color: _tinta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  pessoa.papel,
                  style: const TextStyle(color: _tinta, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: _tinta, size: 24),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _mostrarPerfil(PessoaEquipe pessoa) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        pessoa.nome,
        style: const TextStyle(color: _tinta, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: _amarelo,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                pessoa.papel,
                style: const TextStyle(
                  color: _tinta,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('E-mail', style: TextStyle(color: _apoio, fontSize: 12)),
            SelectableText(pessoa.email, style: const TextStyle(color: _tinta)),
            const SizedBox(height: 16),
            const Text(
              'Vínculo ativo nesta obra',
              style: TextStyle(color: _tinta),
            ),
            if (pessoa.desde != null)
              Text(
                'Desde ${pessoa.desde}',
                style: const TextStyle(color: _apoio),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar', style: TextStyle(color: _tinta)),
        ),
      ],
    ),
  );

  Widget _aviso(String texto, {bool tentar = false}) => Semantics(
    identifier: tentar ? 'equipe-erro' : 'equipe-vazio',
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
          if (tentar)
            TextButton(
              onPressed: () => _carregar(recarregarObras: true),
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
