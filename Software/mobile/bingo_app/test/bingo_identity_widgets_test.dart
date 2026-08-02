import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/b1n_dialogue_strip.dart';
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

  testWidgets('BinCoin amount can hide its icon without losing its contract', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const BinCoinAmount(value: 1190, showIcon: false)),
    );

    expect(find.byType(BinCoinIcon), findsNothing);
    expect(find.text('1.190'), findsOneWidget);
    expect(find.bySemanticsLabel('1190 BinCoins'), findsOneWidget);
  });

  testWidgets('large BinCoin value abbreviates without losing semantics', (
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

      expect(find.text('123,5 mi'), findsOneWidget);
      expect(find.bySemanticsLabel('123456789 BinCoins'), findsOneWidget);
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('BinCoin typography grows with text scale', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const amount = Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 104,
        child: BinCoinAmount(value: 123456789, size: 32),
      ),
    );
    const viewports = [(390.0, 844.0), (430.0, 932.0), (1024.0, 768.0)];

    for (final viewport in viewports) {
      _setViewport(tester, viewport.$1, viewport.$2);
      await tester.pumpWidget(
        _testApp(amount, width: viewport.$1, height: viewport.$2),
      );
      final baseHeight = tester.getSize(find.text('123,5 mi')).height;

      await tester.pumpWidget(
        _testApp(amount, width: viewport.$1, height: viewport.$2, textScale: 2),
      );
      final scaledHeight = tester.getSize(find.text('123,5 mi')).height;

      expect(scaledHeight, greaterThanOrEqualTo(baseHeight * 2));
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dialogue strip renders one avatar, speaker and message', (
    tester,
  ) async {
    const message = 'Estamos perto de recuperar outro setor!';

    await tester.pumpWidget(_testApp(const B1nDialogueStrip(message: message)));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('B1N'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(find.bySemanticsLabel('B1N diz: $message'), findsOneWidget);
    final avatar = tester.widget<Image>(find.byType(Image));
    expect(avatar.fit, BoxFit.contain);
    expect(avatar.alignment, Alignment.center);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialogue strip uses the contextual B1N pose', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const B1nDialogueStrip(
          message: 'Vamos pensar juntos.',
          asset: AppAssets.b1nQuestion,
        ),
      ),
    );

    final avatar = tester.widget<Image>(find.byType(Image));
    expect((avatar.image as AssetImage).assetName, AppAssets.b1nQuestion);
    expect(avatar.alignment, Alignment.topCenter);
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
          const B1nDialogueStrip(
            message:
                'Cada descarte validado ajuda a escola a recuperar setores da cidade e construir um impacto coletivo duradouro.',
            tone: AppColors.green,
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
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('impact labels grow with text scale and can wrap', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const beforeLabel = 'Antes da mobilizacao escolar';
    const comparison = ImpactComparison(
      beforeImage: AppAssets.sceneCorrupt,
      nowImage: AppAssets.sceneClean,
      beforeLabel: beforeLabel,
      nowLabel: 'Agora com o descarte correto',
    );
    const viewports = [(390.0, 844.0), (430.0, 932.0), (1024.0, 768.0)];

    for (final viewport in viewports) {
      _setViewport(tester, viewport.$1, viewport.$2);
      await tester.pumpWidget(
        _testApp(comparison, width: viewport.$1, height: viewport.$2),
      );
      final baseHeight = tester.getSize(find.text(beforeLabel)).height;

      await tester.pumpWidget(
        _testApp(
          comparison,
          width: viewport.$1,
          height: viewport.$2,
          textScale: 2,
        ),
      );
      final scaledHeight = tester.getSize(find.text(beforeLabel)).height;

      expect(scaledHeight, greaterThan(baseHeight));
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
