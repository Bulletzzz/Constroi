import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../painel/painel_model.dart';
import 'nfe_file_picker.dart';
import 'nfe_preview.dart';
import 'nfe_service.dart';

class NfeScreen extends StatefulWidget {
  const NfeScreen({
    super.key,
    required this.service,
    required this.perfil,
    this.selecionarArquivo = escolherXml,
  });

  final NfeService service;
  final PerfilUsuario perfil;
  final EscolherXml selecionarArquivo;

  @override
  State<NfeScreen> createState() => _NfeScreenState();
}

class _NfeScreenState extends State<NfeScreen> {
  final _entrada = TextEditingController();
  final _rolagem = ScrollController();
  List<ObraPainel> _obras = const [];
  int? _obraId;
  bool _anexar = false;
  bool _carregando = true;
  bool _lendo = false;
  bool _enviando = false;
  bool _revisando = false;
  String? _erroObras;
  String? _erro;
  int? _statusErro;
  List<Map> _pendencias = const [];
  NfePreview? _nota;
  NfeResultado? _resultado;

  bool get _permitido => widget.perfil.possuiNivel(PerfilUsuario.engenheiro);
  bool get _ocupado => _lendo || _enviando;

  @override
  void initState() {
    super.initState();
    if (_permitido) _carregarObras();
  }

  @override
  void dispose() {
    _entrada.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _carregarObras() async {
    setState(() {
      _carregando = true;
      _erroObras = null;
    });
    try {
      final obras = await widget.service.obras();
      if (!mounted) return;
      setState(() {
        _obras = obras;
        _obraId = obras.length == 1 ? obras.first.id : null;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(
        () => _erroObras = erro is ApiException
            ? erro.message
            : 'Não foi possível carregar as obras. Confira a conexão e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _limparErro() {
    _erro = null;
    _statusErro = null;
    _pendencias = const [];
  }

  Future<void> _escolherArquivo() async {
    if (_ocupado) return;
    setState(() {
      _lendo = true;
      _limparErro();
    });
    try {
      final nota = await widget.selecionarArquivo();
      if (!mounted || nota == null) return;
      setState(() {
        _nota = nota;
        _revisando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        // Uma seleção inválida nunca deixa a nota anterior pronta para envio.
        _nota = null;
        _revisando = false;
        _erro = erro is FormatException
            ? erro.message
            : 'Não foi possível ler o arquivo. Escolha o XML novamente.';
      });
    } finally {
      if (mounted) setState(() => _lendo = false);
    }
  }

  int? get _entradaId {
    final valor = _entrada.text.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(valor)) return null;
    final id = int.tryParse(valor);
    return id != null && id > 0 && id <= 2147483647 ? id : null;
  }

  void _revisar() {
    if (_ocupado) return;
    setState(() {
      _limparErro();
      if (_anexar && _entradaId == null) {
        _erro = 'Informe o número de uma entrada existente, maior que zero.';
      } else if (!_anexar && _obraId == null) {
        _erro = 'Escolha a obra que receberá os materiais.';
      } else if (_nota == null) {
        _erro = 'Escolha o arquivo XML da NF-e.';
      } else {
        _revisando = true;
      }
    });
    if (_revisando) _mostrarInicio();
  }

  void _mostrarInicio() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rolagem.hasClients) _rolagem.jumpTo(0);
    });
  }

