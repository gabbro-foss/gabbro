/// A raw SAF URI means nothing to a user: `content://.../tree/primary%3A...`
/// shows as `primary:Download/...`, a document URI as its folder.
String folderDisplayLabel(String folder) {
  const tree = '/tree/';
  const document = '/document/';
  final t = folder.indexOf(tree);
  if (t >= 0) return Uri.decodeComponent(folder.substring(t + tree.length));
  final d = folder.indexOf(document);
  if (d < 0) return folder;
  final id = Uri.decodeComponent(folder.substring(d + document.length));
  final slash = id.lastIndexOf('/');
  final colon = id.indexOf(':');
  // No folder part: keep the volume (`primary:`).
  if (slash < 0) return colon < 0 ? id : id.substring(0, colon + 1);
  return id.substring(0, slash);
}
