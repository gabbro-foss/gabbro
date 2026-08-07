import '../gabbro_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

import '../safe_file_picker.dart';

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

  /// Fires only when the native picker returns a path — never while typing.
  /// Lets a caller act on a definite choice (adopt triages the file here)
  /// without reacting to every keystroke.
  final void Function(String path)? onPathPicked;

  /// Fires when the user submits the typed path (Enter / IME done).
  final void Function(String path)? onSubmitted;

  /// Test seams: override the native dialogs to return a path, `null` (cancel),
  /// or throw (portal unavailable). Default to the real `file_picker`.
  final Future<String?> Function()? openPicker;
  final Future<String?> Function()? savePicker;

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
    this.onPathPicked,
    this.onSubmitted,
    this.openPicker,
    this.savePicker,
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

  Future<String?> _defaultOpen() =>
      GabbroFilePicker.pickPath(allowedExtensions: widget.allowedExtensions);

  Future<String?> _defaultSave() => GabbroFilePicker.savePath(
        fileName: widget.saveFileName,
        allowedExtensions: widget.allowedExtensions,
      );

  Future<void> _pick() async {
    final String? picked;
    try {
      picked = widget.mode == PathFieldMode.open
          ? await runPicker(widget.openPicker ?? _defaultOpen)
          : await runPicker(widget.savePicker ?? _defaultSave);
    } on FilePickerUnavailable {
      if (mounted) showPickerUnavailable(context);
      return;
    }
    if (picked != null) {
      setState(() => _controller.text = picked!);
      widget.onPathSelected(picked);
      widget.onPathPicked?.call(picked);
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
      onFieldSubmitted: (v) => widget.onSubmitted?.call(v),
      validator: widget.validator,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hint,
        suffixIcon: widget.readOnly
            ? null
            : IconButton(
                icon: Icon(
                  Icons.folder_open,
                  semanticLabel: AppLocalizations.of(context).tooltipBrowse,
                ),
                tooltip: AppLocalizations.of(context).tooltipBrowse,
                onPressed: _pick,
              ),
      ),
    );
  }
}
