import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../utils/utils.dart';

Future<void> deleteAttendancePhoto(XFile photo) async {
  try {
    final file = File(photo.path);
    if (await file.exists()) await file.delete();
  } catch (error) {
    AppLogger.warning('Unable to remove temporary attendance photo',
        context: {'type': error.runtimeType.toString()});
  }
}
