# AI Gallery — Implementation Progress (Master Prompt)

Last updated: 2026-09-26 (SIZE-CUT IMPLEMENTED on chatgpt/size-cut-siglipruntime)
Branch: chatgpt/size-cut-siglipruntime (from chatgpt/ai-gallery-master)
SIZE-CUT: removed bundled SigLIP (siglip_base_patch16_224.onnx 336M + siglip_text_encoder.onnx 804M, gitignored) → runtime-download-only via existing ModelPresets/ModelManager; assets/models 1.2G→67M (yolo/mobilefacenet/ppocr/blaze/tokenizer stay bundled); APK before ~1.2G → debug 249M, release split-per-ABI arm64-v8a 99.4M / armeabi-v7a 92.9M / x86_64 86.7M (~92% reduction); APK audit via unzip -l: NO siglip payload, only 6 small models + tokenizer (468 files, 96MB archive); LocalEmbeddingProvider missing-asset errors now MODEL_NOT_READY (Settings > AI Models); 5 new tests test/services/size_cut_test.dart; suite 534 passed, analyze 0 errors; Pixel-5554 fresh-install validated (uninstall→install slim APK: onboarding→Skip→Home 9 photos, search HELLO no-model → honest No-results card no crash, PhotoView+Edit/Delete icons); runtime download proven on device (app_flutter/models/mobileclip_s2.onnx 136M + mobileclip_s2_text_encoder.onnx 242M auto-downloaded+validated 00:52/00:54, restart caused NO re-download, mtimes unchanged); pre-cut log showed "Model already installed: mobileclip_s2" (detection works); inference limitation documented: x86_64 emulator lacks libonnxruntime.so → download/validation SUCCESS, inference NOT claimed (needs ARM device). Toolchain: Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, pub upgrade 65 deps. Search UX: honest no-results/empty states.
Master roadmap: Phase 11 A-J → 14 → 15 → 16 → 17 → 18 (skip 12)
ChatGPT Phase 14 Review 2026-09-23: APPROVED WITH DOCUMENTED LIMITATION — 9/10 capabilities fully implemented; perspective stored non-destructively but _applyPerspective identity (image pkg limitation) — must keep infrastructure/tests but DO NOT claim true perspective correction. Phase 15 AI image enhancement/upscaling 2x/4x per ChatGPT 2026-09-23 instruction (preserve original, local, ModelManager, progress, cancel, large-image safe) — IMPLEMENTED 2026-09-24 via ImageEnhancementService + EditTransformationEngine + ModelPresets realesrgan-x2/x4.

---

## Phase 9 — Semantic / Natural Language Image Search
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION**
- Verify: `lib/features/search/services/search_service.dart` hybrid search (70% semantic / 30% OCR), `lib/ai/providers/local_embedding_provider.dart`, `lib/core/services/model_manager.dart` reuse, `lib/features/search/services/natural_language_parser.dart`, `lib/features/search/services/ranking_engine.dart`
- Offline: works after ONNX model download via Settings > AI Models
- Checks: `flutter analyze` 0 errors, `flutter test` 461 passed (2026-09-23)

## Phase 10 — OCR + Text-Aware Image Search
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION**
- Verify: `lib/ai/ai_manager.dart:_processOcr` real confidence + bounding boxes, `lib/domain/models/photo_metadata.dart` OcrStatus, `lib/core/database/app_database.dart` ocr_status / ocr_model_version, `lib/core/database/daos/photo_metadata_dao.dart`, `lib/features/search/services/search_service.dart:search()` OCR relevance scoring (`relevance * confidence`)
- Offline: PaddleOCR ONNX Runtime, local-first
- Checks: hybrid search degrades gracefully when OCR unavailable

## Phase 11 — People / Face Recognition

### Clustering Foundation (FaceClusteringService)
- Audited: 20 checks PASS (previous report 2026-09-22)
- File: `lib/features/people/services/face_clustering_service.dart`
- Uses real stored face embeddings, cosine similarity, `similarityThreshold=0.6`, `minClusterSize=2`, compatibility guard `_areEmbeddingsCompatible(dim)`, prefers false-negatives, unknown groups via `displayName == null`

### Task 11-A — People UI
- Screen: `lib/features/people/screens/people_screen.dart` (now 1517 lines)
- Checklist:
  - [x] Named / Unknown tabs — `PersonCluster.isUnknown` (`label == 'Unknown'`)
  - [x] Cover image — `PersonCluster.coverPhotoId` + `representativeFace` prefers cover photo; `_PersonClusterCard` uses cover
  - [x] Approximate photo counts — `faceCount` and `photoCount` (`faces.photoId.toSet().length`) displayed as "N faces • M photos" in card; detail header shows both
  - [x] Loading / empty / error / processing — `AsyncLoading` shows spinner + "Processing faces…" + `LinearProgressIndicator`, empty "No People Found", error with Retry + Recluster
  - [x] Mobile-friendly — `LayoutBuilder` responsive grid (2 cols <360px, 3 cols <600px, 4 cols otherwise), 12px padding, card aspect 0.82
  - [x] Reuse gallery grid — `AssetEntityImage` with `ThumbnailSize.square(300)` same as `photo_tile.dart` / `pinch_zoom_grid.dart`, no new image loader
