import 'package:flutter/material.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';

/// Shows an entry's recovery history: values replaced during sync, each
/// restorable or deletable. Reuses existing strings (no new l10n).
class RecoveryHistoryScreen extends StatefulWidget {
  final List<HistoryRecordData> records;

  /// Restore the record at [index] (set its field back to the saved value).
  final Future<void> Function(int index) onRestore;

  /// Delete the record at [index] without restoring it.
  final Future<void> Function(int index) onDelete;

  const RecoveryHistoryScreen({
    super.key,
    required this.records,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  State<RecoveryHistoryScreen> createState() => _RecoveryHistoryScreenState();
}

const _secretFields = {'password', 'cvv', 'pin', 'transaction_password'};

String _fieldLabel(String field) {
  for (final prefix in const ['custom_fields:', 'attachments:']) {
    if (field.startsWith(prefix)) return field.substring(prefix.length);
  }
  return field;
}

/// File contents are stored as base64 here; never show the raw value.
bool _isBinary(String field) => field == 'data' || field == 'credential';

class _RecoveryHistoryScreenState extends State<RecoveryHistoryScreen> {
  late final List<HistoryRecordData> _records = List.of(widget.records);

  /// Record rows (by index) whose masked secret the user has revealed.
  final Set<int> _revealed = {};

  Future<void> _act(int index, Future<void> Function(int) action) async {
    try {
      await action(index);
      if (mounted) setState(() => _records.removeAt(index));
    } catch (err) {
      if (!mounted) return;
      // A dialog, not a SnackBar: the error carries the full path, which can
      // outgrow the strip, and a SnackBar clips without scrolling (ADR-016).
      await showFailureMessage(
        context,
        AppLocalizations.of(context).recoveryActionFailed(err.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.historyPrevious)),
      body: ListView.separated(
        itemCount: _records.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final r = _records[index];
          final secret = _secretFields.contains(r.field);
          final binary = _isBinary(r.field);
          final revealed = _revealed.contains(index);
          // An attachment row is titled by its filename (the record's value);
          // a uuid tells the user nothing. The value line is dropped — it
          // would repeat the title.
          final isAttachment = r.field.startsWith('attachments:');
          final title = isAttachment && r.value.isNotEmpty
              ? r.value
              : _fieldLabel(r.field);
          final display = binary
              ? '<binary>'
              : (secret && !revealed ? '••••' : r.value);
          // The actions sit under the value, not in `trailing`. `trailing` is
          // intrinsically sized: a longer Revert label (most locales) or larger
          // text made the row demand the whole tile width, and the controls ran
          // off the right edge where they could not be tapped. A Wrap reflows
          // them onto another line instead.
          return ListTile(
            title: Text(title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isAttachment) Text(display),
                Text(
                  l.historySavedOn(
                    formatTimestamp(
                      r.savedAt,
                      unknownLabel: l.timestampUnknown,
                      locale: l.localeName,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (secret)
                      IconButton(
                        iconSize: scaledIconSize(context),
                        icon: Icon(
                          revealed ? Icons.visibility : Icons.visibility_off,
                          semanticLabel: revealed
                              ? l.tooltipHide
                              : l.tooltipShow,
                        ),
                        tooltip: revealed ? l.tooltipHide : l.tooltipShow,
                        onPressed: () => setState(() {
                          if (revealed) {
                            _revealed.remove(index);
                          } else {
                            _revealed.add(index);
                          }
                        }),
                      ),
                    TextButton(
                      onPressed: () => _act(index, widget.onRestore),
                      child: Text(l.revert),
                    ),
                    IconButton(
                      tooltip: l.delete,
                      icon: Icon(
                        Icons.delete_outline,
                        semanticLabel: l.delete,
                      ),
                      onPressed: () => _act(index, widget.onDelete),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
