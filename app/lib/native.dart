import 'dart:convert';

import 'package:flutter/services.dart';

/// Thin client over the Kotlin layer.
///
/// Everything that must survive the app being killed — call detection, alarms, SMS, the
/// bridge, notifications — lives natively. This file is the only place that knows how to
/// ask it questions, and every reply arrives as a JSON string decoded into the models below.
class Native {
  static const MethodChannel _channel = MethodChannel('cc.ubermensch.ctm/native');

  static Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final raw = await _channel.invokeMethod<String>(method, args);
    if (raw == null || raw.isEmpty) return const {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Routes pushed from a notification tap. The first is delivered on launch; later ones
  /// arrive while the app is already running.
  static void listen({
    required void Function(String route) onNavigate,
    required void Function() onPermissionsChanged,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'navigate':
          final route = call.arguments as String?;
          if (route != null) onNavigate(route);
        case 'permissionsChanged':
          onPermissionsChanged();
      }
      return null;
    });
  }

  static Future<String?> takeInitialRoute() =>
      _channel.invokeMethod<String>('takeInitialRoute');

  // ---- status -------------------------------------------------------------------

  static Future<AppStatus> status() async => AppStatus.fromJson(await _call('getStatus'));

  /// Writes a setting and returns the refreshed status, since several settings have
  /// side effects natively (starting the watchdog, re-arming the daily alarm).
  static Future<AppStatus> setSetting(String key, String value) async {
    await _call('setSetting', {'key': key, 'value': value});
    return status();
  }

  // ---- rules --------------------------------------------------------------------

  static Future<List<Rule>> rules() async {
    final json = await _call('getRules');
    return (json['rules'] as List).map((e) => Rule.fromJson(e)).toList();
  }

  static Future<List<Rule>> saveRule(Rule rule) async {
    final json = await _call('saveRule', {'rule': jsonEncode(rule.toJson())});
    return (json['rules'] as List).map((e) => Rule.fromJson(e)).toList();
  }

  static Future<List<Rule>> deleteRule(int id) async {
    final json = await _call('deleteRule', {'id': id});
    return (json['rules'] as List).map((e) => Rule.fromJson(e)).toList();
  }

  static Future<List<Rule>> reorderRules(List<int> ids) async {
    final json = await _call('reorderRules', {'ids': ids});
    return (json['rules'] as List).map((e) => Rule.fromJson(e)).toList();
  }

  // ---- history ------------------------------------------------------------------

  static Future<List<LogEntry>> log({
    int limit = 100,
    int offset = 0,
    int? dayStart,
    String? status,
    String? channel,
  }) async {
    final json = await _call('getLog', {
      'limit': limit,
      'offset': offset,
      'dayStart': ?dayStart,
      'status': ?status,
      'channel': ?channel,
    });
    return (json['entries'] as List).map((e) => LogEntry.fromJson(e)).toList();
  }

  static Future<LogDetail?> logEntry(int id) async {
    final json = await _call('getLogEntry', {'id': id});
    return json.isEmpty ? null : LogDetail.fromJson(json);
  }

  static Future<LogDetail?> entryForOutbox(int outboxId) async {
    final json = await _call('findEntryForOutbox', {'outboxId': outboxId});
    return json.isEmpty ? null : LogDetail.fromJson(json);
  }

  static Future<void> retry(int outboxId) => _call('retryOutbox', {'outboxId': outboxId});

  static Future<void> clearHistory() => _call('clearHistory');

  // ---- number list --------------------------------------------------------------

  static Future<List<ListedNumber>> numberList() async {
    final json = await _call('getNumberList');
    return (json['numbers'] as List).map((e) => ListedNumber.fromJson(e)).toList();
  }

  static Future<List<ListedNumber>> addNumber(String number, {String? note}) async {
    final json = await _call('addNumber', {'number': number, 'note': note});
    return (json['numbers'] as List).map((e) => ListedNumber.fromJson(e)).toList();
  }

  static Future<List<ListedNumber>> removeNumber(int id) async {
    final json = await _call('removeNumber', {'id': id});
    return (json['numbers'] as List).map((e) => ListedNumber.fromJson(e)).toList();
  }

  // ---- setup --------------------------------------------------------------------

  static Future<SetupStatus> setupStatus() async =>
      SetupStatus.fromJson(await _call('getSetupStatus'));

  static Future<void> requestPermissions() => _call('requestPermissions');

  static Future<void> openSystemPage(String key) => _call('openSystemPage', {'key': key});

  static Future<AppStatus> completeSetup() async =>
      AppStatus.fromJson(await _call('completeSetup'));

  // ---- helpers ------------------------------------------------------------------

  static Future<List<SimCard>> sims() async {
    final json = await _call('getSims');
    return (json['sims'] as List).map((e) => SimCard.fromJson(e)).toList();
  }

  static Future<MessageShape> describeMessage(String body) async =>
      MessageShape.fromJson(await _call('describeMessage', {'body': body}));

  // ---- bridge -------------------------------------------------------------------

  static Future<AppStatus> bridgeRegister(String inviteCode, String name) async =>
      AppStatus.fromJson(await _call('bridgeRegister', {
        'inviteCode': inviteCode,
        'name': name,
      }));

  static Future<PairingSession> bridgeCreateSession(String phone) async =>
      PairingSession.fromJson(await _call('bridgeCreateSession', {'phone': phone}));

  static Future<Map<String, dynamic>> bridgeSessionStatus() => _call('bridgeSessionStatus');

  static Future<String?> bridgePairingCode() async {
    final json = await _call('bridgePairingCode');
    return json['code'] as String?;
  }

  static Future<BridgeState> bridgeStats() async =>
      BridgeState.fromJson(await _call('bridgeStats'));

  static Future<void> bridgeReconnect() => _call('bridgeReconnect');

  static Future<AppStatus> bridgeLogout() async =>
      AppStatus.fromJson(await _call('bridgeLogout'));

  static Future<void> testSend({
    required String channel,
    required String to,
    required String text,
  }) =>
      _call('testSend', {'channel': channel, 'to': to, 'text': text});
}