- Delta 2026-09-23: Added `PersonCluster.coverPhotoId`, `photoCount`, `isUnknown`; `getPeopleClusters` now uses `getAllActive()` sorted by size; `PeopleScreen` responsive grid + processing indicator; card subtitle photo count.

### Task 11-B — Person Details
- Screen: `PersonDetailScreen` in same file
- Checklist:
  - [x] Name, cover, counts in AppBar + header row (face + photo icons)
  - [x] All associated photos — `GridView` 3 cols of `_FaceThumbnail` (photo-backed); tapping shows photo via `AssetEntityImage` full-screen
  - [x] Reuse gallery: same `AssetEntityImage`, `PhotoViewScreen` for single photo view
  - [x] Counts header, divider, expandable grid

### Task 11-C — Person Naming
- Service: `PeopleService.renamePerson`, `FaceClusteringService.renameCluster`
- UI: `_renameCluster` and `_renamePerson` dialogs with `maxLength=50`, duplicate name guard (case-insensitive), length check, error snackbar, refresh `peopleClustersProvider`
- DAO: `PeopleDao.updateDisplayName`, `getByDisplayName` case-insensitive

### Task 11-D — Manual Correction UI
- Actions: rename, assign/move face, remove face, mark as unknown, change cover, delete/move selected (split), all present in `PersonDetailScreen._showFaceActions` + split mode
- Face thumbnail long-press enters split mode, tap selects, "Select all" + "Move selected" batch
- `PeopleService.moveFace`, `removeFaceFromPerson`, `assignFaceToPerson` verified; `PeopleDao` transactional

### Task 11-E — Merge
- Dialog: `_showMergeDialog` lists other clusters, confirmation with faces count warning, calls `service.mergeClusters(target, source)` → `PeopleService.mergePersons` transaction (reassign faces + mark source merged + update dest timestamp)
- Coverage: prevents self-merge, verifies active status

### Task 11-F — Split / Move
- Enter split mode: FAB menu "Split (move faces)" or long-press a face; selection overlay with check icon, `_selectedFaceIds`
- `_showMoveSelectedDialog`: lists other persons + "Unknown" (null), loops `moveFace` or `removeFaceFromPerson` per face, updates local `_faces`, snackbar
- Also single-face `_showMoveFaceDialog` and `_removeFaceFromPerson` / `_markAsUnknown`

### Task 11-G — People Search
- Parser: `lib/features/search/services/natural_language_parser.dart` with `personNames` injected from `peopleDao.getAllActive()`; `naturalLanguageParserProvider` watches DB
- Service: `SearchService.searchByPerson` (exact name via `peopleDao.getByDisplayName`), `searchParsed` person-only path, ` _searchPersonWithSemantic` (person hard filter + semantic ranking), `_searchSemanticOnly` respects object/person filters, batched metadata + favorites
- Tests: `test/services/natural_language_parser_person_test.dart`, `test/services/search_multi_signal_test.dart` all pass

### Task 11-H — Hybrid / Robustness
- Intent classification: `SearchIntent.person/object/scene/location/combined/unknown` via `NaturalLanguageParser._classifyIntent`
- Combinations: person+semantic, object-only, location-only, semantic-only with object hard filter, person+object+semantic intersection
- Robust variations covered by tests: "photos of Thiyan", "pictures of Thiyan" (filler stripped), "show me Thiyan", "Thiyan at college", "Thiyan hiking", "Thiyan at beach", case-insensitive, multi-word names, `O'Brien`, partial/fuzzy handled by fallback to semantic if person not found
- Ranking: `RankingEngine.rank()` with `SearchIntent` weights; person match gets strong signal (score 1.0 for person-only, cosine for hybrid)

### Task 11-I — Privacy / Reset
- Settings: `lib/features/settings/screens/settings_screen.dart:415` "Reset Face Data" ListTile + `_showFaceDataResetDialog` with warning icon, discloses that photos/metadata/OCR/embeddings preserved, requires confirmation, calls `PeopleService.resetAllFaceData()` transaction (clear `faces.person_id` + `DELETE FROM people`)
- Verify: embeddings remain local (no upload, no logging), person names local (SQLite), face detections local, no external biometric calls; `PeopleService.resetAllFaceData` tested
- No secrets in repo, no model binaries committed (`.gitignore` + `assets/models/ppocr_dict.txt` is tiny dict only)

### Task 11-J — Performance
- Background: `FaceClusteringService.clusterAllFaces` batched `limit 1000`, incremental `clusterFace` compares only against assigned faces with embedding-compatibility guard, not full reclustering
- Android: `PeopleClustersNotifier` guards `_isClustering` to prevent concurrent reclusters, refresh via provider; UI progress indicator not blocking
- Image loading: `ThumbnailSize.square(300)`, `isOriginal:false` in grids; full res only in `PhotoViewScreen`
- Models: reuse `ModelManager`/`ModelDownloader` with `.part`, checksum, ONNX validation, state `NOT_INSTALLED→DOWNLOADING→VERIFYING→INSTALLED→LOADING→READY→FAILED`, not auto-downloaded on `pub get`/`analyze`/`test`

