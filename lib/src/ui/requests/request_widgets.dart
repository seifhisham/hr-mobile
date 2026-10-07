import 'package:hrmobile/src/imports/imports.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/models/employee_request.dart';
import '../../services/request_attachment_service.dart';
import 'requests_provider.dart';
import '../auth/providers/session_provider.dart';

String requestTypeLabel(String type) => requestTypes.contains(type)
    ? 'requests.types.${type.replaceAll('-', '_')}'.tr()
    : type;
String requestStatusLabel(String status) => requestStatuses.contains(status)
    ? 'requests.statuses.$status'.tr()
    : status;
String requestTime(DateTime value, String timezone) {
  try {
    return DateFormat('yyyy-MM-dd HH:mm')
        .format(tz.TZDateTime.from(value, tz.getLocation(timezone)));
  } on tz.LocationNotFoundException {
    return '${DateFormat('yyyy-MM-dd HH:mm').format(value.toUtc())} UTC';
  }
}

class RequestFeedback extends StatelessWidget {
  const RequestFeedback({super.key, required this.state});
  final RequestsState state;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (state.noticeKey case final key?)
          Semantics(liveRegion: true, child: Text(key.tr())),
        if (state.action case RequestFailure(:final failure))
          Semantics(
              liveRegion: true,
              child: Text(failure.message,
                  style: TextStyle(color: context.colors.error))),
      ]);
}

class RequestAttachmentButton extends ConsumerStatefulWidget {
  const RequestAttachmentButton({super.key, required this.attachment});
  final RequestAttachment attachment;
  @override
  ConsumerState<RequestAttachmentButton> createState() =>
      _RequestAttachmentButtonState();
}

class _RequestAttachmentButtonState
    extends ConsumerState<RequestAttachmentButton> {
  RequestState<void> _state = const RequestInitial();
  Future<void> _open() async {
    if (_state.isLoading) return;
    try {
      if (widget.attachment.mimeType == 'application/pdf') {
        setState(() => _state = const RequestLoading());
        final result =
            await RequestAttachmentService.instance.savePdf(widget.attachment);
        if (!mounted) return;
        setState(() => _state = result.fold(
            (f) => RequestFailure(f), (_) => const RequestSuccess(null)));
      } else {
        final bytes = widget.attachment.decode();
        final userId = ref.read(sessionProvider).userOrNull?.id;
        if (userId == null) return;
        await showDialog<void>(
            context: context,
            builder: (_) => _AttachmentPreview(
                bytes: bytes, name: widget.attachment.name, userId: userId));
      }
    } on FormatException {
      if (mounted) {
        setState(() => _state =
            RequestFailure(ServerFailure('requests.attachment_invalid'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.attachment.name, style: context.textTheme.titleMedium),
        AppButton(
            label: (widget.attachment.mimeType == 'application/pdf'
                    ? 'requests.save_pdf'
                    : 'requests.preview')
                .tr(),
            variant: ButtonVariant.outline,
            isLoading: _state.isLoading,
            onPressed: _open),
        if (_state case RequestFailure(:final failure))
          Text(failure.message, style: TextStyle(color: context.colors.error)),
      ]);
}

class _AttachmentPreview extends ConsumerStatefulWidget {
  const _AttachmentPreview(
      {required this.bytes, required this.name, required this.userId});
  final Uint8List bytes;
  final String name, userId;
  @override
  ConsumerState<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends ConsumerState<_AttachmentPreview> {
  @override
  void dispose() {
    MemoryImage(widget.bytes).evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s.userOrNull?.id), (_, next) {
      if (next != widget.userId &&
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });
    if (ref.watch(sessionProvider.select((s) => s.userOrNull?.id)) !=
        widget.userId) {
      return const SizedBox.shrink();
    }
    return AlertDialog(
        title: Text(widget.name),
        content: Image.memory(widget.bytes,
            semanticLabel: widget.name,
            errorBuilder: (_, __, ___) =>
                Text('requests.attachment_invalid'.tr())),
        actions: [
          AppTextButton(
              label: 'requests.close'.tr(),
              onPressed: () => Navigator.of(context).pop())
        ]);
  }
}
