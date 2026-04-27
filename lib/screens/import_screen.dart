import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';

Future<BigInt> _defaultImportEnpass(List<int> data) =>
    importFromEnpass(data: data);
Future<BigInt> _defaultImportBitwarden(List<int> data) =>
    importFromBitwarden(data: data);
CsvPreviewData _defaultSniffCsv(String input) => sniffCsvFile(input: input);

class ImportScreen extends StatefulWidget {
  final Future<BigInt> Function(List<int> data) onImportEnpass;
  final Future<BigInt> Function(List<int> data) onImportBitwarden;
  final CsvPreviewData Function(String input) onSniffCsv;

  const ImportScreen({
    super.key,
    this.onImportEnpass = _defaultImportEnpass,
    this.onImportBitwarden = _defaultImportBitwarden,
    this.onSniffCsv = _defaultSniffCsv,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _enpassPathController = TextEditingController();
  final _bitwardenPathController = TextEditingController();
  final _csvPathController = TextEditingController();

  bool _isImportingEnpass = false;
  bool _isImportingBitwarden = false;
  bool _isSniffingCsv = false;

  String? _enpassError;
  String? _bitwardenError;
  String? _csvError;

  @override
  void dispose() {
    _enpassPathController.dispose();
    _bitwardenPathController.dispose();
    _csvPathController.dispose();
    super.dispose();
  }

  // ── Enpass ───────────────────────────────────────────────────────────────

  Future<void> _importEnpass() async {
    final path = _enpassPathController.text.trim();
    if (path.isEmpty) {
      setState(() => _enpassError = 'Enter a file path.');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _enpassError = 'File not found.');
      return;
    }
    setState(() {
      _isImportingEnpass = true;
      _enpassError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final count = await widget.onImportEnpass(bytes);
      if (mounted) Navigator.of(context).pop(count.toInt());
    } catch (e) {
      if (mounted) setState(() => _enpassError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingEnpass = false);
    }
  }

  // ── Bitwarden ────────────────────────────────────────────────────────────

  Future<void> _importBitwarden() async {
    final path = _bitwardenPathController.text.trim();
    if (path.isEmpty) {
      setState(() => _bitwardenError = 'Enter a file path.');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _bitwardenError = 'File not found.');
      return;
    }
    setState(() {
      _isImportingBitwarden = true;
      _bitwardenError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final count = await widget.onImportBitwarden(bytes);
      if (mounted) Navigator.of(context).pop(count.toInt());
    } catch (e) {
      if (mounted) setState(() => _bitwardenError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingBitwarden = false);
    }
  }

  // ── CSV ──────────────────────────────────────────────────────────────────

  Future<void> _sniffAndPushCsvMapping() async {
    final path = _csvPathController.text.trim();
    if (path.isEmpty) {
      setState(() => _csvError = 'Enter a file path.');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _csvError = 'File not found.');
      return;
    }
    setState(() {
      _isSniffingCsv = true;
      _csvError = null;
    });
    try {
      final content = await file.readAsString();
      final preview = widget.onSniffCsv(content);
      if (!mounted) return;
      final count = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (context) =>
              CsvMappingScreen(csvContent: content, preview: preview),
        ),
      );
      if (mounted && count != null) Navigator.of(context).pop(count);
    } catch (e) {
      if (mounted) setState(() => _csvError = e.toString());
    } finally {
      if (mounted) setState(() => _isSniffingCsv = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import entries')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _importSection(
                title: 'Enpass',
                subtitle: 'JSON export from Enpass (Tools → Export)',
                controller: _enpassPathController,
                hint: '/home/user/enpass_export.json',
                isLoading: _isImportingEnpass,
                error: _enpassError,
                onImport: _importEnpass,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _importSection(
                title: 'Bitwarden',
                subtitle:
                    'Unencrypted JSON export from Bitwarden (Tools → Export Vault)',
                controller: _bitwardenPathController,
                hint: '/home/user/bitwarden_export.json',
                isLoading: _isImportingBitwarden,
                error: _bitwardenError,
                onImport: _importBitwarden,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _csvSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importSection({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required bool isLoading,
    required String? error,
    required VoidCallback onImport,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'File path',
            hintText: hint,
            errorText: error,
          ),
          onFieldSubmitted: (_) => isLoading ? null : onImport(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: isLoading ? null : onImport,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }

  Widget _csvSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Generic CSV', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'CSV export from any password manager',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _csvPathController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'File path',
            hintText: '/home/user/passwords.csv',
            errorText: _csvError,
          ),
          onFieldSubmitted: (_) =>
              _isSniffingCsv ? null : _sniffAndPushCsvMapping(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isSniffingCsv ? null : _sniffAndPushCsvMapping,
          child: _isSniffingCsv
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Next: map columns'),
        ),
      ],
    );
  }
}
