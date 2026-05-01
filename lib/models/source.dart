enum SourceStatus { ok, degraded, down, unknown, stale }

extension SourceStatusParse on SourceStatus {
  static SourceStatus fromDb(String? raw) {
    switch (raw) {
      case 'ok':
        return SourceStatus.ok;
      case 'degraded':
        return SourceStatus.degraded;
      case 'down':
        return SourceStatus.down;
      case 'stale':
        return SourceStatus.stale;
      default:
        return SourceStatus.unknown;
    }
  }
}

class SourceInfo {
  final String id;
  final String name;
  final String? homepage;
  final String kind;
  final bool authRequired;
  final int priority;
  final SourceStatus status;
  final DateTime? lastChecked;
  final String? statusReason;
  final int? entryCount;
  final int? linkCount;

  const SourceInfo({
    required this.id,
    required this.name,
    required this.kind,
    this.homepage,
    this.authRequired = false,
    this.priority = 0,
    this.status = SourceStatus.unknown,
    this.lastChecked,
    this.statusReason,
    this.entryCount,
    this.linkCount,
  });
}
