import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';

void main() {
  group('CsOrderPhotoPickResult', () {
    test('hasPhoto is true when bytes present', () {
      final pick = CsOrderPhotoPickResult(bytes: Uint8List.fromList([1, 2, 3]));
      expect(pick.hasPhoto, isTrue);
    });

    test('hasPhoto is false when empty', () {
      const pick = CsOrderPhotoPickResult();
      expect(pick.hasPhoto, isFalse);
      expect(CsOrderPhotoPickResult(bytes: Uint8List(0)).hasPhoto, isFalse);
    });
  });
}
