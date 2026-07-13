import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/b1n_context_message.dart';
import 'package:bingo_app/src/widgets/bincoin_amount.dart';
import 'package:bingo_app/src/widgets/impact_comparison.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(Widget child, {double width = 390}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 844)),
      child: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('BinCoin amount uses the official asset and semantic label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const BinCoinAmount(value: 120, size: 32)),
    );

    expect(find.bySemanticsLabel('120 BinCoins'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as AssetImage;
    expect(provider.assetName, AppAssets.bincoinV2);
    expect(image.width, 32);
    expect(image.height, 32);
    expect(image.fit, BoxFit.contain);
  });

  testWidgets(
    'context message renders one character and one message at 390px',
    (tester) async {
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
    },
  );

  testWidgets('compact context message remains stable on a narrow screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const B1nContextMessage(
          asset: AppAssets.b1nThumbsUp,
          message: 'Boa! Seu descarte ja esta contando para a escola.',
          tone: AppColors.green,
          compact: true,
        ),
        width: 320,
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('impact comparison keeps matching frames and visible labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const ImpactComparison(
          beforeImage: AppAssets.sceneCorrupt,
          nowImage: AppAssets.sceneClean,
        ),
        width: 320,
      ),
    );

    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Agora'), findsOneWidget);
    expect(find.byType(AspectRatio), findsNWidgets(2));
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(images.every((image) => image.fit == BoxFit.cover), isTrue);
    expect(find.bySemanticsLabel('Antes'), findsOneWidget);
    expect(find.bySemanticsLabel('Agora'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