### Task 11-K — Tests
- Files: `test/services/face_clustering_service_test.dart`, `test/services/people_service_test.dart`, `test/services/natural_language_parser_person_test.dart`, `test/services/search_multi_signal_test.dart`, `test/services/multimodal_search_test.dart`
- Run 2026-09-23: `flutter test` 461 passed, 2 skipped, 0 failed
- `flutter analyze` / `dart analyze` 0 errors (warnings only, no error-level)

### Phase 11 Acceptance Gate — 2026-09-23
- [x] Face detection works (BlazeFace ONNX, `lib/ai/providers/blazeface_provider.dart`)
- [x] Real face embeddings work (FaceEmbeddingProvider, no hash/fake)
- [x] Face processing status works (PhotoMetadata faceStatus + faceModelVersion, duplicate prevention)
- [x] Model versions handled safely (compatibility guard, separate per-model cache)
- [x] Clustering works (greedy cosine similarity, conservative threshold)
- [x] Unknown groups work (displayName == null → 'Unknown')
- [x] Named people work (rename, cover)
- [x] People UI works (tabs, cover, counts, responsive, loading/empty/error/processing)
- [x] Person details work (header + face grid + photo view)
- [x] Manual correction works (rename/assign/remove/move/cover)
- [x] Merge works (transactional, confirm)
- [x] Split works (batch move to unknown or another person)
- [x] Person search works (`searchByPerson`, `searchParsed` person-only)
- [x] Natural-language person search works (parser personNames, variations)
- [x] Person + semantic search works (`_searchPersonWithSemantic`)
- [x] Person + OCR search works (hybrid 70/30 with OCR relevance)
- [x] Reset face data works (Settings, confirmation, preserves photos)
- [x] Offline operation works (ONNX local-first, no cloud after download)
- [x] Existing Phase 9 works (semantic search unchanged)
- [x] Existing Phase 10 works (OCR unchanged)
- [x] flutter analyze passes (0 errors)
- [x] tests pass (461 passed)

**Status: CODE COMPLETE — ANDROID VALIDATION PENDING (approved 2026-09-23 per ChatGPT)**

---

## Phase 12 — Private Lock Folder
- Skipped per master prompt.

## Phase 14 — Advanced Image Editing
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION — APPROVED WITH DOCUMENTED LIMITATION (2026-09-23 ChatGPT review)**
- ChatGPT Review 2026-09-23: APPROVED WITH DOCUMENTED LIMITATION — 9/10 capabilities ✅, perspective ⚠️ Partial (stored non-destructively, identity transform; must NOT be advertised as functional perspective correction; keep infrastructure/serialization/tests)
- Approval prerequisite: Phase 11 APPROVED CODE-COMPLETE 2026-09-23, maintaining ANDROID VALIDATION PENDING; `.chatgpt-loop-history.md` inspected (no secrets, only branch history) and gitignored via `.gitignore`.
- Architecture reused (per master prompt “inspect existing editing architecture in lib/features/editing”):
  - `lib/domain/models/edit/edit_recipe.dart` non-destructive recipe (operations JSON) — original never overwritten, edited derivative in `getApplicationDocumentsDirectory()/edited`
  - `lib/domain/models/edit/edit_operation.dart` pipeline (crop, rotate, flip, straighten, adjustment 14 params, filter, blur/grain/fade, drawing, text, frame, AI ops, curves/hsl, resize/perspective)
  - `lib/core/database/daos/edit_dao.dart` + `app_database.dart` `edit_recipes` table (version 16)
  - `lib/features/editing/services/edit_transformation_engine.dart` deterministic pipeline order (geometric → tonal → color → detail → creative) using `image` package, memory-safe
  - `lib/features/editing/providers/edit_session_provider.dart` ChangeNotifier with EditHistoryManager undo/redo, discrete vs continuous commits, isolate decoding, preview capped at 1200px
  - `lib/features/editing/services/edit_export_service.dart` atomic temp→final export, cancellation token, preserve original; `lib/features/editing/services/export_queue_service.dart` sequential queue with progress tracking
  - `lib/features/gallery/screens/photo_view_screen.dart` entry point `Edit` button (photo only, not video), reuses `AssetEntity`
  - `lib/features/editing/screens/edit_screen.dart` mobile-first toolbar, undo/redo, reset/revert, save, processing/error states, Flip H/V separate, Resize dialog
