import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/gallery/providers/navigation_provider.dart';

void main() {
  group('ActiveTabNotifier', () {
    test('starts at Home tab (index 0)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeTabProvider), 0);
    });

    test('switchTo updates the tab index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeTabProvider.notifier).switchTo(3);
      expect(container.read(activeTabProvider), 3);
    });

    test('can navigate between multiple tabs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeTabProvider.notifier).switchTo(1);
      container.read(activeTabProvider.notifier).switchTo(4);
      expect(container.read(activeTabProvider), 4);
    });

    test('notifies listeners on change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = <int>[];
      container.listen(activeTabProvider, (_, next) => seen.add(next));
      container.read(activeTabProvider.notifier).switchTo(2);
      expect(seen, [2]);
    });
  });
}
