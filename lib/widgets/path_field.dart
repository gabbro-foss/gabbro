import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

enum PathFieldMode { open, save }

class PathField extends StatefulWidget {
  final PathFieldMode mode;
  final String hint;
  final String? initialPath;
  final List<String>? allowedExtensions;
  final String? saveFileName;
  final void Function(String path) onPathSelected;
  final String? Function(String?)? validator;
  final bool readOnly;

  const PathField({
    super.key,
    required this.mode,
    required this.hint,
    required this.onPathSelected,
    this.initialPath,
    this.allowedExtensions,
    this.saveFileName,
    this.validator,
    this.readOnly = false,
  });

  @override
  State<PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<PathField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath ?? '');
  }

  @override
  void didUpdateWidget(PathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect an external initialPath change (e.g. the onboarding alias-driven
    // path preview) without clobbering what the user is actively typing: when
    // the user types, onChanged feeds the same value straight back as
    // initialPath, so incoming == the controller text and we leave it alone.
    final incoming = widget.initialPath ?? '';
    if (incoming != (oldWidget.initialPath ?? '') &&
        incoming != _controller.text) {
      _controller.text = incoming;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    String? picked;
    if (widget.mode == PathFieldMode.open) {
      final result = await FilePicker.pickFiles(
        type: widget.allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: widget.allowedExtensions,
      );
      picked = result?.files.single.path;
    } else {
      picked = await FilePicker.saveFile(
        fileName: widget.saveFileName,
        allowedExtensions: widget.allowedExtensions,
        type: widget.allowedExtensions != null ? FileType.custom : FileType.any,
      );
    }
    if (picked != null) {
      setState(() => _controller.text = picked!);
      widget.onPathSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      // Editable so the user can type or paste a path directly (e.g. when the
      // native file dialog is unavailable under a Wayland bubblewrap sandbox).
      // Only a caller-requested display field stays read-only.
      readOnly: widget.readOnly,
      onChanged: widget.onPathSelected,
      validator: widget.validator,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hint,
        suffixIcon: widget.readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _pick,
              ),
      ),
    );
  }
}
