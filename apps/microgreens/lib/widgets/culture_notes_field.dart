import 'dart:async';

import 'package:flutter/material.dart';

import '../state/plant_notes_store.dart';
import '../theme/app_theme.dart';

/// Multiline notes for a knowledge-base culture.
class CultureNotesField extends StatefulWidget {
  const CultureNotesField({super.key, required this.plantId});

  final String plantId;

  @override
  State<CultureNotesField> createState() => _CultureNotesFieldState();
}

class _CultureNotesFieldState extends State<CultureNotesField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _edited = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await PlantNotesStore.noteFor(widget.plantId);
    if (!mounted || _edited) return;
    _controller.text = text;
    setState(() {});
  }

  void _onChanged(String _) {
    _edited = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() =>
      PlantNotesStore.setNote(widget.plantId, _controller.text);

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
        Text(
          'Заметки',
          style: Theme.of(context).textTheme.titleLarge,
        ),
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
            ),
          ),
        ),
      ],
    );
  }
}