// ---- models ---------------------------------------------------------------------

class AppStatus {
  AppStatus({
    required this.settings,
    required this.today,
    required this.health,
    required this.bridgeLinked,
    required this.whatsappInstalled,
    required this.accessibilityEnabled,
    required this.setupComplete,
    required this.recent,
    required this.appVersion,
  });

  final String appVersion;
  final Map<String, String> settings;
  final DayCounts today;
  final Health health;
  final bool bridgeLinked;
  final bool whatsappInstalled;
  final bool accessibilityEnabled;
  final bool setupComplete;
  final List<LogEntry> recent;

  factory AppStatus.fromJson(Map<String, dynamic> json) => AppStatus(
        settings: (json['settings'] as Map).map((k, v) => MapEntry('$k', '$v')),
        today: DayCounts.fromJson(json['today'] as Map<String, dynamic>),
        health: Health.fromJson(json['health'] as Map<String, dynamic>),
        bridgeLinked: json['bridgeLinked'] as bool? ?? false,
        whatsappInstalled: json['whatsappInstalled'] as bool? ?? false,
        accessibilityEnabled: json['accessibilityEnabled'] as bool? ?? false,
        setupComplete: json['setupComplete'] as bool? ?? false,
        recent: ((json['recent'] as List?) ?? const [])
            .map((e) => LogEntry.fromJson(e))
            .toList(),
        appVersion: json['appVersion'] as String? ?? '?',
      );

  bool get masterEnabled => settings['master_enabled'] == '1';
  String get theme => settings['theme'] ?? 'system';
  int get delaySeconds => int.tryParse(settings['default_delay_seconds'] ?? '60') ?? 60;
  String get counterResetMode => settings['counter_reset_mode'] ?? 'answered';
  String get whatsappMode => settings['whatsapp_mode'] ?? 'bridge';
  bool get quietEnabled => settings['quiet_enabled'] == '1';
  int get quietStart => int.tryParse(settings['quiet_start'] ?? '1380') ?? 1380;
  int get quietEnd => int.tryParse(settings['quiet_end'] ?? '480') ?? 480;
  bool get dailySummaryEnabled => settings['daily_summary_enabled'] == '1';
  int get dailySummaryMinute => int.tryParse(settings['daily_summary_minute'] ?? '1260') ?? 1260;
  String get listMode => settings['list_mode'] ?? 'off';
  int get dedupeMinutes => int.tryParse(settings['dedupe_minutes'] ?? '10') ?? 10;
  int get simSubscriptionId => int.tryParse(settings['sim_subscription_id'] ?? '-1') ?? -1;
  String get bridgeUrl => settings['bridge_url'] ?? 'https://ctm.ubermensch.cc';
  String get countryCode => settings['default_country_code'] ?? '90';
}

class DayCounts {
  const DayCounts({
    required this.missed,
    required this.sent,
    required this.failed,
    required this.cancelled,
    required this.skipped,
  });

