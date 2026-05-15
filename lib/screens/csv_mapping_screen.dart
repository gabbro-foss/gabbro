import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/import.dart';

Future<ImportResult> _defaultImportCsv(String input, CsvImportConfigData config) =>
    importFromCsv(input: input, config: config);

class CsvMappingScreen extends StatefulWidget {
  final String csvContent;
  final CsvPreviewData preview;
  final Future<ImportResult> Function(String input, CsvImportConfigData config) onImport;

  const CsvMappingScreen({
    super.key,
    required this.csvContent,
    required this.preview,
    this.onImport = _defaultImportCsv,
  });

  @override
  State<CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends State<CsvMappingScreen> {
  late String? _titleCol;
  late String? _urlCol;
  late String? _usernameCol;
  late String? _passwordCol;
  late String? _notesCol;
  bool _isImporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-select columns by common name guessing
    _titleCol = _guess(['title', 'name', 'label']);
    _urlCol = _guess(['url', 'uri', 'website', 'site']);
    _usernameCol = _guess(['username', 'user', 'login', 'email']);
    _passwordCol = _guess(['password', 'pass', 'secret']);
    _notesCol = _guess(['notes', 'note', 'comments', 'comment']);
  }

  /// Return the first header that contains any of the candidate strings
  /// (case-insensitive), or null if none match.
  String? _guess(List<String> candidates) {
    for (final header in widget.preview.headers) {
      final lower = header.toLowerCase();
      if (candidates.any((c) => lower.contains(c))) return header;
    }
    return null;
  }

  Future<void> _import() async {
    if (_titleCol == null && _urlCol == null) {
      setState(
        () => _error = 'Map at least Title or URL so entries have a name.',
      );
      return;
    }
    setState(() {
      _isImporting = true;
      _error = null;
    });
    try {
      final config = CsvImportConfigData(
        titleCol: _titleCol,
        urlCol: _urlCol,
        usernameCol: _usernameCol,
        passwordCol: _passwordCol,
        notesCol: _notesCol,
      );
      final result = await widget.onImport(widget.csvContent, config);
      if (mounted) Navigator.of(context).pop(result.imported.toInt());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headers = widget.preview.headers;
    // Dropdown items: a "(none)" option + all headers
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...headers.map((h) => DropdownMenuItem(value: h, child: Text(h))),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Map CSV columns')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Preview table ─────────────────────────────────────────────
              Text('Preview', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 28,
                  columnSpacing: 16,
                  columns: headers
                      .map(
                        (h) => DataColumn(
                          label: Text(
                            h,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                      .toList(),
                  rows: widget.preview.rows
                      .map(
                        (row) => DataRow(
                          cells: List.generate(
                            headers.length,
                            (i) => DataCell(
                              Text(
                                i < row.length ? row[i] : '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 24),

              // ── Warning ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Only import CSV files you exported yourself from a trusted password manager.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),

              // ── Column mapping dropdowns ──────────────────────────────────
              Text(
                'Column mapping',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              _mappingRow(
                'Title',
                _titleCol,
                items,
                (v) => setState(() => _titleCol = v),
              ),
              _mappingRow(
                'URL',
                _urlCol,
                items,
                (v) => setState(() => _urlCol = v),
              ),
              _mappingRow(
                'Username',
                _usernameCol,
                items,
                (v) => setState(() => _usernameCol = v),
              ),
              _mappingRow(
                'Password',
                _passwordCol,
                items,
                (v) => setState(() => _passwordCol = v),
              ),
              _mappingRow(
                'Notes',
                _notesCol,
                items,
                (v) => setState(() => _notesCol = v),
              ),
              const SizedBox(height: 16),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),

              FilledButton(
                onPressed: _isImporting ? null : _import,
                child: _isImporting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mappingRow(
    String label,
    String? value,
    List<DropdownMenuItem<String>> items,
    void Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
