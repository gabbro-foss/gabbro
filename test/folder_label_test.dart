import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/folder_label.dart';

void main() {
  test('a Linux path is shown as is', () {
    expect(folderDisplayLabel('/home/user/GabbroSync'), '/home/user/GabbroSync');
  });

  test('an Android tree URI is shown as its decoded tree id', () {
    expect(
      folderDisplayLabel(
        'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FGabbroSync',
      ),
      'primary:Download/GabbroSync',
    );
  });

  test('empty stays empty', () {
    expect(folderDisplayLabel(''), '');
  });
}