  final int missed;
  final int sent;
  final int failed;
  final int cancelled;
  final int skipped;

  factory DayCounts.fromJson(Map<String, dynamic> json) => DayCounts(
        missed: json['missed'] as int? ?? 0,
        sent: json['sent'] as int? ?? 0,
        failed: json['failed'] as int? ?? 0,
        cancelled: json['cancelled'] as int? ?? 0,
        skipped: json['skipped'] as int? ?? 0,
      );
}

class Health {
  const Health({
    required this.ringsSeen,
    required this.alarmsFired,
    required this.watchdogRestarts,
    required this.startRefusals,
    required this.lastEventKind,
    required this.lastEventAt,
  });

  final int ringsSeen;
  final int alarmsFired;
  final int watchdogRestarts;
  final int startRefusals;
  final String? lastEventKind;
  final int? lastEventAt;

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        ringsSeen: json['ringsSeen24h'] as int? ?? 0,
        alarmsFired: json['alarmsFired24h'] as int? ?? 0,
        watchdogRestarts: json['watchdogRestarts24h'] as int? ?? 0,
        startRefusals: json['startRefusals24h'] as int? ?? 0,
        lastEventKind: json['lastEventKind'] as String?,
        lastEventAt: json['lastEventAt'] as int?,
      );

  /// The honest read on whether the OS is letting the app do its job.
  bool get looksHealthy => startRefusals == 0 && watchdogRestarts < 10;
}

class Rule {
  Rule({
    this.id,
    required this.name,
    this.enabled = true,
    this.attemptMin,
    this.attemptMax,
    this.timeStart,
    this.timeEnd,
    this.contactFilter = 'any',
    this.channel = 'sms',
    this.delaySeconds,
    this.messages = const [],
  });

  final int? id;
  final String name;
  final bool enabled;
  final int? attemptMin;
  final int? attemptMax;
  final int? timeStart;
  final int? timeEnd;
  final String contactFilter;
  final String channel;
  final int? delaySeconds;
  final List<String> messages;

  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
        id: json['id'] as int?,
        name: json['name'] as String? ?? 'Rule',
        enabled: json['enabled'] as bool? ?? true,
        attemptMin: json['attemptMin'] as int?,
        attemptMax: json['attemptMax'] as int?,
        timeStart: json['timeStart'] as int?,
        timeEnd: json['timeEnd'] as int?,
        contactFilter: json['contactFilter'] as String? ?? 'any',
        channel: json['channel'] as String? ?? 'sms',
        delaySeconds: json['delaySeconds'] as int?,
        messages: ((json['messages'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'attemptMin': attemptMin,
        'attemptMax': attemptMax,
        'timeStart': timeStart,
        'timeEnd': timeEnd,
        'contactFilter': contactFilter,
        'channel': channel,
        'delaySeconds': delaySeconds,
        'messages': messages,
      };

  Rule copyWith({
    String? name,
    bool? enabled,
    Object? attemptMin = _unset,
    Object? attemptMax = _unset,
    Object? timeStart = _unset,
    Object? timeEnd = _unset,
    String? contactFilter,
    String? channel,
    Object? delaySeconds = _unset,
    List<String>? messages,
  }) =>
      Rule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        attemptMin: attemptMin == _unset ? this.attemptMin : attemptMin as int?,
        attemptMax: attemptMax == _unset ? this.attemptMax : attemptMax as int?,
        timeStart: timeStart == _unset ? this.timeStart : timeStart as int?,
        timeEnd: timeEnd == _unset ? this.timeEnd : timeEnd as int?,
        contactFilter: contactFilter ?? this.contactFilter,
        channel: channel ?? this.channel,
        delaySeconds: delaySeconds == _unset ? this.delaySeconds : delaySeconds as int?,
        messages: messages ?? this.messages,
      );

  static const Object _unset = Object();

  /// "1st call", "3rd call onwards", "any call" — the condition in plain English.
  String get attemptLabel {
    if (attemptMin == null && attemptMax == null) return 'Any call';
    if (attemptMin != null && attemptMin == attemptMax) return '${_ordinal(attemptMin!)} call';
    if (attemptMin != null && attemptMax == null) {
      return '${_ordinal(attemptMin!)} call onwards';
    }
    if (attemptMin == null && attemptMax != null) {
      return 'Up to the ${_ordinal(attemptMax!)} call';
    }
    return 'Calls ${attemptMin!}–${attemptMax!}';
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }
}

class LogEntry {
  const LogEntry({
    required this.id,
    required this.display,
    required this.occurredAt,
    required this.state,
    this.e164,
    this.attemptIndex,
    this.cancelReason,
    this.ruleName,
    this.messageCount = 0,
    this.failedCount = 0,
    this.channels,
  });

