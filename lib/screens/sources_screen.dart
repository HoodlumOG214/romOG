import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/source.dart';
import '../providers/sources_provider.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSources = ref.watch(sourcesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(sourcesProvider),
          ),
        ],
      ),
      body: asyncSources.when(
        data: (sources) {
          if (sources.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No sources found in the catalog database. '
                  'Download or update the database from Settings → Update.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sources.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, i) => _SourceTile(source: sources[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load sources: $e'),
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final SourceInfo source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHomepage = source.homepage != null && source.homepage!.isNotEmpty;

    return ListTile(
      leading: _StatusDot(status: source.status),
      title: Text(
        source.name,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Chip(label: source.kind),
              if (source.authRequired) const _Chip(label: 'login required'),
              _Chip(label: 'priority ${source.priority}'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _statusLine(source),
            style: theme.textTheme.bodySmall,
          ),
          if (source.statusReason != null && source.statusReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                source.statusReason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      trailing: hasHomepage
          ? IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open ${source.homepage}',
              onPressed: () => _open(source.homepage!),
            )
          : null,
      isThreeLine: true,
    );
  }

  static String _statusLine(SourceInfo source) {
    final parts = <String>[];
    parts.add(_statusLabel(source.status));
    if (source.lastChecked != null) {
      parts.add('checked ${_relative(source.lastChecked!)}');
    }
    if (source.entryCount != null && source.linkCount != null) {
      parts.add(
        '${_compact(source.entryCount!)} entries · ${_compact(source.linkCount!)} links',
      );
    }
    return parts.join(' · ');
  }

  static String _statusLabel(SourceStatus s) {
    switch (s) {
      case SourceStatus.ok:
        return 'OK';
      case SourceStatus.degraded:
        return 'Degraded';
      case SourceStatus.down:
        return 'Down';
      case SourceStatus.stale:
        return 'Stale';
      case SourceStatus.unknown:
        return 'Unknown';
    }
  }

  static String _relative(DateTime when) {
    final delta = DateTime.now().toUtc().difference(when.toUtc());
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    final days = delta.inDays;
    if (days < 30) return '${days}d ago';
    final months = (days / 30).floor();
    if (months < 12) return '${months}mo ago';
    return '${(months / 12).floor()}y ago';
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1_000_000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1_000_000).toStringAsFixed(1)}M';
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SourceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      SourceStatus.ok => Colors.green,
      SourceStatus.degraded => Colors.orange,
      SourceStatus.stale => Colors.amber,
      SourceStatus.down => theme.colorScheme.error,
      SourceStatus.unknown => theme.colorScheme.outline,
    };
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}
