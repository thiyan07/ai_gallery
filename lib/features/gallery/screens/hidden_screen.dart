import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';
import 'package:ai_gallery/features/gallery/screens/photo_view_screen.dart';
import 'package:ai_gallery/features/gallery/services/visibility_service.dart';

/// PIN-gated Hidden section. Hidden photos are excluded from the timeline,
/// albums, and search until unhidden here.
class HiddenScreen extends ConsumerStatefulWidget {
  const HiddenScreen({super.key});

  @override
  ConsumerState<HiddenScreen> createState() => _HiddenScreenState();
}

class _HiddenScreenState extends ConsumerState<HiddenScreen> {
  bool _checking = true;
  bool _unlocked = false;
  bool _hasPin = false;
  List<String> _ids = [];
  Map<String, AssetEntity> _assets = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final hasPin = await ref.read(visibilityServiceProvider).hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _checking = false;
    });
  }

  Future<void> _setupPin() async {
    final pin = await _askPin(context, title: 'Set Hidden PIN', confirm: true);
    if (pin == null || !mounted) return;
    final ok = await ref.read(visibilityServiceProvider).setPin(pin);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _hasPin = true;
        _unlocked = true;
      });
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must be at least 4 digits')),
      );
    }
  }

  Future<void> _unlock() async {
    final pin = await _askPin(context, title: 'Enter Hidden PIN');
    if (pin == null || !mounted) return;
    final ok = await ref.read(visibilityServiceProvider).verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      setState(() => _unlocked = true);
      await _load();
    } else {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong PIN')),
      );
    }
  }

  /// PIN entry dialog. With [confirm], asks twice and requires a match.
  static Future<String?> _askPin(
    BuildContext context, {
    required String title,
    bool confirm = false,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'PIN (4+ digits)',
                  counterText: '',
                ),
              ),
              if (confirm)
                TextField(
                  controller: second,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                    counterText: '',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final pin = first.text.trim();
                if (!VisibilityService.isValidPin(pin)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('PIN must be at least 4 digits'),
                    ),
                  );
                  return;
                }
                if (confirm && second.text.trim() != pin) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('PINs do not match')),
                  );
                  return;
                }
                Navigator.pop(ctx, pin);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return result;
    } finally {
      first.dispose();
      second.dispose();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ids = await ref.read(visibilityServiceProvider).hiddenIds();
    final trashed = await ref.read(trashServiceProvider).trashedIds();
    final live = ids.where((id) => !trashed.contains(id)).toList();
    final repo = ref.read(photoRepositoryProvider);
    final assets = await repo.getAssetsByIds(live);
    if (!mounted) return;
    setState(() {
      _ids = live;
      _assets = {for (final a in assets) a.id: a};
      _loading = false;
    });
  }

  Future<void> _unhide(String id) async {
    await ref.read(visibilityServiceProvider).unhide(id);
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    await _load();
  }

  Future<void> _openViewer(String id) async {
    final asset = _assets[id];
    if (asset == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(assets: [asset], initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_hasPin
              ? _Gate(
                  icon: Icons.lock_outline,
                  message:
                      'Set a PIN to protect hidden photos.\nHidden photos never appear in the timeline, albums, or search.',
                  actionLabel: 'Set PIN',
                  onAction: _setupPin,
                )
              : !_unlocked
                  ? _Gate(
                      icon: Icons.lock_outline,
                      message: 'Enter your Hidden PIN to view these photos.',
                      actionLabel: 'Unlock',
                      onAction: _unlock,
                    )
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _ids.isEmpty
                          ? const Center(
                              child: Text(
                                'Nothing hidden.\nHide photos to keep them private.',
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(8),
                              cacheExtent: 800,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                              itemCount: _ids.length,
                              itemBuilder: (context, index) {
                                final id = _ids[index];
                                final asset = _assets[id];
                                return RepaintBoundary(
                                  child: GestureDetector(
                                    onTap: () => _openViewer(id),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (asset != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: AssetEntityImage(
                                              asset,
                                              isOriginal: false,
                                              thumbnailSize:
                                                  ThumbnailSizes.forGrid(
                                                      context, 3,
                                                      spacing: 4),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else
                                          const Center(
                                            child: Icon(
                                                Icons.image_not_supported),
                                          ),
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Tooltip(
                                            message: 'Unhide',
                                            child: InkWell(
                                              onTap: () => _unhide(id),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.7),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons
                                                      .visibility_outlined,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
