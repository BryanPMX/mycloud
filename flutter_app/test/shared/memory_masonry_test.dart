import 'package:familycloud/features/media/domain/media.dart';
import 'package:familycloud/shared/widgets/vault_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 768.0, 1280.0, 1920.0]) {
    for (final count in [1, 2, 12]) {
      testWidgets(
          '$count memories use a consistent, left-aligned tile size at $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final items = List.generate(
            count,
            (i) => Media(
                id: 'item-$i',
                ownerId: 'fixture',
                filename: 'fixture-$i.jpg',
                mimeType: 'image/jpeg',
                sizeBytes: 100,
                width: 400,
                height: 400,
                durationSecs: 0,
                status: MediaStatus.ready,
                isFavorite: false,
                uploadedAt: DateTime.utc(2026),
                thumbUrls: const ThumbUrls()));
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: MemoryMasonry(
                        key: const ValueKey('grid'),
                        items: items,
                        builder: (_, i) => AspectRatio(
                            aspectRatio: 1,
                            child: ColoredBox(
                                key: ValueKey('tile-$i'),
                                color: Colors.grey)))))));
        await tester.pumpAndSettle();
        final grid = tester.getRect(find.byKey(const ValueKey('grid')));
        final first = tester.getRect(find.byKey(const ValueKey('tile-0')));
        expect(first.left, grid.left);
        expect(first.width, inInclusiveRange(120, 320));
        if (count > 1) {
          final second = tester.getRect(find.byKey(const ValueKey('tile-1')));
          expect(second.width, closeTo(first.width, 0.01));
          expect(second.left, greaterThan(first.right));
        }
        expect(grid.width, width);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
