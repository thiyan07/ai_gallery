# AI Gallery

A privacy-first, fully on-device AI photo gallery for Android, built with Flutter.
All machine learning — semantic search, face clustering, OCR, object detection —
runs locally via ONNX Runtime. No cloud, no uploads, no accounts.

## Features

**AI search**
- Natural-language search ("beach without people", "dog from last week") with a
  rule-based parser: precise object labels, exclusions, date/camera/quality filters
- Semantic search over CLIP/SigLIP/MobileCLIP embeddings + OCR text fallback
- Per-region (object-crop) embeddings so small objects in complex scenes match
- Search by image, "find similar", relevance feedback ("not relevant"), match explanations
- Camera point-and-search: capture and find visually similar photos

**People & organization**
- Face detection + clustering with merge/naming, tiny-face and duplicate guards
- Archive (declutter timeline, stays searchable) and PIN-protected Hidden section
- Recycle bin with 30-day retention, restore, and auto-purge
- Smart albums, memories, events, favorites, device albums

**Library tools**
- Clean-up hub: duplicate review (keep-best), blurry shots, largest files
- Library stats: counts, formats, people, objects, AI index coverage
- Newest/oldest sort, timeline scrubber, slideshow (shuffle/repeat), grid zoom

**Viewer & editing**
- Full-screen viewer with hero transitions, neighbor precaching, details panel
  (fixed AI insights + EXIF), wallpaper setter, print, slideshow
- Photo editor: filters, crop/rotate, object removal, background tools, upscaling

**Performance**
- Adaptive thumbnail resolution, repaint isolation, grid prefetch, shimmer skeletons

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

On first launch the app downloads its embedding model from Settings → AI Models
(models are fetched at runtime to keep the APK small: ~87–99 MB per ABI).
For true semantic inference use an ARM64 device — the x86_64 emulator lacks
`libonnxruntime.so`, so it exercises the OCR-only fallback paths.

## Project layout

- `lib/features/` — gallery, search, people, editing, memories, settings, …
- `lib/ai/` — ONNX providers, job processor, background worker
- `lib/core/` — database (sqflite, versioned migrations), jobs, storage
- `test/` — 550+ unit/widget tests (`flutter test`)

## Acknowledgments

Feature ideas studied from excellent open-source projects (all functionality
reimplemented clean-room for this codebase): Aves (BSD-3), CLIP-Finder2 (MIT),
Ente/Immich/flutterface (GPL-family, ideas only, no code taken).

## License

MIT — see [LICENSE](LICENSE).
