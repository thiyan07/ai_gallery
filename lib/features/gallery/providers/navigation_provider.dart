import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the active tab index in the main navigation shell.
final activeTabProvider = NotifierProvider<ActiveTabNotifier, int>(
  ActiveTabNotifier.new,
);

class ActiveTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void switchTo(int index) {
    state = index;
  }
}
