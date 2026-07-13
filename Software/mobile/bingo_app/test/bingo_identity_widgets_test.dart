import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/b1n_context_message.dart';
import 'package:bingo_app/src/widgets/bincoin_amount.dart';
import 'package:bingo_app/src/widgets/impact_comparison.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(
  Widget child, {
  double width = 390,
  double height = 844,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
}

void main() {
  testWidgets('BinCoin amount uses official asset, formatting and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const BinCoinAmount(value: 1190, size: 32)),
    );

    expect(find.bySemanticsLabel('1190 BinCoins'), findsOneWidget);
    expect(find.text('1.190'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as AssetImage;
    expect(provider.assetName, AppAssets.bincoinV2);
    expect(image.width, 32);
    expect(image.height, 32);
    expect(image.fit, BoxFit.contain);
  });

  test('BinCoin amount rejects negative values', () {
    expect(() => BinCoinAmount(value: -1), throwsAssertionError);
  });

  testWidgets('large BinCoin value scales without losing semantics', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const viewports = [(390.0, 844.0), (430.0, 932.0), (1024.0, 768.0)];

    for (final viewport in viewports) {
      _setViewport(tester, viewport.$1, viewport.$2);
      await tester.pumpWidget(
        _testApp(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 104,
              child: BinCoinAmount(value: 123456789, size: 32),
            ),
          ),
          width: viewport.$1,
          height: viewport.$2,
          textScale: 2,
        ),
      );

      expect(find.text('123.456.789'), findsOneWidget);
      expect(find.bySemanticsLabel('123456789 BinCoins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('context message renders one character and one message', (
    tester,
  ) async {
    const message = 'Estamos perto de recuperar outro setor!';

    await tester.pumpWidget(
      _testApp(
        const B1nContextMessage(
          asset: AppAssets.b1nIdeaInstruction,
          message: message,
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long compact message supports target viewports and text scale', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const viewports = [(390.0, 844.0), (430.0, 932.0), (1024.0, 768.0)];

    for (final viewport in viewports) {
      _setViewport(tester, viewport.$1, viewport.$2);
      await tester.pumpWidget(
        _testApp(
          const B1nContextMessage(
            asset: AppAssets.b1nIdeaInstruction,
            message:
                'Cada descarte validado ajuda a escola a recuperar setores da cidade e construir um impacto coletivo duradouro.',
            tone: AppColors.green,
            compact: true,
          ),
          width: viewport.$1,
          height: viewport.$2,
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('impact comparison uses equal 16:9 frames without default crop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const ImpactComparison(
          beforeImage: AppAssets.sceneCorrupt,
          nowImage: AppAssets.sceneClean,
        ),
      ),
    );

    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Agora'), findsOneWidget);
    expect(find.byType(AspectRatio), findsNWidgets(2));
    final frameFinders = [
      find.byType(AspectRatio).first,
      find.byType(AspectRatio).last,
    ];
    expect(tester.getSize(frameFinders[0]), tester.getSize(frameFinders[1]));
    expect(tester.widget<AspectRatio>(frameFinders[0]).aspectRatio, 16 / 9);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(images.every((image) => image.fit == BoxFit.contain), isTrue);
    expect(find.bySemanticsLabel('Antes'), findsOneWidget);
    expect(find.bySemanticsLabel('Agora'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('impact comparison supports independent image framing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const ImpactComparison(
          beforeImage: AppAssets.sceneCorrupt,
          nowImage: AppAssets.sceneClean,
          beforeFit: BoxFit.cover,
          nowFit: BoxFit.fitWidth,
          beforeAlignment: Alignment.centerLeft,
          nowAlignment: Alignment.topRight,
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images[0].fit, BoxFit.cover);
    expect(images[0].alignment, Alignment.centerLeft);
    expect(images[1].fit, BoxFit.fitWidth);
    expect(images[1].alignment, Alignment.topRight);
  });

  testWidgets('impact comparison avoids overflow in target viewports', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const viewports = [(390.0, 844.0), (430.0, 932.0), (1024.0, 768.0)];

    for (final viewport in viewports) {
      _setViewport(tester, viewport.$1, viewport.$2);
      await tester.pumpWidget(
        _testApp(
          const ImpactComparison(
            beforeImage: AppAssets.sceneCorrupt,
            nowImage: AppAssets.sceneClean,
            beforeLabel: 'Antes da mobilizacao escolar',
            nowLabel: 'Agora com o descarte correto',
          ),
          width: viewport.$1,
          height: viewport.$2,
          textScale: 2,
        ),
      );

      expect(find.text('Antes da mobilizacao escolar'), findsOneWidget);
      expect(find.text('Agora com o descarte correto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
