// report_sheet.dart — the one reason picker every Report action uses.
//
// Replaces an unreferenced sheet that had a hardcoded white background (unusable
// in dark mode) and a "Restrict" action with nothing behind it. The reasons here
// are free text as far as the API is concerned, so this list can grow without a
// backend change; `details` is optional and capped at 1000 characters server
// side.

import 'package:flutter/material.dart';
import '../design_system/sejilo_theme.dart';

/// What the reporter chose. Returned by [showReportSheet].
class ReportSubmission {
  const ReportSubmission({required this.reason, this.details});

  final String reason;
  final String? details;
}

const List<String> _reasons = [
  'Spam',
  'Harassment or bullying',
  'Hate speech',
  'Nudity or sexual content',
  'Violence or threats',
  'Impersonation',
  'Scam or fraud',
  'False information',
  'Something else',
];

/// Asks for a reason, then optional detail. Returns null if dismissed.
Future<ReportSubmission?> showReportSheet(
  BuildContext context, {
  required String title,
}) {
  return showModalBottomSheet<ReportSubmission>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportSheet(title: title),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.title});

  final String title;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _details = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = _reason;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              reason == null
                  ? 'Pick the closest reason. Reports are private — the person '
                      'is not told who filed one.'
                  : 'Add anything a reviewer would need to know. Optional.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (reason == null)
              for (final option in _reasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => setState(() => _reason = option),
                )
            else ...[
              InputChip(
                avatar: const Icon(Icons.flag_outlined, size: 16),
                label: Text(reason),
                onDeleted: () => setState(() => _reason = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _details,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: SejiloColors.danger,
                      ),
                      onPressed: () => Navigator.pop(
                        context,
                        ReportSubmission(
                          reason: reason,
                          details: _details.text.trim().isEmpty
                              ? null
                              : _details.text.trim(),
                        ),
                      ),
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: const Text('Send report'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