  final int id;
  final String display;
  final int occurredAt;
  final String state;
  final String? e164;
  final int? attemptIndex;
  final String? cancelReason;
  final String? ruleName;
  final int messageCount;
  final int failedCount;
  final String? channels;

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        id: json['id'] as int,
        display: json['display'] as String? ?? 'Unknown',
        occurredAt: json['occurredAt'] as int,
        state: json['state'] as String? ?? 'scheduled',
        e164: json['e164'] as String?,
        attemptIndex: json['attemptIndex'] as int?,
        cancelReason: json['cancelReason'] as String?,
        ruleName: json['ruleName'] as String?,
        messageCount: json['messageCount'] as int? ?? 0,
        failedCount: json['failedCount'] as int? ?? 0,
        channels: json['channels'] as String?,
      );
}

class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.channel,
    required this.body,
    required this.status,
    required this.scheduledAt,
    this.error,
    this.sentAt,
    this.deliveredAt,
  });

  final int id;
  final String channel;
  final String body;
  final String status;
  final int scheduledAt;
  final String? error;
  final int? sentAt;
  final int? deliveredAt;

  factory OutboxMessage.fromJson(Map<String, dynamic> json) => OutboxMessage(
        id: json['id'] as int,
        channel: json['channel'] as String,
        body: json['body'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        scheduledAt: json['scheduledAt'] as int? ?? 0,
        error: json['error'] as String?,
        sentAt: json['sentAt'] as int?,
        deliveredAt: json['deliveredAt'] as int?,
      );
}

class LogDetail {
  const LogDetail({
    required this.id,
    required this.display,
    required this.prettyNumber,
    required this.occurredAt,
    required this.state,
    required this.messages,
    this.e164,
    this.contactName,
    this.attemptIndex,
    this.cancelReason,
    this.ruleName,
    this.dispatchedAt,
  });

  final int id;
  final String display;
  final String prettyNumber;
  final int occurredAt;
  final String state;
  final List<OutboxMessage> messages;
  final String? e164;
  final String? contactName;
  final int? attemptIndex;
  final String? cancelReason;
  final String? ruleName;
  final int? dispatchedAt;

  factory LogDetail.fromJson(Map<String, dynamic> json) => LogDetail(
        id: json['id'] as int,
        display: json['display'] as String? ?? 'Unknown',
        prettyNumber: json['prettyNumber'] as String? ?? '',
        occurredAt: json['occurredAt'] as int,
        state: json['state'] as String? ?? 'scheduled',
        messages: ((json['messages'] as List?) ?? const [])
            .map((e) => OutboxMessage.fromJson(e))
            .toList(),
        e164: json['e164'] as String?,
        contactName: json['contactName'] as String?,
        attemptIndex: json['attemptIndex'] as int?,
        cancelReason: json['cancelReason'] as String?,
        ruleName: json['ruleName'] as String?,
        dispatchedAt: json['dispatchedAt'] as int?,
      );
}

class ListedNumber {
  const ListedNumber({required this.id, required this.e164, required this.pretty, this.note});

  final int id;
  final String e164;
  final String pretty;
  final String? note;

  factory ListedNumber.fromJson(Map<String, dynamic> json) => ListedNumber(
        id: json['id'] as int,
        e164: json['e164'] as String,
        pretty: json['pretty'] as String? ?? json['e164'] as String,
        note: json['note'] as String?,
      );
}

class SimCard {
  const SimCard({required this.id, required this.label});

  final int id;
  final String label;

  factory SimCard.fromJson(Map<String, dynamic> json) =>
      SimCard(id: json['id'] as int, label: json['label'] as String? ?? 'SIM');
}

class MessageShape {
  const MessageShape({required this.chars, required this.parts, required this.unicode});

  final int chars;
  final int parts;
  final bool unicode;

  factory MessageShape.fromJson(Map<String, dynamic> json) => MessageShape(
        chars: json['chars'] as int? ?? 0,
        parts: json['parts'] as int? ?? 1,
        unicode: json['unicode'] as bool? ?? false,
      );

  /// Turkish letters push a message into UCS-2, which caps a part at 70 characters.
  int get perPart => unicode ? 70 : 160;
}

class PermissionItem {
  const PermissionItem({
    required this.permission,
    required this.label,
    required this.why,
    required this.granted,
  });