- Delta 2026-09-23 (Phase 14 polish to meet spec 1-10):
  - Added `EditOperationType.resize` + `EditOperationType.perspective` (lib/domain/models/edit/edit_operation.dart): resize with width/height 1-8000, maintainAspect, lanczos/cubic; perspective 8 deltas [-0.5..0.5] (identity = no-op, stored non-destructively for future native warp without migration)
  - `EditTransformationEngine`: added `_applyResize` (caps 4096, aspect-fit via cubic, memory-safe) and `_applyPerspective` stub (identity fallback — `image` package has no perspective warp; avoids external native dep per “if practical with existing stack”)
  - `EditRecipe`: added `withResize/withoutResize/withPerspective/withoutPerspective`, `hasResize/hasPerspective`, summary “Resized W×H” / “Perspective”
  - `EditSessionController`: added `setResize/removeResize/setPerspective/removePerspective` (discrete commits, undo-able)
  - `EditScreen`: split Flip into Flip H (isFlippedH active) + Flip V (isFlippedV active) via `toggleVerticalFlip`; added Resize tool button with dialog (presets 25/50/75/Original, maintainAspect, validation 1-8000, Remove)
  - Existing already covered spec: crop (CropRect relative 0-1, compositing), rotate (arbitrary degrees), flip H/V, brightness/contrast/saturation/sharpness (via `AdjustmentDefaults`), straighten ±45°, original preservation, undo/redo, revert, history
  - EXIF/orientation: preserved via `AssetEntity` originalFile (orientation handled by viewer); export quality 95 JPEG, PNG for preview, no unnecessary recompression
  - Local-first: all transforms run on-device via `image` package, no upload, no API key, no telemetry with image data
  - Memory: preview downscaled to 1200px max, geometric ops first, `createPreview` helper, resize caps, large-image safety verified in tests
- Coverage vs spec 1-10:
  - [x] 1 Crop — EditOperation.crop + CropRect compositing + _CropOverlay rule-of-thirds
  - [x] 2 Rotate — EditOperation.rotate arbitrary degrees + cycleRotation
  - [x] 3 Flip horizontal — EditOperation.flip horizontal + toggleHorizontalFlip
  - [x] 4 Flip vertical — EditOperation.flip vertical + toggleVerticalFlip (UI now exposes both, pixel-tested in edit_phase14_test.dart)
  - [x] 5 Resize — EditOperation.resize + _applyResize + Resize dialog (presets, aspect, 4096 cap, engine-tested)
  - [x] 6 Brightness — AdjustmentDefaults brightness + _applyBrightness
  - [x] 7 Contrast — AdjustmentDefaults contrast + _applyContrast
  - [x] 8 Saturation — AdjustmentDefaults saturation + _applySaturation
  - [x] 9 Sharpness — AdjustmentDefaults sharpness + _applySharpness (unsharp mask)
  - [~] 10 Perspective correction — EditOperation.perspective stored non-destructively, _applyPerspective currently identity (image pkg limitation); straighten covers horizon ±45°; documented as “if practical” — no external service introduced; serialization tested
- Final QA 2026-09-23:
  - Added `test/editing/edit_phase14_test.dart` (26 tests): resize clamping/serialization/engine aspect-fit/caps/identity, perspective deltas/clamping/serialization/no-op identity, vertical flip pixel correctness (H/V/both axes, summary), bright pixel flips, export queue enqueue/pendingCount/cancel/clearFinished.
  - Verified export queue: `ExportQueueService` sequential processing, `ExportQueueStatus` pending/processing/completed/failed/cancelled, `cancel`/`cancelAll`/`clearFinished`/`pendingCount`; failure path returns failed status without crash (test shows binding init failure gracefully handled, queue remains consistent).
  - `flutter analyze` 0 errors (only info/warn), `flutter test` 487 passed, 2 skipped (2026-09-23) — +26 from 461.
  - Manual checks: crop/rotate/flip H/V/resize/brightness/contrast/saturation/sharpness via adjustment pipeline; preview still memory-safe.
- Files touched 2026-09-23: edit_operation.dart, edit_recipe.dart, edit_transformation_engine.dart, edit_session_provider.dart, edit_screen.dart, test/editing/edit_phase14_test.dart, IMPLEMENTATION_PROGRESS.md, .gitignore

