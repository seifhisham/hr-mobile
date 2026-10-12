import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../data/models/employee_request.dart';
import '../utils/utils.dart';

class RequestAttachmentService {
  static final instance = RequestAttachmentService();
  FutureEither<RequestAttachment?> pick() => runTask(() async {
        try {
          final result = await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
              withReadStream: true);
          if (result == null) return null;
          final file = result.files.single;
          if (file.size < 1 || file.size > RequestAttachment.maxBytes) {
            throw const FormatException('requests.attachment_invalid');
          }
          final stream = file.readStream ??
              (file.path == null ? null : File(file.path!).openRead());
          if (stream == null) {
            throw const FormatException('requests.attachment_invalid');
          }
          final bytes = <int>[];
          await for (final chunk in stream) {
            bytes.addAll(chunk);
            if (bytes.length > RequestAttachment.maxBytes) {
              throw const FormatException('requests.attachment_invalid');
            }
          }
          final mime = switch (file.extension?.toLowerCase()) {
            'pdf' => 'application/pdf',
            'png' => 'image/png',
            'jpg' || 'jpeg' => 'image/jpeg',
            _ => '',
          };
          final attachment = RequestAttachment(
              name: file.name.trim(),
              mimeType: mime,
              content: base64Encode(bytes));
          attachment.decode();
          return attachment;
        } finally {
          if (Platform.isAndroid || Platform.isIOS) {
            if (await FilePicker.clearTemporaryFiles() == false) {
              AppLogger.warning(
                  'Unable to remove temporary request attachment files',
                  category: LogCategory.app);
            }
          }
        }
      }, operation: 'requests.pick_attachment', category: LogCategory.app);

  FutureEither<bool> savePdf(RequestAttachment attachment) => runTask(() async {
        final bytes = attachment.decode();
        if (attachment.mimeType != 'application/pdf') {
          throw const FormatException('requests.attachment_invalid');
        }
        // Use a safe basename, never an API-provided path.
        final name = attachment.name.split(RegExp(r'[/\\]')).last;
        return await FilePicker.saveFile(
                fileName: name.endsWith('.pdf') ? name : '$name.pdf',
                type: FileType.custom,
                allowedExtensions: ['pdf'],
                bytes: bytes) !=
            null;
      }, operation: 'requests.save_pdf', category: LogCategory.app);
}
