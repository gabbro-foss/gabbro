import 'dart:io';

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

  /// Where the native dialog opens: a remembered folder (Linux path, or on
  /// Android the location the picker last reported). Null = system default.
  final String? startFolder;

  /// Fires with the picked file's folder (the value to remember) when the
  /// native picker returns; never while typing.
  final void Function(String folder)? onFolderPicked;

  /// Test seams: override the native dialogs to return a path, `null` (cancel),
  /// or throw (portal unavailable). Default to the real native dialogs.
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
    this.onFolderPicked,
    this.startFolder,
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

  // The folder to remember: the picker's own answer on the open leg (Android
  // reports a location there); the path's directory otherwise.
  Future<PickedPath?> _defaultOpen() => GabbroFilePicker.pickPathWithFolder(
        allowedExtensions: widget.allowedExtensions,
        startFolder: widget.startFolder,
      );

  Future<PickedPath?> _defaultSave() async {
    final path = await GabbroFilePicker.savePath(
      fileName: widget.saveFileName,
      allowedExtensions: widget.allowedExtensions,
      startFolder: widget.startFolder,
    );
    return path == null ? null : (path: path, folder: File(path).parent.path);
  }

  Future<PickedPath?> _viaSeam(Future<String?> Function() seam) async {
    final path = await seam();
    return path == null ? null : (path: path, folder: File(path).parent.path);
  }

  Future<void> _pick() async {
    final PickedPath? picked;
    try {
      final open = widget.mode == PathFieldMode.open;
      final seam = open ? widget.openPicker : widget.savePicker;
      picked = await runPicker(seam != null
          ? () => _viaSeam(seam)
          : (open ? _defaultOpen : _defaultSave));
    } on FilePickerUnavailable {
      if (mounted) showPickerUnavailable(context);
      return;
    }
    if (picked != null) {
      setState(() => _controller.text = picked!.path);
      widget.onPathSelected(picked.path);
      widget.onPathPicked?.call(picked.path);
      widget.onFolderPicked?.call(picked.folder);
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
