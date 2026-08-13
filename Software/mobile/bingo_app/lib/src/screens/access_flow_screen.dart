import 'package:flutter/material.dart';

import '../auth/auth_gateway.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/b1n_guide.dart';
import '../widgets/bingo_action_button.dart';

typedef SignInCallback =
    Future<AuthFailure?> Function(String email, String password);

class AccessFlowScreen extends StatefulWidget {
  const AccessFlowScreen({
    required this.onSignIn,
    required this.onEnterPilot,
    super.key,
  });

  final SignInCallback onSignIn;
  final VoidCallback onEnterPilot;

  @override
  State<AccessFlowScreen> createState() => _AccessFlowScreenState();
}

class _AccessFlowScreenState extends State<AccessFlowScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _showLogin = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      !_submitting;

  Future<void> _signIn() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final failure = await widget.onSignIn(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure.message;
    });
  }

  void _enterPilot() {
    widget.onEnterPilot();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _showLogin
            ? IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                        _showLogin = false;
                        _error = null;
                      }),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: _showLogin ? _buildLogin() : _buildHub(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHub() {
    return Column(
      key: const ValueKey('access-hub'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Como você quer entrar?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'A conta demo usa uma sessão real. O modo piloto funciona apenas com dados locais simulados.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nIdeaInstruction,
          title: 'Dois modos, dados separados',
          message:
              'O piloto nunca consulta a nuvem e a conta autenticada nunca usa os mocks.',
          tone: AppColors.blue,
        ),
        const SizedBox(height: 22),
        BingoActionButton(
          label: 'Entrar com conta demo',
          icon: Icons.cloud_outlined,
          tone: BingoActionTone.green,
          onPressed: () => setState(() => _showLogin = true),
        ),
        const SizedBox(height: 12),
        BingoActionButton(
          label: 'Entrar no modo piloto',
          style: BingoActionStyle.quiet,
          icon: Icons.science_outlined,
          onPressed: _enterPilot,
        ),
      ],
    );
  }

  Widget _buildLogin() {
    return AutofillGroup(
      child: Column(
        key: const ValueKey('remote-sign-in'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conta demo autenticada',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Use o e-mail e a senha provisionados no Supabase Auth.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('auth-email'),
            controller: _emailController,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-mail'),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('auth-password'),
            controller: _passwordController,
            enabled: !_submitting,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(labelText: 'Senha'),
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('auth-error'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 22),
          BingoActionButton(
            label: _submitting ? 'Entrando...' : 'Entrar',
            icon: Icons.login_rounded,
            tone: BingoActionTone.green,
            onPressed: _canSubmit ? _signIn : null,
          ),
          const SizedBox(height: 10),
          Text(
            'Não há cadastro público nesta etapa. A senha não é armazenada pelo aplicativo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
