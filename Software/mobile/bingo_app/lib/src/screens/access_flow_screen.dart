import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/b1n_guide.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/pin_keypad.dart';
import 'shell_screen.dart';

enum _AccessStage { hub, identify, createPin, confirmPin, signIn, resetPin, success }

enum _AccessIntent { create, reset }

class AccessFlowScreen extends StatefulWidget {
  const AccessFlowScreen({this.repository, super.key});

  final ProfileRepository? repository;

  @override
  State<AccessFlowScreen> createState() => _AccessFlowScreenState();
}

class _AccessFlowScreenState extends State<AccessFlowScreen> {
  final _schoolController = TextEditingController();
  final _identifierController = TextEditingController();
  ProfileRepository? _repository;
  _AccessStage _stage = _AccessStage.hub;
  _AccessIntent _intent = _AccessIntent.create;
  String _pin = '';
  String _firstPin = '';
  String? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    if (_repository == null) {
      _loadRepository();
    }
  }

  Future<void> _loadRepository() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _repository = LocalProfileRepository(preferences));
    }
  }

  @override
  void dispose() {
    _schoolController.dispose();
    _identifierController.dispose();
    super.dispose();
  }

  bool get _hasIdentity {
    return _schoolController.text.trim().isNotEmpty &&
        _identifierController.text.trim().isNotEmpty;
  }

  void _startIdentity(_AccessIntent intent) {
    setState(() {
      _intent = intent;
      _error = null;
      _pin = '';
      _firstPin = '';
      _stage = _AccessStage.identify;
    });
  }

  void _continueFromIdentity() {
    if (!_hasIdentity) return;
    setState(() {
      _error = null;
      _pin = '';
      _stage = _intent == _AccessIntent.create
          ? _AccessStage.createPin
          : _AccessStage.resetPin;
    });
  }

  void _continueFromPin() {
    if (_pin.length != 4) return;
    setState(() {
      _firstPin = _pin;
      _pin = '';
      _error = null;
      _stage = _AccessStage.confirmPin;
    });
  }

  Future<void> _confirmPin() async {
    if (_pin.length != 4) return;
    if (_pin != _firstPin) {
      setState(() {
        _error = 'Os dois PINs precisam ser iguais.';
        _pin = '';
      });
      return;
    }

    setState(() => _submitting = true);
    final profile = StudentProfile(
      school: _schoolController.text.trim(),
      identifier: _identifierController.text.trim(),
    );
    final repository = _repository!;
    final reset = _intent == _AccessIntent.reset;
    final accepted = reset
        ? await repository.resetPin(
            school: profile.school,
            identifier: profile.identifier,
            newPin: _pin,
          )
        : true;

    if (!mounted) return;
    if (!accepted) {
      setState(() {
        _submitting = false;
        _error = 'Não encontrei esse cadastro neste aparelho.';
        _stage = _AccessStage.identify;
      });
      return;
    }

    if (!reset) {
      await repository.save(profile: profile, pin: _pin);
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _stage = _AccessStage.success;
    });
  }

  Future<void> _signIn() async {
    if (!_hasIdentity || _pin.length != 4) return;
    setState(() => _submitting = true);
    final accepted = await _repository!.verify(
      school: _schoolController.text.trim(),
      identifier: _identifierController.text.trim(),
      pin: _pin,
    );
    if (!mounted) return;
    if (!accepted) {
      setState(() {
        _submitting = false;
        _error = 'Esses dados ou PIN não conferem.';
        _pin = '';
      });
      return;
    }
    _openApp();
  }

  void _openApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => ShellScreen(repository: _repository),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_repository == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final content = switch (_stage) {
      _AccessStage.hub => _buildHub(),
      _AccessStage.identify => _buildIdentity(),
      _AccessStage.createPin || _AccessStage.resetPin => _buildPin(),
      _AccessStage.confirmPin => _buildConfirmation(),
      _AccessStage.signIn => _buildSignIn(),
      _AccessStage.success => _buildSuccess(),
    };

    return Scaffold(
      appBar: AppBar(
        leading: _stage == _AccessStage.hub
            ? null
            : IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _error = null;
                  _pin = '';
                  _stage = _stage == _AccessStage.createPin ||
                          _stage == _AccessStage.resetPin
                      ? _AccessStage.identify
                      : _stage == _AccessStage.confirmPin
                      ? (_intent == _AccessIntent.create
                            ? _AccessStage.createPin
                            : _AccessStage.resetPin)
                      : _AccessStage.hub;
                }),
              ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: AnimatedSwitcher(
                duration: Duration(
                  milliseconds:
                      MediaQuery.of(context).disableAnimations ? 0 : AppMotion.standard,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHub() {
    return Column(
      key: const ValueKey('access-hub'),
      children: [
        Text('Vamos entrar em ação?', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Seu PIN identifica você no Totem e acompanha seu caminho no BinGo.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nIdeaInstruction,
          title: 'B1N está pronto',
          message: 'Crie seu PIN uma vez. Depois, ele abre seu caminho no Totem.',
          tone: AppColors.blue,
        ),
        const SizedBox(height: 22),
        BingoActionButton(
          label: 'Criar meu PIN',
          icon: Icons.lock_outline_rounded,
          tone: BingoActionTone.green,
          onPressed: () => _startIdentity(_AccessIntent.create),
        ),
        const SizedBox(height: 12),
        BingoActionButton(
          label: 'Já tenho PIN',
          icon: Icons.login_rounded,
          style: BingoActionStyle.secondary,
          onPressed: () => setState(() {
            _error = null;
            _pin = '';
            _stage = _AccessStage.signIn;
          }),
        ),
        const SizedBox(height: 12),
        BingoActionButton(
          label: 'Entrar no modo piloto',
          style: BingoActionStyle.quiet,
          icon: Icons.science_outlined,
          onPressed: _openApp,
        ),
      ],
    );
  }

  Widget _buildIdentity() {
    final isReset = _intent == _AccessIntent.reset;
    return Column(
      key: const ValueKey('identify'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isReset ? 'Vamos recuperar seu acesso' : 'Primeiro, me conta quem você é',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          isReset
              ? 'Confirme os mesmos dados usados no cadastro deste aparelho.'
              : 'Esses dados aparecem no seu perfil e no Totem.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        B1nGuide(
          asset: isReset ? AppAssets.b1nQuestion : AppAssets.b1nIdeaInstruction,
          title: isReset ? 'Vamos resolver isso' : 'É rápido',
          message: isReset
              ? 'Depois voce escolhe um novo PIN.'
              : 'Use seu nome ou matrícula como a escola combinou.',
          compact: true,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _schoolController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Escola', hintText: 'ENIAC'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _identifierController,
          decoration: const InputDecoration(labelText: 'Nome ou matrícula'),
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 22),
        BingoActionButton(
          label: 'Continuar',
          tone: BingoActionTone.green,
          icon: Icons.arrow_forward_rounded,
          onPressed: _hasIdentity ? _continueFromIdentity : null,
        ),
      ],
    );
  }

  Widget _buildPin() {
    final isReset = _stage == _AccessStage.resetPin;
    return Column(
      key: ValueKey(isReset ? 'reset-pin' : 'create-pin'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isReset ? 'Escolha seu novo PIN' : 'Crie seu PIN de 4 números',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text('Ele será usado para entrar no Totem.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nPinPrivacy,
          title: 'Só você vê seu PIN',
          message: 'B1N fecha os olhos para proteger sua escolha.',
          tone: AppColors.blue,
          compact: true,
        ),
        const SizedBox(height: 22),
        PinKeypad(value: _pin, onChanged: (value) => setState(() => _pin = value)),
        const SizedBox(height: 20),
        BingoActionButton(
          label: 'Continuar',
          tone: BingoActionTone.green,
          onPressed: _pin.length == 4 ? _continueFromPin : null,
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    return Column(
      key: const ValueKey('confirm-pin'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Confirme seu PIN', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Digite os mesmos 4 números mais uma vez.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nPinPrivacy,
          title: 'Sem pressa',
          message: 'Eu continuo de olhos fechados.',
          compact: true,
        ),
        const SizedBox(height: 22),
        PinKeypad(
          value: _pin,
          errorText: _error,
          onChanged: (value) => setState(() {
            _error = null;
            _pin = value;
          }),
        ),
        const SizedBox(height: 20),
        BingoActionButton(
          label: _submitting ? 'Guardando...' : 'Confirmar PIN',
          tone: BingoActionTone.green,
          onPressed: _pin.length == 4 && !_submitting ? _confirmPin : null,
        ),
      ],
    );
  }

  Widget _buildSignIn() {
    return Column(
      key: const ValueKey('sign-in'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bom te ver de novo', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Use os dados e o PIN deste aparelho.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nThumbsUp,
          title: 'B1N lembra do caminho',
          message: 'Seu PIN continua privado.',
          compact: true,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _schoolController,
          decoration: const InputDecoration(labelText: 'Escola'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _identifierController,
          decoration: const InputDecoration(labelText: 'Nome ou matrícula'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        PinKeypad(
          value: _pin,
          errorText: _error,
          onChanged: (value) => setState(() {
            _error = null;
            _pin = value;
          }),
        ),
        const SizedBox(height: 20),
        BingoActionButton(
          label: _submitting ? 'Entrando...' : 'Entrar no BinGo',
          icon: Icons.login_rounded,
          onPressed: _hasIdentity && _pin.length == 4 && !_submitting ? _signIn : null,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => _startIdentity(_AccessIntent.reset),
            child: const Text('Esqueci meu PIN'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final wasReset = _intent == _AccessIntent.reset;
    return Column(
      key: const ValueKey('access-success'),
      children: [
        Text(
          wasReset ? 'PIN atualizado!' : 'Tudo pronto!',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          wasReset
              ? 'Seu novo PIN já pode ser usado no Totem.'
              : 'Seu PIN abre caminho no Totem.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        const B1nGuide(
          asset: AppAssets.b1nThumbsUp,
          title: 'Mandou bem!',
          message: 'Agora vamos recuperar BinGópolis juntos.',
          tone: AppColors.green,
        ),
        const SizedBox(height: 22),
        BingoActionButton(
          label: 'Entrar no BinGo',
          icon: Icons.arrow_forward_rounded,
          tone: BingoActionTone.green,
          onPressed: _openApp,
        ),
      ],
    );
  }
}
