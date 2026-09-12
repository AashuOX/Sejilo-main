// my_reports_page.dart — the reports this account has filed.
//
// This replaces a "moderation queue" screen that generated eight fake reports
// and answered review taps with a SnackBar. There is no moderator tooling in
// this deployment, and the server deliberately never returns another person's
// reports, so what an ordinary user can honestly be shown is their own history.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../design_system/components/sejilo_state_views.dart';
import '../design_system/sejilo_theme.dart';
import '../settings/settings_section.dart';

class MyReportsPage extends StatefulWidget {
  const MyReportsPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  List<FiledReport>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.auth.loadMyReports();
      if (!mounted) return;
      setState(() => _reports = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reports you have filed',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return SejiloErrorView(
        title: 'Reports unavailable',
        message: _error!,
        onRetry: _load,
      );
    }
    final reports = _reports;
    if (reports == null) {
      return const SejiloLoadingView(message: 'Loading your reports…');
    }
    if (reports.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: const SejiloEmptyView(
              icon: Icons.flag_outlined,
              title: 'No reports filed',
              description:
                  'Use "Report" on a post or profile when something breaks the '
                  'rules. Anything you send lands here so you can see whether '
                  'it has been reviewed.',
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) => _ReportTile(report: reports[index]),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final FiledReport report;

  @override
  Widget build(BuildContext context) {
    final isPost = report.targetType == 'post';
    final label = report.targetLabel ??
        (report.targetDeleted
            ? (isPost ? 'Post has been deleted' : 'Account no longer exists')
            : 'Unavailable');

    return ListTile(
      isThreeLine: report.details != null,
      leading: Icon(
        isPost ? Icons.photo_outlined : Icons.person_outline_rounded,
        color: SejiloColors.primary,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${report.reason} · ${settingsRelativeDate(report.createdAt)}'),
          if (report.details != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                report.details!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: _StatusChip(status: report.status),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      'resolved' => (SejiloColors.darkSuccess, 'Actioned'),
      'dismissed' => (Theme.of(context).disabledColor, 'Dismissed'),
      _ => (SejiloColors.primary, 'Under review'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
