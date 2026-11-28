import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/wechat/transcription_service.dart';
import 'package:material_ui/material_ui.dart';

/// 语音气泡下面的转文字结果。
///
/// 三种状态：转文字中 / 成功（最多 3 行，可点开）/ 失败（点一下重试）。
class TranscriptionBubble extends StatefulWidget {
  const TranscriptionBubble({
    super.key,
    required this.entry,
    required this.color,
    required this.onRetry,
  });

  final TranscriptionEntry entry;
  final Color color;
  final VoidCallback onRetry;

  @override
  State<TranscriptionBubble> createState() => _TranscriptionBubbleState();
}

class _TranscriptionBubbleState extends State<TranscriptionBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final entry = widget.entry;
    final baseStyle = TextStyle(
      color: widget.color.withValues(alpha: 0.85),
      fontSize: 13,
      height: 1.35,
    );

    switch (entry.status) {
      case TranscriptionStatus.loading:
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
          child: Text(l10n.transcribing, style: baseStyle),
        );
      case TranscriptionStatus.failed:
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
          child: InkWell(
            onTap: widget.onRetry,
            child: Text(
              _failedText(l10n),
              style: baseStyle.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
      case TranscriptionStatus.done:
        final text = entry.text;
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: baseStyle,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _expanded ? l10n.transcribeCollapse : l10n.transcribeExpand,
                  style: baseStyle.copyWith(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  String _failedText(L10n l10n) {
    final detail = widget.entry.detail;
    if (detail == null || detail.isEmpty) return l10n.transcribeFailed;
    return l10n.transcribeFailedWith(detail);
  }
}