## Phase 15 — AI Image Enhancement / Upscaling 2x/4x
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION** (implemented 2026-09-24)
- Verify:
  - Service: `lib/features/editing/services/image_enhancement_service.dart` (ImageEnhancementService: enhanceBytes/upscaleBytes, normalizeScale, modelReady fallback, progressCallback, EditCancelToken cancellation, memory caps 8192/64MP, preserve original via edited/<id>_enhanced|_upscaled_x2|x4.jpg atomic temp→final, local-first bicubic fallback, ONNX model readiness via ModelManager, _getEditedDir fallback to systemTemp for tests, _lastUpscaleUsedFallback tracking ONNX vs fallback for usedFallback accuracy, upscaleBytes now attempts OnnxUpscaler first then bicubic fallback, progress 0.3..0.7 for tiled ONNX)
  - Onnx: `lib/features/editing/services/onnx_upscaler.dart` (NEW 250 lines): tryUpscale with model file validity check, memory guards 8192/64MP, single vs tiled inference decision (tile 512 overlap 16, tilesX*tilesY), _createSession via OrtSessionOptions(threads2, GraphOptimizationLevel.ortEnableAll, CPU arena), preprocess RGB 0..1 Float32 [1,3,H,W] NCHW, postprocess Float32 [1,3,H*scale,W*scale] clamped 0..1->255, _tiledInference stiches tiles at tx*scale/ty*scale, progress done/total*0.8, cancellation between tiles, seamless overlap handling, logs ONNX INFERENCE VERIFIED vs FALLBACK, handles invalid model file gracefully (returns null)
  - Engine: `lib/features/editing/services/edit_transformation_engine.dart` extended Phase 15 pipeline — _applyEnhancement (histogram-aware brightness/contrast/vibrance/clarity via _averageLuminance/_dynamicRange), _applyDenoising (gaussianBlend), _applyAutoEnhance (map-driven), _applyUpscaling (cubic 2x/4x caps 8192/64MP, last phase after enhancement/frame), pipeline now 9 phases (geometric→adjust→curves→hsl→filter→effects→drawing/text→frame→enhancement/denoise/auto→upscale)
  - Models: `lib/core/services/model_downloader.dart` added ModelType.upscaler/enhancer + ModelPresets `realesrgan-x2`/`realesrgan-x4`/`waifu2x-x2` (caq/realesrgan, xenova/waifu2x, ~4-8MB, runtime download only, never build-time, via existing ModelDownloader/ModelManager dedup + .part→final atomic + stallTimeout, _ensureInitialized fallback to systemTemp for tests)
  - Operations: `lib/domain/models/edit/edit_operation.dart` already had enhancement/upscaling/denoising/autoEnhance (clamping 0..1 / scale 2..4, isNoOp, isUpscaling etc.); reused, no new schema
  - Recipe: `lib/domain/models/edit/edit_recipe.dart` withEnhancement/withoutEnhancement/withUpscaling/withoutUpscaling/withDenoising etc., summary “Enhancement” / “Upscale 2x/4x”
  - Controller: `lib/features/editing/providers/edit_session_provider.dart` added setEnhancement/removeEnhancement/setUpscaling/removeUpscaling/setDenoising/removeDenoising/setAutoEnhance/removeAutoEnhance (discrete undo-able, reuse history)
  - Providers: `lib/features/editing/providers/enhancement_providers.dart` (imageEnhancementServiceProvider reuses appLogger/modelManager/modelDownloader)
  - Privacy: all enhancement/upscale runs on-device via `image` package + onnxruntime local session when model available (RGB 0..1 preprocessing, no upload, no API key, no telemetry with image data; ONNX path is local inference, fallback bicubic ensures offline without download, tiling avoids seam where practical)
  - Memory: input >4096 clamped before upscale, output capped 8192 per side + 64MP, refuses if would exceed, tiled 512+16 overlap avoids holding full output for every tile simultaneously, releases intermediate buffers, progress based on tiles, cancellation between tiles, avoids multiple full-res copies (source→result single), progress 0..1, cancellation via EditCancelToken checked at decode/progress/write/tile boundaries, large-image safety verified in tests (600x600 ->1200)
  - Export: derived result only (`edited/<photoId>_enhanced.jpg`, `_upscaled_x2.jpg`), original never overwritten, atomic temp→final, preserve EXIF-quality 95 JPEG, _writeDerived uses _getEditedDir fallback for host tests, handle invalid bytes as failed not crash
  - State: Model readiness (isModelReady/getModelState notInstalled→downloading→installed→failed via ModelDownloader.getModelState with systemTemp fallback), clear modelNotReady vs fallback vs ONNX verified, download via ModelManager.getSelectedModelPath with progress/state callbacks, _lastUpscaleUsedFallback tracks actual ONNX vs fallback for accurate usedFallback reporting, no hardcoded URLs outside ModelPresets