  Future<void> _confirmar() async {
    if (_ocupado || !_permitido || !_revisando || _nota == null) return;
    setState(() {
      _enviando = true;
      _limparErro();
    });
    try {
      final resultado = _anexar
          ? await widget.service.anexar(_nota!, _entradaId!)
          : await widget.service.importar(_nota!, _obraId!);
      if (!mounted) return;
      setState(() => _resultado = resultado);
      _mostrarInicio();
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = erro.message;
        _statusErro = erro.statusCode;
        final pendencias = erro.details['materiais_pendentes'];
        _pendencias = pendencias is List
            ? pendencias.whereType<Map>().toList()
            : const [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro =
            'Não foi possível confirmar o resultado. Confira a conexão e '
            'se a nota já foi registrada antes de tentar novamente.';
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _voltar() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoute.estoque.caminho);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTheme.accent,
        primary: AppTheme.background,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F2F2),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.background,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
    return Theme(
      data: tema,
      child: PopScope(
        canPop: !_enviando,
        child: Scaffold(
          appBar: AppHeader(perfil: widget.perfil),
          body: !_permitido
              ? const Center(
                  child: Text('Acesso exclusivo de engenheiro e master.'),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: ListView(
                      controller: _rolagem,
                      key: const ValueKey('nfe-rolagem'),
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Importação de NF-e',
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.15,
                            color: AppTheme.background,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Confira os materiais da nota antes de registrar a entrada.',
                        ),
                        const SizedBox(height: 24),
                        if (_resultado != null)
                          _sucesso()
                        else ...[
                          if (!_revisando) _formulario() else _revisao(),
                          if (_erro != null) ...[
                            const SizedBox(height: 20),
                            _falha(),
                          ],
                          const SizedBox(height: 24),
                          if (_revisando)
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _id(
                                  'nfe-confirmar',
                                  ElevatedButton(
                                    onPressed: _ocupado ? null : _confirmar,
                                    child: Text(
                                      _enviando
                                          ? 'Enviando XML…'
                                          : _anexar
                                          ? 'Confirmar anexo'
                                          : 'Confirmar importação',
                                    ),
                                  ),
                                ),
                                _id(
                                  'nfe-editar',
                                  OutlinedButton(
                                    onPressed: _ocupado
                                        ? null
                                        : () => setState(() {
                                            _revisando = false;
                                            _limparErro();
                                          }),
                                    child: const Text('Alterar dados'),
                                  ),
                                ),
                              ],
                            )
                          else
                            _id(
                              'nfe-revisar',
                              ElevatedButton(
                                onPressed:
                                    _ocupado ||
                                        (!_anexar &&
                                            (_carregando ||
                                                _erroObras != null ||
                                                _obras.isEmpty))
                                    ? null
                                    : _revisar,
                                child: const Text('Revisar materiais'),
                              ),
                            ),
                          if (_enviando) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _formulario() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _id(
            'nfe-modo-importar',
            ChoiceChip(
              label: const Text('Nova entrada'),
              selected: !_anexar,
              onSelected: _ocupado
                  ? null
                  : (_) => setState(() {
                      _anexar = false;
                      _limparErro();
                    }),
            ),
          ),
          _id(
            'nfe-modo-anexar',
            ChoiceChip(
              label: const Text('Anexar a uma entrada'),
              selected: _anexar,
              onSelected: _ocupado
                  ? null
                  : (_) => setState(() {
                      _anexar = true;
                      _limparErro();
                    }),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (_anexar) ...[
        _id(
          'nfe-entrada',
          TextField(
            controller: _entrada,
            enabled: !_ocupado,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Número da entrada existente',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'A obra será a da entrada informada. O anexo guarda a nota '
          'sem alterar os materiais ou o saldo já registrado.',
        ),
      ] else if (_carregando)
        const LinearProgressIndicator()
      else if (_erroObras != null)
        _id(
          'nfe-obras-erro',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_erroObras!),
              _id(
                'nfe-obras-tentar',
                TextButton(
                  onPressed: _carregarObras,
                  child: const Text('Carregar obras novamente'),
                ),
              ),
            ],
          ),
        )
      else if (_obras.isEmpty)
        _id(
          'nfe-obras-vazio',
          const Text(
            'Nenhuma obra disponível. Cadastre uma obra antes de importar.',
          ),
        )
      else
        _id(
          'nfe-obra',
          DropdownButtonFormField<int>(
            initialValue: _obraId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Obra de destino'),
            items: [
              for (final obra in _obras)
                DropdownMenuItem(
                  value: obra.id,
                  child: Text(obra.nome, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _ocupado
                ? null
                : (valor) => setState(() {
                    _obraId = valor;
                    _limparErro();
                  }),
          ),
        ),
      const SizedBox(height: 24),
      _id(
        'nfe-arquivo',
        OutlinedButton.icon(
          onPressed: _ocupado ? null : _escolherArquivo,
          icon: const Icon(Icons.upload_file),
          label: Text(
            _lendo
                ? 'Lendo XML…'
                : _nota == null
                ? 'Escolher arquivo XML'
                : 'Trocar arquivo XML',
          ),
        ),
      ),
      const SizedBox(height: 8),
      _id(
        'nfe-arquivo-nome',
        Text(_nota?.nomeArquivo ?? 'XML de NF-e em UTF-8, até 2 MiB.'),
      ),
      if (_nota != null) ...[
        const SizedBox(height: 8),
        Text(
          '${_nota!.materiais.length} material(is) lido(s). Revise antes de confirmar.',
        ),
      ],
    ],
  );

  Widget _revisao() {
    final nota = _nota!;
    final obra = _obras.where((o) => o.id == _obraId).firstOrNull;
    return _id(
      'nfe-previa',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _anexar
                ? 'Anexar à entrada #${_entradaId!}'
                : 'Destino: ${obra?.nome ?? _obraId}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(nota.nomeArquivo),
          const SizedBox(height: 8),
          const Text(
            'Chave da NF-e',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          _id('nfe-chave', Text(nota.chave)),
          const SizedBox(height: 16),
          Text(
            _anexar
                ? 'Confira se esta é a nota da entrada informada. O anexo não compara '
                      'os materiais com o lançamento existente e não altera o estoque.'
                : 'A confirmação criará uma entrada e somará as quantidades ao estoque '
                      'da obra. O catálogo será conferido no envio.',
          ),
          const SizedBox(height: 24),
          Text(
            'Materiais do XML (${nota.materiais.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final material in nota.materiais)
            _id(
              'nfe-material',
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFD1D1D1))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.nome,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text('Código: ${material.codigo}'),
                    Text(
                      'Quantidade: ${material.quantidade.replaceAll('.', ',')} ${material.unidade}',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _falha() => _id(
    _statusErro == 409 ? 'nfe-conflito' : 'nfe-erro',
    Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFFFDAD6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_erro!, style: const TextStyle(color: Color(0xFF690005))),
          if (_statusErro == 422 && _pendencias.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Materiais pendentes no catálogo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final material in _pendencias)
              _id(
                'nfe-material-pendente',
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${material['nome'] ?? 'Material'}\n'
                    'Código: ${material['codigo'] ?? '—'} · Unidade: ${material['unidade'] ?? '—'}\n'
                    '${_motivo(material['motivo'])}',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Corrija o cadastro dos materiais no catálogo e confirme novamente.',
            ),
          ],
        ],
      ),
    ),
  );

  String _motivo(Object? motivo) => switch (motivo) {
    'nao_encontrado' => 'Material não encontrado.',
    'ambiguo' => 'Mais de um material corresponde a este nome ou código.',
    'unidade_diferente' => 'A unidade da nota difere da unidade cadastrada.',
    _ => 'Confira o cadastro deste material.',
  };

  Widget _sucesso() => _id(
    'nfe-sucesso',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.check_circle_outline,
            size: 44,
            color: Color(0xFF246A36),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _anexar ? 'XML anexado com sucesso.' : 'NF-e importada com sucesso.',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text('Entrada #${_resultado!.id} · Obra #${_resultado!.obraId}'),
        const SizedBox(height: 8),
        Text(
          _anexar
              ? 'Os materiais e saldos da entrada foram mantidos.'
              : 'Os materiais foram adicionados ao estoque da obra.',
        ),
        const SizedBox(height: 24),
        _id(
          'nfe-concluir',
          ElevatedButton(
            onPressed: _voltar,
            child: const Text('Voltar ao estoque'),
          ),
        ),
      ],
    ),
  );

  Widget _id(String identificador, Widget child) =>
      Semantics(identifier: identificador, container: true, child: child);
}
