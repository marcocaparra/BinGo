import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../widgets/b1n_guide.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import '../widgets/pin_keypad.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({
    required this.repository,
    required this.profile,
    super.key,
  });

  final ProfileRepository repository;
  final StudentProfile profile;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  String _pin = '';
  String _firstPin = '';
  String? _error;
  var _confirming = false;
  var _saving = false;

  void _continue() {
    if (_pin.length != 4) return;
    setState(() {
      _firstPin = _pin;
      _pin = '';
      _error = null;
      _confirming = true;
    });
  }

  Future<void> _save() async {
    if (_pin.length != 4) return;
    if (_pin != _firstPin) {
      setState(() {
        _pin = '';
        _error = 'Os dois PINs precisam ser iguais.';
      });
      return;
    }

    setState(() => _saving = true);
    final saved = await widget.repository.resetPin(
      school: widget.profile.school,
      identifier: widget.profile.identifier,
      newPin: _pin,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error = 'Não foi possível atualizar o PIN neste aparelho.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: _confirming ? 'Confirme seu novo PIN' : 'Crie seu novo PIN',
      subtitle: 'Ele continuará sendo usado para entrar no Totem.',
      dataStatus: AppDataStatus.local,
      child: Column(
        children: [
          B1nGuide(
            asset: AppAssets.b1nPinPrivacy,
            title: _confirming ? 'Mais uma vez' : 'Sua escolha é privada',
            message: _confirming
                ? 'Digite os mesmos quatro números.'
                : 'B1N fecha os olhos enquanto você escolhe.',
            compact: true,
            portrait: B1nPortraitVariant.question,
          ),
          const SizedBox(height: 20),
          PinKeypad(
            value: _pin,
            errorText: _error,
            onChanged: (value) => setState(() {
              _pin = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          BingoActionButton(
            label: _saving
                ? 'Atualizando...'
                : _confirming
                ? 'Atualizar PIN'
                : 'Continuar',
            tone: BingoActionTone.green,
            icon: _confirming
                ? Icons.check_rounded
                : Icons.arrow_forward_rounded,
            onPressed: _pin.length != 4 || _saving
                ? null
                : _confirming
                ? _save
                : _continue,
          ),
        ],
      ),
    );
  }
}
