import 'package:flutter/services.dart';

/// Android Storage Access Framework trees (ADR-013): the one way an app reads
/// or overwrites a file another app (a sync client) owns under scoped
/// storage. A tree is picked once, its grant persisted by Kotlin, and later
/// reached by its `content://…/tree/…` URI. Export writes into one; Sync from
/// vault reads this vault's file out of one.
const safTreeChannel = MethodChannel('app.gabbro.gabbro/export');

/// A granted tree: its URI and the folder name the picker showed.
typedef SafTree = ({String treeUri, String displayName});

/// Shows the system folder picker and persists the grant. Null on cancel.
Future<SafTree?> pickSafTree() async {
  final r = await safTreeChannel.invokeMethod<Map<Object?, Object?>>(
    'pick_export_dir',
  );
  if (r == null) return null;
  return (
    treeUri: r['treeUri'] as String,
    displayName: r['displayName'] as String,
  );
}

/// The file called [name] inside the granted [treeUri], copied to the app
/// cache; returns that path. Null when the tree holds no such file.
Future<String?> readSafTreeFile(String treeUri, String name) =>
    safTreeChannel.invokeMethod<String>('read_tree_file', {
      'treeUri': treeUri,
      'name': name,
    });