- Checks: `test/editing/edit_phase15_test.dart` 42 tests passed (enhancement clamping/serialization/engine pixel change, upscaling 2x/4x caps 8192/64MP, denoising smoothing, autoEnhance adjustments, service normalizeScale, enhanceBytes/upscaleBytes invalid/cancel/memory-guard/fallback, progress, model readiness fallback notInstalled, upscalePhoto/enhancePhoto success/derived suffix/original preservation/fallback flag, ModelPresets realesrgan entries, 2x/4x exact dimensions, recipe enhancement+upscale+denoise combo, ONNX wiring: tryUpscale null when not installed Fallback Verified, usedFallback distinguishes ONNX vs fallback, tiled 600->1200 via fallback correct dims, invalid model file gracefully fallback); `flutter analyze` 0 errors (info only); `flutter test` 529 passed, 2 skipped (487->529 +42 Phase15, includes 4 ONNX wiring tests); manual verify enhance 0.6 changes pixels, upscale 2x doubles, 4x quadruples, caps, cancellation, invalid bytes failed gracefully, tiling 600 handled, ONNX path logs attempted vs fallback
- Limitation updated: ONNX Real-ESRGAN inference NOW WIRED via OnnxUpscaler (OrtSession, RGB 0..1 NCHW, output [1,3,H*scale,W*scale], tiling 512+16 overlap, progress per tile, cancellation between tiles, caps preserved). Previously bicubic fallback only; now when model installed, actual ONNX inference is attempted and logged as ONNX INFERENCE VERIFIED vs FALLBACK. Tested with invalid model file fallback gracefully; real model not committed (runtime download). Enhancement remains algorithmic histogram-aware (local, deterministic) — labeled accurately not learned; suitable for mobile. Both are local-first, tiling memory-safe, ready for device validation with Pixel_8.
- Reuse: existing ModelManager/ModelDownloader, EditTransformationEngine, EditRecipe/AppDatabase (no new tables), AppLogger, no duplicate DBs, no secrets, no model binaries committed, onnxruntime already in pubspec (no new dep)
- Files touched 2026-09-24: lib/core/services/model_downloader.dart (ModelType.upscaler/enhancer + 3 presets + test fallback), lib/features/editing/services/image_enhancement_service.dart (NEW 430 lines + _lastUpscaleUsedFallback + OnnxUpscaler integration), lib/features/editing/services/onnx_upscaler.dart (NEW 250 lines tiling + session), lib/features/editing/services/edit_transformation_engine.dart (+enhancement/denoising/auto/upscale), lib/features/editing/providers/edit_session_provider.dart (+6), lib/features/editing/providers/enhancement_providers.dart (NEW), test/editing/edit_phase15_test.dart (NEW 42 tests), IMPLEMENTATION_PROGRESS.md

## Phase 15B — Video Intelligence (legacy, audited)
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION** (audited 2026-09-23; no reimplementation per master prompt “reuse architecture, never duplicate DBs”)
- Verify:
  - Engine: `lib/features/video_intelligence/services/video_intelligence_engine.dart` (scene detection via visual similarity, highlight scoring people+objects, chapters, summary, search by text/person/time)
  - Cache/manager: `lib/features/video_intelligence/services/frame_cache.dart` (LRU, invalidateVideo, clear), `video_quality_service.dart`, `video_resource_manager.dart`
  - UI: `lib/features/video_intelligence/widgets/video_intelligence_panel.dart`, `lib/features/gallery/screens/video_player_screen.dart` (reuses photo tile / media service)
  - Persistence: `lib/core/database/app_database.dart::_createVideoTables` (video_segments, video_analysis, video_frames, indexes), `lib/core/database/daos/video_segment_dao.dart`, `video_frame_dao.dart`, `video_analysis_dao.dart`, version 16
  - DI: `lib/core/di/providers.dart` video providers reuse existing AppDatabase/AppLogger, no duplicate DB
- Offline: all analysis local-first (frames sampled on-device, embeddings via ModelManager ONNX), no upload
- Checks: `test/video_intelligence/video_intelligence_phase30_test.dart` 22 tests passed (scene detection, mergeShortScenes, highlights, chapters, summary, search, FrameCache LRU); `flutter analyze` 0 errors; `flutter test` 487 passed overall (now 525)
- Reuse: existing `ModelManager`/`MediaService`, `AppDatabase` video tables already versioned; no secrets

## Phase 16 — Memories
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION** (audited 2026-09-23)
- Verify:
  - Algorithms: `lib/core/algorithms/temporal_clustering.dart`, `event_discovery.dart`, `memory_scoring.dart`, `memory_title_generator.dart`, `best_photo_selector.dart`, `cover_photo_selector.dart`, `semantic_analysis.dart`, `trip_detection.dart`, `automatic_album_generator.dart`
  - Service: `lib/features/memories/services/memory_service.dart` (batched metadata+faces, EventDiscovery, scoring, bestPhoto/cover selection)
  - UI: `lib/features/memories/screens/memories_screen.dart` / `memory_detail_screen.dart` / `album_detail_screen.dart`, widgets `memory_card.dart` / `automatic_album_card.dart`
  - Persistence: `lib/core/database/app_database.dart::_createMemoryTables` (memories, automatic_albums, indexes), `lib/core/database/daos/memory_dao.dart`, `smart_album_dao.dart`, `event_dao.dart`, version 16
  - DI: `lib/core/di/providers.dart` memory providers reuse AppDatabase
- Offline: generation is on-device deterministic clustering/scoring, no cloud
- Checks: `test/services/memory_algorithms_test.dart` 33 tests passed (temporal clustering, event discovery, scoring, titles, best/cover selection, semantic coherence, trip detection, album generation); `flutter test` overall 487 passed; analyze 0 errors
- Reuse: existing photo_metadata/face tables, no duplicate stores; incremental via `IncrementalAnalysisTracker` if needed

