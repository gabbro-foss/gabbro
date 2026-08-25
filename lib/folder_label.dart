/// Human-readable label for a remembered folder.
///
/// A Linux path is shown as is. An Android SAF tree URI
/// (`content://…/tree/primary%3ADownload%2FGabbroSync`) is shown as
/// `primary:Download/GabbroSync`, since the raw URI means nothing to a user.
String folderDisplayLabel(String folder) {
  const marker = '/tree/';
  final i = folder.indexOf(marker);
  if (i < 0) return folder;
  return Uri.decodeComponent(folder.substring(i + marker.length));
}