  final String permission;
  final String label;
  final String why;
  final bool granted;

  factory PermissionItem.fromJson(Map<String, dynamic> json) => PermissionItem(
        permission: json['permission'] as String,
        label: json['label'] as String? ?? '',
        why: json['why'] as String? ?? '',
        granted: json['granted'] as bool? ?? false,
      );
}

class VendorStep {
  const VendorStep({
    required this.key,
    required this.title,
    required this.detail,
    required this.manualOnly,
  });

  final String key;
  final String title;
  final String detail;
  final bool manualOnly;

  factory VendorStep.fromJson(Map<String, dynamic> json) => VendorStep(
        key: json['key'] as String,
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        manualOnly: json['manualOnly'] as bool? ?? false,
      );
}

class SetupStatus {
  const SetupStatus({
    required this.permissions,
    required this.vendorSteps,
    required this.batteryUnrestricted,
    required this.exactAlarms,
    required this.isXiaomi,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.whatsappInstalled,
    required this.accessibilityEnabled,
    required this.setupComplete,
  });

  final List<PermissionItem> permissions;
  final List<VendorStep> vendorSteps;
  final bool batteryUnrestricted;
  final bool exactAlarms;
  final bool isXiaomi;
  final String manufacturer;
  final String model;
  final String androidVersion;
  final bool whatsappInstalled;
  final bool accessibilityEnabled;
  final bool setupComplete;

  factory SetupStatus.fromJson(Map<String, dynamic> json) => SetupStatus(
        permissions: ((json['permissions'] as List?) ?? const [])
            .map((e) => PermissionItem.fromJson(e))
            .toList(),
        vendorSteps: ((json['vendorSteps'] as List?) ?? const [])
            .map((e) => VendorStep.fromJson(e))
            .toList(),
        batteryUnrestricted: json['batteryUnrestricted'] as bool? ?? false,
        exactAlarms: json['exactAlarms'] as bool? ?? false,
        isXiaomi: json['isXiaomi'] as bool? ?? false,
        manufacturer: json['manufacturer'] as String? ?? '',
        model: json['model'] as String? ?? '',
        androidVersion: json['androidVersion'] as String? ?? '',
        whatsappInstalled: json['whatsappInstalled'] as bool? ?? false,
        accessibilityEnabled: json['accessibilityEnabled'] as bool? ?? false,
        setupComplete: json['setupComplete'] as bool? ?? false,
      );

  bool get allPermissionsGranted => permissions.every((p) => p.granted);
  bool get ready => allPermissionsGranted && batteryUnrestricted && exactAlarms;
}

/// The bridge's own account of itself.
///
/// The app used to infer "linked" from having a token stored locally, which meant the
/// Home screen said "Linked and ready" while the server had been logged out for hours.
/// This is the answer to the only question that matters: can a message go out right now?
class BridgeState {
  const BridgeState({
    required this.linked,
    required this.connected,
    required this.canReconnect,
    this.status,
    this.messagesSent = 0,
    this.lastError,
    this.reachable = true,
  });

  final bool linked;
  final bool connected;
  final bool canReconnect;
  final String? status;
  final int messagesSent;
  final String? lastError;

  /// False when the bridge could not be reached at all — a different problem from
  /// being reachable but disconnected from WhatsApp.
  final bool reachable;

  factory BridgeState.fromJson(Map<String, dynamic> json) => BridgeState(
        linked: json['linked'] as bool? ?? false,
        connected: json['connected'] as bool? ?? false,
        canReconnect: json['canReconnect'] as bool? ?? false,
        status: json['status'] as String?,
        messagesSent: json['messagesSent'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );

  static const BridgeState unreachable = BridgeState(
    linked: false,
    connected: false,
    canReconnect: false,
    reachable: false,
  );

  String get summary {
    if (!reachable) return 'Bridge unreachable';
    if (connected) return 'Linked and ready';
    if (!linked) return 'Not linked yet';
    if (canReconnect) return lastError == null ? 'Disconnected' : 'Disconnected — $lastError';
    return 'Session ended — pair again';
  }
}

class PairingSession {
  const PairingSession({
    required this.sessionId,
    required this.linkUrl,
    required this.expiresAt,
  });

  final String sessionId;
  final String linkUrl;
  final int expiresAt;

  factory PairingSession.fromJson(Map<String, dynamic> json) => PairingSession(
        sessionId: json['sessionId'] as String,
        linkUrl: json['linkUrl'] as String,
        expiresAt: json['expiresAt'] as int? ?? 0,
      );
}