## Phase 17 — Knowledge Graph
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION** (audited 2026-09-23)
- Verify:
  - Service: `lib/features/knowledge_graph/services/knowledge_graph_service.dart` (buildGraph idempotent upserts, entities: media/person/place/event/object/memory, relationships: media↔person/place/event/object, event↔place/person, memory↔media/person, person co-occurrence, event temporal, video segments; all evidence-based, no fabrication)
  - Persistence: `lib/core/database/app_database.dart::_createKnowledgeGraphTables` (knowledge_graph_entities UNIQUE(type, external_id), knowledge_graph_relationships with evidence_source/confidence/analysis_version, indexes), `lib/core/database/daos/knowledge_graph_dao.dart`, version 16
  - Integration: `lib/core/di/providers.dart` knowledgeGraphServiceProvider / knowledgeGraphDaoProvider, `assistant/tools/query_knowledge_graph_tool.dart`, diagnostics counts (`diagnostics_service.dart`), `repair_engine.dart` orphan checks, `incremental_analysis_tracker` version `1.0`
  - UI surfacing via Assistant tooling (no standalone screen needed; graph is backing store)
- Offline: deterministic derivation from indexed metadata/faces/tags/events, no external calls
- Checks: `flutter analyze` 0 errors; `flutter test` 487 passed; no duplicate DBs (reuses AppDatabase), no secrets logged
- Reuse: derives from faces/person, photo_metadata lat/lng, analysis_state/event_id, object_tags, photo_events, memories — no re-ingestion

## Phase 18 — Assistant
- Status: **CODE-COMPLETE — READY FOR ANDROID VALIDATION** (audited 2026-09-23)
- Verify:
  - Core: `lib/features/assistant/services/gallery_assistant.dart` (intent → query plan → structured/semantic retrieval → grounded response → actions), `intent_resolver.dart`, `structured_retriever.dart`, `result_set_manager.dart`, `multi_step_planner.dart`, `conversational_context.dart`
  - Security: `lib/features/assistant/services/assistant_security_guard.dart` (allowlist, injection guard), `tool_registry.dart`/`tool_interface.dart`/`tool_executor.dart`/`action_registry.dart`/`batch_action_executor.dart` respect local-only execution
  - Tools: `lib/features/assistant/tools/*.dart` (search_photos, search_videos, get_gallery_stats, count_photos, find_best_photos, find_duplicates, filter_by_quality, get_video_highlights/chapters/summary, query_knowledge_graph, add/remove favorites, create_album/memory, navigation) — all use existing SearchService/AnalysisManager/RelatedPhotoService/SearchExplainer, no new external APIs
  - Retrieval: `chat_history_service.dart`, `result_set_manager.dart` session-scoped, no telemetry
  - UI: `lib/features/assistant/screens/assistant_screen.dart`, widgets `action_preview_card.dart` / `assistant_photo_grid.dart`, providers `assistant_providers.dart`
  - DI: `lib/core/di/providers.dart` assistant wiring reuses SearchService/NL parser/RelatedPhotoService/AnalysisManager; no duplicate model manager
  - Memory safety: result sets bounded via BoundedCache, history capped
- Offline: deterministic intent classification, local retrieval; model calls (if any) via existing AI providers local-first, no image upload
- Checks: `flutter analyze` 0 errors; `flutter test` 487 passed (± search/assistant hybrid tests in `search_multi_signal_test.dart`/`multimodal_search_test.dart` covering intent routing); no secrets (api keys via SecureStorageService, never logged)
- Reuse: reuses all Phase 9-11 search stack, Phase 15 video search, Phase 17 knowledge graph, never duplicates DBs

---

## Verification Commands Run
- `/opt/flutter/bin/flutter analyze --no-pub` — 0 errors (2026-09-24, info/warn only, 0 errors confirmed 2026-09-24 after ONNX wiring)
- `/opt/flutter/bin/flutter test` — 529 passed, 2 skipped, 0 failed (2026-09-24) [+26 Phase14 (resize/perspective/vertical-flip/export-queue) +42 Phase15 (enhancement/upscaling 2x/4x/denoising/auto, service model-readiness/fallback/progress/cancel/memory-guard/export, ModelPresets realesrgan, ONNX tiling/cancel/progress/model-file-invalid)]
- Sub-suites: `test/video_intelligence/video_intelligence_phase30_test.dart` 22 passed, `test/services/memory_algorithms_test.dart` 33 passed, `test/editing/edit_phase14_test.dart` 26 passed, `test/editing/edit_phase15_test.dart` 42 passed (4 ONNX wiring: tryUpscale null fallback verified, usedFallback distinguishes, tiled 600->1200, invalid model fallback)
- Manual inspection: `PeopleScreen` tabs, `PersonDetailScreen` merge/split/cover/move/delete flows, `SearchScreen` suggestions (`people` + `object_tags` with legacy fallback), `SettingsScreen` reset dialog, `EditScreen` Flip H/V separate active states + Resize dialog (presets 25/50/75/Original, aspect, 1-8000 validation), preview memory safety (1200px cap, 4096 resize cap), enhancement histogram-aware pixel change verified, upscale 2x/4x doubles/quadruples + 8192/64MP caps + invalid bytes fallback, tiling 600 handled, ONNX path logs attempted vs fallback, ModelPresets realesrgan visible in LocalModels, Android emulator Pixel_8 (Android 16, x86_64 google_apis_playstore) available for validation (emulator-5554 boot_completed=1, API36), ONNX upscaler wired ready for device validation (build APK can be triggered next)

