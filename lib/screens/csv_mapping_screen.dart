import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/import.dart';

Future<ImportResult> _defaultImportCsv(
  String input,
  CsvImportConfigData config,
) => importFromCsv(input: input, config: config);

class CsvMappingScreen extends StatefulWidget {
  final String csvContent;
  final CsvPreviewData preview;
  final Future<ImportResult> Function(String input, CsvImportConfigData config)
  onImport;

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
    final l = AppLocalizations.of(context);
    if (_titleCol == null && _urlCol == null) {
      setState(() => _error = l.csvMapTitleOrUrl);
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
    final l = AppLocalizations.of(context);
    final headers = widget.preview.headers;
    // The heading row has a fixed default height (56px); at large text the bold
    // header text is taller and clips mid-height (hardware: tablet 5x). Grow the
    // heading row with the text scale, default below normal (ADR-016).
    final headerScale = MediaQuery.textScalerOf(context).scale(1);
    final headingRowHeight = headerScale > 1.0 ? 56.0 * headerScale : null;
    // Dropdown items: a "(none)" option + all headers
    final items = [
      DropdownMenuItem<String>(value: null, child: Text(l.csvColumnNone)),
      ...headers.map((h) => DropdownMenuItem(value: h, child: Text(h))),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.csvMappingTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Preview table ─────────────────────────────────────────────
              Text(
                l.csvPreviewLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  // No fixed row heights: at large text a capped row clips the
                  // cell text vertically. Let rows grow to their content (ADR-016).
                  headingRowHeight: headingRowHeight,
                  dataRowMaxHeight: double.infinity,
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
                    : Text(l.import),
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
    final labelWidget = Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
    final dropdown = DropdownButtonFormField<String>(
      isExpanded: true, // fill width (ADR-016)
      itemHeight: null, // menu items grow to wrapped height at large text
      initialValue: value,
      isDense: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      // Ellipsize the collapsed one-line selection. Items are all Text by
      // construction (see the `items` list), so read their label back.
      selectedItemBuilder: (context) => items
          .map(
            (it) => Text(
              it.child is Text ? ((it.child as Text).data ?? '') : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
          .toList(),
      items: items,
      onChanged: onChanged,
    );
    // A fixed 88px label column is illegible at large text (wraps to a couple of
    // chars); stack the label above the dropdown instead of beside it (ADR-016).
    final stack = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: labelWidget,
                ),
                dropdown,
              ],
            )
          : Row(
              children: [
                SizedBox(width: 88, child: labelWidget),
                const SizedBox(width: 8),
                Expanded(child: dropdown),
              ],
            ),
    );
  }
}
