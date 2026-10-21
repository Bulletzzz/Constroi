import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../navigation/app_bottom_navigation.dart';
import '../../navigation/app_route.dart';
import '../../navigation/perfil_usuario.dart';
import '../../widgets/app_header.dart';
import 'custos_model.dart';
import 'custos_service.dart';

const _tinta = Color(0xFF1A1C1C);
const _fundo = Color(0xFFF2F2F2);
const _amarelo = Color(0xFFFFD700);
const _apoio = Color(0xFF5E5E5E);
const _vermelho = Color(0xFFBA1A1A);

class CustosScreen extends StatefulWidget {
  const CustosScreen({super.key, required this.service, required this.perfil});
  final CustosService service;
  final PerfilUsuario perfil;

  @override
  State<CustosScreen> createState() => _CustosScreenState();
}

class _CustosScreenState extends State<CustosScreen> {
  DadosCustos? _dados;
  List<ObraCusto> _obras = [];
  final _lancamentos = <LancamentoCusto>[];
  int? _obra;
  String _periodo = 'total';
  int _consulta = 0;
  bool _carregando = true;
  bool _mais = false;
  bool _temMais = false;
  String? _erro;
  String? _erroPagina;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool mais = false}) async {
    final consulta = ++_consulta;
    setState(() {
      _erroPagina = null;
      _mais = mais;
      if (!mais) {
        _carregando = true;
        _erro = null;
      }
    });
    try {
      final dados = await widget.service.carregar(
        obraId: _obra,
        periodo: _periodo,
        offset: mais ? _lancamentos.length : 0,
      );
      if (!mounted || consulta != _consulta) return;
      setState(() {
        _dados = dados;
        _obras = dados.obras;
        if (!mais) _lancamentos.clear();
        _lancamentos.addAll(dados.lancamentos);
        _temMais = dados.temMais;
        _carregando = false;
        _mais = false;
      });
    } catch (erro) {
      if (!mounted || consulta != _consulta) return;
      setState(() {
        final mensagem = erro is ApiException
            ? erro.message
            : 'Não foi possível carregar os custos. Confira a conexão.';
        if (mais) {
          _erroPagina = mensagem;
        } else {
          _erro = mensagem;
        }
        _carregando = false;
        _mais = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    appBar: AppHeader(perfil: widget.perfil),
    bottomNavigationBar: AppBottomNavigation(
      rotaAtual: AppRoute.custos,
      perfil: widget.perfil,
    ),
    body: RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: DefaultTextStyle(
                style: const TextStyle(color: _tinta, fontSize: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'CUSTOS DA OBRA',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<int?>(
                      value: _obra,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: _tinta, fontSize: 14),
                      iconEnabledColor: _tinta,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas as obras'),
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
                      onChanged: (obra) {
                        setState(() => _obra = obra);
                        _carregar();
                      },
                    ),
                    const Divider(color: _tinta, thickness: 2, height: 24),
                    Row(
                      children: [
                        for (final periodo in const {
                          'semana': 'SEMANA',
                          'mes': 'MÊS',
                          'total': 'TOTAL',
                        }.entries)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _periodo == periodo.key
                                      ? _tinta
                                      : Colors.white,
                                  foregroundColor: _periodo == periodo.key
                                      ? _amarelo
                                      : _tinta,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: const BorderSide(color: _tinta),
                                  shape: const RoundedRectangleBorder(),
                                ),
                                onPressed: () {
                                  setState(() => _periodo = periodo.key);
                                  _carregar();
                                },
                                child: Text(periodo.value),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_carregando)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(color: _tinta),
                        ),
                      )
                    else if (_erro != null)
                      _aviso(_erro!, tentar: () => _carregar())
                    else if (_dados != null)
                      ..._conteudo(_dados!),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _conteudo(DadosCustos dados) => [
    if (dados.obras.isEmpty)
      _aviso('Nenhuma obra disponível para consultar custos.')
    else ...[
      Container(
        color: _tinta,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _periodo == 'total' ? 'CUSTO ACUMULADO' : 'CUSTO NO PERÍODO',
              style: const TextStyle(color: _amarelo, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              dinheiro(dados.resumo.periodo),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(switch (_periodo) {
              'semana' => 'Semana atual, a partir de segunda-feira',
              'mes' => 'Mês atual',
              _ => 'Materiais comprados e outras despesas',
            }, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _orcamento(dados.resumo),
      if (dados.semPreco > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${dados.semPreco} item(ns) de entrada sem preço. '
            'Esses itens ainda não entram nos totais.',
            style: const TextStyle(color: _apoio, height: 1.4),
          ),
        ),
      if (_obra == null) ...[
        _titulo('TOTAIS POR OBRA'),
        for (final total in dados.totais)
          _linha(
            total.nome,
            dinheiro(total.periodo),
            detalhe:
                'Acumulado: ${dinheiro(total.acumulado)} · '
                'Orçamento: ${total.orcamento == null ? 'não informado' : dinheiro(total.orcamento!)}',
          ),
      ],
      _titulo('CUSTO POR CATEGORIA'),
      if (dados.categorias.isEmpty)
        _aviso('Nenhum lançamento de custo neste período.')
      else
        for (final categoria in dados.categorias)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _linha(categoria.nome, dinheiro(categoria.valor)),
                LinearProgressIndicator(
                  value: double.parse(dados.resumo.periodo) > 0
                      ? (double.parse(categoria.valor) /
                                double.parse(dados.resumo.periodo))
                            .clamp(0, 1)
                      : 0,
                  color: _amarelo,
                  backgroundColor: const Color(0xFFDDDDDD),
                  minHeight: 6,
                ),
              ],
            ),
          ),
      _titulo('LANÇAMENTOS DO PERÍODO'),
      for (final item in _lancamentos)
        _linha(
          item.descricao,
          dinheiro(item.valor),
          detalhe: '${item.dataFormatada} · ${item.obra}\n${item.categoria}',
        ),
      if (_erroPagina != null)
        _aviso(_erroPagina!, tentar: () => _carregar(mais: true))
      else if (_temMais)
        TextButton(
          onPressed: _mais ? null : () => _carregar(mais: true),
          child: Text(
            _mais ? 'Carregando…' : 'Carregar mais',
            style: const TextStyle(color: _tinta),
          ),
        ),
    ],
  ];

  Widget _orcamento(ResumoCusto resumo) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _tinta, width: 2)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ORÇAMENTO DA OBRA', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          resumo.orcamento == null
              ? 'Não informado para todas as obras'
              : dinheiro(resumo.orcamento!),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (resumo.percentual != null) ...[
          LinearProgressIndicator(
            value: (resumo.percentual! / 100).clamp(0, 1),
            color: resumo.percentual! > 100 ? _vermelho : _amarelo,
            backgroundColor: Colors.white,
            minHeight: 10,
          ),
          const SizedBox(height: 8),
          Text(
            '${resumo.percentual!.toStringAsFixed(1).replaceAll('.', ',')}% consumido',
            style: const TextStyle(color: _apoio),
          ),
        ],
        if (resumo.saldo != null)
          Text(
            'Saldo: ${dinheiro(resumo.saldo!)}',
            style: TextStyle(
              color: resumo.saldo!.startsWith('-') ? _vermelho : _apoio,
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'Orçamento e saldo consideram todo o histórico da obra.',
          style: TextStyle(color: _apoio, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _titulo(String texto) => Container(
    margin: const EdgeInsets.only(top: 18, bottom: 6),
    color: _tinta,
    padding: const EdgeInsets.all(12),
    child: Text(
      texto,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );

  Widget _linha(String nome, String valor, {String? detalhe}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 6,
          children: [
            Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(valor, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        if (detalhe != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              detalhe,
              style: const TextStyle(color: _apoio, fontSize: 12, height: 1.5),
            ),
          ),
      ],
    ),
  );

  Widget _aviso(String texto, {VoidCallback? tentar}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _apoio, height: 1.4),
        ),
        if (tentar != null)
          TextButton(
            onPressed: tentar,
            child: const Text(
              'Tentar novamente',
              style: TextStyle(color: _tinta),
            ),
          ),
      ],
    ),
  );
}