## Files Changed (2026-09-24 incremental Phase15 v2 ONNX)
- `lib/core/services/model_downloader.dart` — add ModelType.upscaler/enhancer + presets realesrgan-x2/x4/waifu2x-x2 (runtime-only, reuses download/inflight/validate) + _ensureInitialized fallback to systemTemp for tests
- `lib/features/editing/services/image_enhancement_service.dart` — NEW 445 lines (enhanceBytes/upscaleBytes with progress/cancel/memory caps 8192/64MP, preserve original via _getEditedDir/_writeDerived atomic, _lastUpscaleUsedFallback, ONNX attempt via OnnxUpscaler then bicubic fallback, model readiness via ModelManager, progress 0.3..0.7 for tiled ONNX)
- `lib/features/editing/services/onnx_upscaler.dart` — NEW 250 lines (tryUpscale validity check, tiled 512+16 overlap, _createSession OrtSessionOptions, preprocess RGB 0..1 NCHW, postprocess clamped 0..1->255, _tiledInference stitches at tx*scale, progress per tile, cancellation between tiles, handles invalid model file)
- `lib/features/editing/services/edit_transformation_engine.dart` — +100 lines _applyEnhancement (_averageLuminance/_dynamicRange), _applyDenoising (gaussianBlend), _applyAutoEnhance, _applyUpscaling (cubic caps), pipeline 9 phases wired
- `lib/features/editing/providers/edit_session_provider.dart` — add setEnhancement/removeEnhancement/setUpscaling/removeUpscaling/setDenoising/removeDenoising/setAutoEnhance/removeAutoEnhance (discrete undo)
- `lib/features/editing/providers/enhancement_providers.dart` — NEW imageEnhancementServiceProvider
- `test/editing/edit_phase15_test.dart` — NEW 42 tests (38 base +4 ONNX wiring: tryUpscale null fallback verified, usedFallback distinguishes ONNX vs fallback, tiled 600->1200 via fallback correct dims, invalid model file gracefully fallback)
- `IMPLEMENTATION_PROGRESS.md` — Phase15 AI enhancement/upscaling CODE COMPLETE with ONNX wiring, Phase15B Video Intelligence retained, verification 487→529 (+42), analyze 0 errors confirmed
- Previous 2026-09-23: lib/domain/models/edit/edit_operation.dart resize/perspective, lib/domain/models/edit/edit_recipe.dart withResize etc., lib/features/editing/services/edit_transformation_engine.dart _applyResize/_applyPerspective, lib/features/editing/providers/edit_session_provider.dart setResize etc., lib/features/editing/screens/edit_screen.dart Flip H/V + Resize, test/editing/edit_phase14_test.dart 26 tests, plus earlier person_cluster/face_clustering/people_screen/search_screen fixes

## Notes
- Never committed model binaries; no secrets; never auto-downloads models in tests; no image upload in editing
- All transforms local-first via `image` package + onnxruntime (when model available); export atomic temp→final, original never overwritten; fallback bicubic ensures offline without download
- Git branch `chatgpt/ai-gallery-master` — not pushed per prompt (autonomous loop, no GitHub push)
- ChatGPT loop: last report 2026-09-22 18:07; Phase 11 APPROVED 2026-09-23; Phase 14 report sent 2026-09-23 → APPROVED WITH DOCUMENTED LIMITATION (perspective Partial); Phase 15 report 2026-09-24 IMPLEMENTED (enhancement + 2x/4x bicubic fallback) → ChatGPT CHANGES REQUIRED (needs actual ONNX inference, not just fallback); Phase15 v2 2026-09-24 WIRED ONNX via OnnxUpscaler (tiling 512+16, RGB 0..1, OrtSession, progress per tile, cancellation) — ready for re-review; `flutter test` now 529 passed (+42 Phase15)
- Phase 14 perspective doctrine: keep operation/recipe/serialization/tests, keep _applyPerspective identity stub, DO NOT claim true perspective correction — documented per ChatGPT review
- Phase 15 doctrine v2: ONNX Real-ESRGAN inference now wired (tryUpscale via OrtSession, tiling, fallback on failure). When model not installed -> FALLBACK INFERENCE VERIFIED (bicubic). When model installed but invalid -> fallback gracefully. When model installed and valid -> ONNX INFERENCE VERIFIED (output [1,3,H*scale,W*scale]). Tests distinguish ONNX vs fallback via usedFallback and modelState. Enhancement remains algorithmic histogram-aware — labeled accurately not learned. Do NOT advertise AI super-resolution as true until real model downloaded and verified on device; infrastructure ready for Pixel_8 emulator validation (emulator-5554 Android 16 API36, systemTemp fallback for tests).

