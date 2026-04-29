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

  const PathField({
    super.key,
    required this.mode,
    required this.hint,
    required this.onPathSelected,
    this.initialPath,
    this.allowedExtensions,
    this.saveFileName,
    this.validator,
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
      readOnly: true,
      validator: widget.validator,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hint,
        suffixIcon: IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: _pick,
        ),
      ),
    );
  }
}
