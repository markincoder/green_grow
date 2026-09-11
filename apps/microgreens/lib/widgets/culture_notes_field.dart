import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/culture_note_photo.dart';
import '../state/plant_notes_store.dart';
import '../state/plant_photos_store.dart';
import '../theme/app_theme.dart';

/// Multiline notes + local photo gallery for a knowledge-base culture.
class CultureNotesField extends StatefulWidget {
  const CultureNotesField({super.key, required this.plantId});

  final String plantId;

  @override
  State<CultureNotesField> createState() => _CultureNotesFieldState();
}

class _CultureNotesFieldState extends State<CultureNotesField> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  Timer? _debounce;
  var _edited = false;
  var _busy = false;
  List<CultureNotePhoto> _photos = const [];
  final Map<String, Uint8List> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await PlantNotesStore.noteFor(widget.plantId);
    final photos = await PlantPhotosStore.listFor(widget.plantId);
    if (!mounted) return;
    if (!_edited) _controller.text = text;
    setState(() => _photos = photos);
    for (final photo in photos) {
      unawaited(_ensureThumb(photo));
    }
  }

  Future<void> _ensureThumb(CultureNotePhoto photo) async {
    if (_thumbs.containsKey(photo.id)) return;
    final bytes = await PlantPhotosStore.bytesFor(photo);
    if (!mounted || bytes == null) return;
    setState(() => _thumbs[photo.id] = bytes);
  }

  void _onChanged(String _) {
    _edited = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() =>
      PlantNotesStore.setNote(widget.plantId, _controller.text);

  Future<void> _persistBytes(Uint8List bytes) async {
    if (_busy) return;
    if (_photos.length >= PlantPhotosStore.maxPerPlant) {
      _toast('Не больше ${PlantPhotosStore.maxPerPlant} фото на культуру');
      return;
    }
    setState(() => _busy = true);
    try {
      final photo = await PlantPhotosStore.add(
        plantId: widget.plantId,
        bytes: bytes,
      );
      if (!mounted) return;
      if (photo == null) {
        _toast('Не больше ${PlantPhotosStore.maxPerPlant} фото на культуру');
        return;
      }
      setState(() {
        _photos = [photo, ..._photos];
        _thumbs[photo.id] = bytes;
      });
    } catch (e, st) {
      debugPrint('CultureNotesField: add photo failed: $e\n$st');
      if (mounted) _toast('Не удалось сохранить фото');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_busy) return;
    if (_photos.length >= PlantPhotosStore.maxPerPlant) {
      _toast('Не больше ${PlantPhotosStore.maxPerPlant} фото на культуру');
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _persistBytes(bytes);
    } catch (e, st) {
      debugPrint('CultureNotesField: pick photo failed: $e\n$st');
      if (mounted) {
        _toast(
          source == ImageSource.camera
              ? 'Камера недоступна — выберите файл'
              : 'Не удалось открыть выбор фото',
        );
      }
    }
  }

  /// On web the file dialog must open inside the same click as the menu item.
  /// Picking after [showModalBottomSheet] returns is blocked on desktop browsers.
  Future<XFile?> _pickImageInGesture(ImageSource source) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e, st) {
      debugPrint('CultureNotesField: pick $source failed: $e\n$st');
      if (mounted) {
        _toast(
          source == ImageSource.camera
              ? 'Камера недоступна — выберите файл'
              : 'Не удалось открыть выбор фото',
        );
      }
      return null;
    }
  }

  Future<void> _pickSource() async {
    if (_busy) return;
    if (_photos.length >= PlantPhotosStore.maxPerPlant) {
      _toast('Не больше ${PlantPhotosStore.maxPerPlant} фото на культуру');
      return;
    }

    if (kIsWeb) {
      final file = await showModalBottomSheet<XFile?>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Сфотографировать'),
                onTap: () async {
                  final picked = await _pickImageInGesture(ImageSource.camera);
                  if (ctx.mounted) Navigator.pop(ctx, picked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Выбрать файл'),
                onTap: () async {
                  final picked = await _pickImageInGesture(ImageSource.gallery);
                  if (ctx.mounted) Navigator.pop(ctx, picked);
                },
              ),
            ],
          ),
        ),
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _persistBytes(bytes);
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сфотографировать'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Из галереи'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _addPhoto(source);
  }

  Future<void> _openViewer(int index) async {
    final updated = await Navigator.of(context).push<List<CultureNotePhoto>>(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerPage(
          photos: _photos,
          initialIndex: index,
          thumbs: Map<String, Uint8List>.from(_thumbs),
        ),
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() => _photos = updated);
      _thumbs.removeWhere((id, _) => !_photos.any((p) => p.id == id));
      for (final photo in _photos) {
        unawaited(_ensureThumb(photo));
      }
    } else {
      await _load();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_edited) {
      unawaited(_save());
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Заметки',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Добавить фото',
              onPressed: _busy ? null : _pickSource,
              icon: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              color: AppColors.leaf,
            ),
          ],
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = _photos[index];
                final bytes = _thumbs[photo.id];
                return InkWell(
                  onTap: () => _openViewer(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: bytes == null
                              ? Container(
                                  color: AppColors.mist,
                                  alignment: Alignment.center,
                                  child: const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 72,
                        child: Text(
                          photo.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ] else
          const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.mist),
          ),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Текст заметки…',
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.photos,
    required this.initialIndex,
    required this.thumbs,
  });

  final List<CultureNotePhoto> photos;
  final int initialIndex;
  final Map<String, Uint8List> thumbs;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _page;
  late List<CultureNotePhoto> _photos;
  late Map<String, Uint8List> _bytes;
  late int _index;
  final _caption = TextEditingController();
  Timer? _captionDebounce;
  var _dirtyCaption = false;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _bytes = Map.of(widget.thumbs);
    _index = widget.initialIndex.clamp(0, _photos.length - 1);
    _page = PageController(initialPage: _index);
    _syncCaptionField();
    unawaited(_loadMissingBytes());
  }

  CultureNotePhoto get _current => _photos[_index];

  void _syncCaptionField() {
    _caption.text = _current.caption;
    _dirtyCaption = false;
  }

  Future<void> _loadMissingBytes() async {
    for (final photo in _photos) {
      if (_bytes.containsKey(photo.id)) continue;
      final data = await PlantPhotosStore.bytesFor(photo);
      if (!mounted || data == null) continue;
      setState(() => _bytes[photo.id] = data);
    }
  }

  void _onCaptionChanged(String value) {
    _dirtyCaption = true;
    _captionDebounce?.cancel();
    _captionDebounce = Timer(const Duration(milliseconds: 400), () async {
      final photo = _current;
      await PlantPhotosStore.updateCaption(photo, value);
      if (!mounted) return;
      setState(() {
        _photos[_index] = photo.copyWith(caption: value.trim());
        _dirtyCaption = false;
      });
    });
  }

  Future<void> _flushCaption() async {
    _captionDebounce?.cancel();
    if (!_dirtyCaption) return;
    final photo = _current;
    final value = _caption.text;
    await PlantPhotosStore.updateCaption(photo, value);
    if (!mounted) return;
    setState(() {
      _photos[_index] = photo.copyWith(caption: value.trim());
      _dirtyCaption = false;
    });
  }

  Future<void> _share() async {
    await _flushCaption();
    final photo = _current;
    var data = _bytes[photo.id];
    data ??= await PlantPhotosStore.bytesFor(photo);
    if (data == null || !mounted) {
      _toast('Не удалось открыть фото');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data,
              mimeType: 'image/jpeg',
              name: '${photo.id}.jpg',
            ),
          ],
          text: photo.caption.isEmpty ? null : photo.caption,
          downloadFallbackEnabled: true,
        ),
      );
    } catch (e, st) {
      debugPrint('share photo failed: $e\n$st');
      if (mounted) _toast('Не удалось поделиться');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text('Фото будет удалено с устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.leaf,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _flushCaption();
    final photo = _current;
    await PlantPhotosStore.delete(photo);
    if (!mounted) return;
    setState(() {
      _bytes.remove(photo.id);
      _photos.removeAt(_index);
      if (_photos.isEmpty) {
        Navigator.pop(context, _photos);
        return;
      }
      _index = _index.clamp(0, _photos.length - 1);
      _syncCaptionField();
    });
    if (_photos.isNotEmpty && _page.hasClients) {
      _page.jumpToPage(_index);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _captionDebounce?.cancel();
    if (_dirtyCaption && _photos.isNotEmpty) {
      unawaited(
        PlantPhotosStore.updateCaption(_current, _caption.text),
      );
    }
    _caption.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_flushCaption().then((_) {
          if (context.mounted) Navigator.pop(context, _photos);
        }));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            _photos.isEmpty
                ? ''
                : '${_index + 1} / ${_photos.length}',
          ),
          actions: [
            IconButton(
              tooltip: 'Поделиться',
              onPressed: _photos.isEmpty ? null : _share,
              icon: const Icon(Icons.ios_share_rounded),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: _photos.isEmpty ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: _photos.isEmpty
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _page,
                      itemCount: _photos.length,
                      onPageChanged: (i) async {
                        await _flushCaption();
                        if (!mounted) return;
                        setState(() {
                          _index = i;
                          _syncCaptionField();
                        });
                      },
                      itemBuilder: (context, i) {
                        final photo = _photos[i];
                        final data = _bytes[photo.id];
                        if (data == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return InteractiveViewer(
                          child: Center(
                            child: Image.memory(
                              data,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    color: Colors.black,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: TextField(
                      controller: _caption,
                      onChanged: _onCaptionChanged,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.sprout,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Подпись',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.sprout),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
