import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';

const _fundo = Color(0xFFF2F2F2);
const _tinta = Color(0xFF1A1C1C);
const _cartao = Color(0xFFF9F9F9);
const _apoio = Color(0xFFD6D6D6);
const _avisoFundo = Color(0xFFE5E5E5);
const _destaque = Color(0xFFFFD700);
const _rotulo = Color(0xFF4D4732);
const _pontos = Color(0xFF6B7280);
const _linha = Color(0xFFE2E2E2);
const _textoRodape = Color(0xFF5E5E5E);
const _dica = Color(0xFF767676);
const _vermelho = Color(0xFFB3261E);

const _statusQueFalamComOperador = {403, 429};

TextStyle _mini(Color cor, [double espaco = 1.2]) => TextStyle(
  color: cor,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: espaco,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _focoEmail = FocusNode();
  final _focoSenha = FocusNode();

  bool _manterSessao = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _focoEmail.dispose();
    _focoSenha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_enviando) return;

    final email = _email.text.trim();
    final senha = _senha.text;

    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe o e-mail e a senha.');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await widget.auth.entrar(
        email: email,
        senha: senha,
        manterSessao: _manterSessao,
      );
      if (!mounted) return;
      setState(() => _enviando = false);
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = _mensagemParaOperador(erro);
        _enviando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível falar com o servidor. Confira a conexão.';
        _enviando = false;
      });
    }
  }

  String _mensagemParaOperador(ApiException erro) {
    if (erro.statusCode == 401) return 'E-mail ou senha inválidos.';
    if (_statusQueFalamComOperador.contains(erro.statusCode)) {
      return erro.message;
    }
    debugPrint('Falha no login (${erro.statusCode}): ${erro.message}');
    return 'Não foi possível entrar agora. Tente novamente em instantes.';
  }

  void _avisarRedefinicao() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A redefinição é feita pelo administrador da empresa.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _fundo,
    body: SafeArea(
      child: Column(
        children: [
          Container(
            height: 64,
            width: double.infinity,
            color: _tinta,
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/ConstroiLogoMarca.svg',
              height: 42,
              semanticsLabel: 'Constrói',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 358),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _cartao,
                      border: Border.all(color: _tinta, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_tampa(), _corpo(), _rodape()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tampa() => Container(
    height: 139,
    color: _tinta,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'ÁREA DE ACESSO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('AUTORIZAÇÃO NECESSÁRIA', style: _mini(_apoio, 1.7)),
      ],
    ),
  );

  Widget _corpo() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _aviso(),
        const SizedBox(height: 30),
        Text('EMAIL DO OPERADOR', style: _mini(_rotulo)),
        const SizedBox(height: 8),
        _campo(
          controlador: _email,
          foco: _focoEmail,
          icone: Icons.badge,
          dica: 'operador@construtora.com',
          teclado: TextInputType.emailAddress,
          aoConcluir: () => _focoSenha.requestFocus(),
        ),
        const SizedBox(height: 22),
        Text('SENHA DE SEGURANÇA', style: _mini(_rotulo)),
        const SizedBox(height: 8),
        _campo(
          controlador: _senha,
          foco: _focoSenha,
          icone: Icons.key,
          dica: '',
          escondido: true,
          aoConcluir: _entrar,
        ),
        if (_erro != null) ...[
          const SizedBox(height: 12),
          Text(
            _erro!,
            style: const TextStyle(
              color: _vermelho,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 26),
        _opcoes(),
        const SizedBox(height: 30),
        _botao(),
        const SizedBox(height: 12),
      ],
    ),
  );

  Widget _aviso() => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(width: 4, color: _destaque),
        Expanded(
          child: Container(
            color: _avisoFundo,
            padding: const EdgeInsets.fromLTRB(17, 19, 23, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      const Icon(
                        Icons.warning_rounded,
                        color: _destaque,
                        size: 20,
                      ),
                      Positioned(
                        top: 9,
                        child: Container(width: 2.8, height: 6, color: _tinta),
                      ),
                      Positioned(
                        top: 16.4,
                        child: Container(
                          width: 2.8,
                          height: 2.4,
                          color: _tinta,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Sistema de acesso restrito. Entradas não autorizadas '
                    'são bloqueadas e registradas.',
                    style: TextStyle(color: _tinta, fontSize: 11, height: 1.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _campo({
    required TextEditingController controlador,
    required FocusNode foco,
    required IconData icone,
    required String dica,
    required VoidCallback aoConcluir,
    bool escondido = false,
    TextInputType teclado = TextInputType.text,
  }) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _tinta, width: 2),
    ),
    child: Row(
      children: [
        const SizedBox(width: 13),
        Icon(icone, size: 20, color: _rotulo),
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            controller: controlador,
            focusNode: foco,
            obscureText: escondido,
            keyboardType: teclado,
            enabled: !_enviando,
            onSubmitted: (_) => aoConcluir(),
            textInputAction: escondido
                ? TextInputAction.done
                : TextInputAction.next,
            style: TextStyle(
              color: escondido ? _pontos : _tinta,
              fontSize: 13,
              letterSpacing: escondido ? 5 : 0,
            ),
            decoration: InputDecoration.collapsed(
              hintText: dica,
              hintStyle: const TextStyle(color: _dica, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );

  Widget _opcoes() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 12,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _manterSessao,
              onChanged: _enviando
                  ? null
                  : (valor) => setState(() => _manterSessao = valor ?? false),
              fillColor: WidgetStateProperty.resolveWith(
                (estados) => estados.contains(WidgetState.selected)
                    ? _tinta
                    : Colors.white,
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
              'MANTER CONECTADO 8H',
              overflow: TextOverflow.ellipsis,
              style: _mini(_tinta),
            ),
          ),
        ],
      ),
      GestureDetector(
        onTap: _avisarRedefinicao,
        child: Text(
          'REDEFINIR SENHA',
          style: _mini(_tinta).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: _tinta,
            decorationThickness: 1.5,
          ),
        ),
      ),
    ],
  );

  Widget _botao() => SizedBox(
    height: 52,
    child: Material(
      color: _destaque,
      child: InkWell(
        onTap: _enviando ? null : _entrar,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: _tinta, width: 2)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 18),
                  child: Icon(Icons.arrow_forward, size: 20, color: _tinta),
                ),
              ),
              if (_enviando)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(_tinta),
                  ),
                )
              else
                const Text(
                  'ENTRAR',
                  style: TextStyle(
                    color: _tinta,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _rodape() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(height: 1.5, color: _linha),
      Container(
        color: _fundo,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        child: Text(
          'CONSTRÓI · SISTEMAS INTERNOS V2.4',
          style: _mini(_textoRodape),
        ),
      ),
    ],
  );
}
