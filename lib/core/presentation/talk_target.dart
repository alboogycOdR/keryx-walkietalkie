/// v2 (Technical §6.3/§6.4, TASK-088 additive scope): the currently selected
/// talk destination — a contact or a group — as seen by the presentation
/// layer. Deliberately minimal: this type carries only what
/// [RadioViewState]/`RadioSessionController.switchTarget` need (identity,
/// display name, room, and member roster for the join-guard/audience
/// computation). It does not import `lib/core/contacts/**` or
/// `lib/core/groups/**` (TASK-086, a different task's `Owned_Paths`) —
/// whichever host composes a live [TalkTarget] from those stores is a later
/// task's job (Technical §10 items 7-9, depends on this one).
enum TalkTargetKind { contact, group }

class TalkTarget {
  const TalkTarget({
    required this.kind,
    required this.id,
    required this.name,
    required this.roomId,
    this.memberPeerIds = const [],
  });

  /// Contact or group.
  final TalkTargetKind kind;

  /// Directory-assigned identifier (a contact's peerId, or a group's uuid).
  final String id;

  /// Display name — a contact's callsign, or a group's name.
  final String name;

  /// v2 room ID (`deriveDirectRoom`/`deriveGroupRoom`, TASK-087) this target
  /// resolves to. `RadioSessionController.switchTarget` joins this room
  /// directly; it is never derived from a numbered channel/code.
  final String roomId;

  /// Every member's peerId except the local device — used both for the
  /// solo join-guard (`FloorEngine.updateRoster`, Technical §1.1) and for
  /// [AudienceState.compute]. Empty for a still-loading or solo target.
  final List<String> memberPeerIds;

  @override
  bool operator ==(Object other) =>
      other is TalkTarget &&
      other.kind == kind &&
      other.id == id &&
      other.name == name &&
      other.roomId == roomId &&
      _listEquals(other.memberPeerIds, memberPeerIds);

  @override
  int get hashCode =>
      Object.hash(kind, id, name, roomId, Object.hashAll(memberPeerIds));

  @override
  String toString() =>
      'TalkTarget(kind: $kind, id: $id, name: $name, roomId: $roomId, '
      'memberPeerIds: $memberPeerIds)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// v2 (Technical §4.3): a peer's presence as known from the directory's
/// presence WebSocket (TASK-086). Mirrored here, minimally, rather than
/// importing `lib/core/contacts/**`'s own presence type — see this file's
/// dartdoc for why.
enum PeerPresence { online, offline, dnd, busy }

/// v2 (Technical §6.3): "who can actually hear a transmission on the
/// currently selected [TalkTarget], and why not if nobody can" —
/// UX-FR-041's ready-ring rule reads this directly.
class AudienceState {
  const AudienceState({required this.canHear, this.reason});

  /// Count of currently-reachable (`PeerPresence.online`) members. `0` means
  /// nobody would hear a transmission right now.
  final int canHear;

  /// Human-facing reason shown on the status line when [canHear] is `0`.
  /// `null` whenever [canHear] > 0.
  final String? reason;

  /// v1-safe default used whenever no v2 [TalkTarget] is selected — every
  /// existing v1 projection keeps behaving as if audience were always
  /// non-empty (TASK-088 re-scope note).
  static const everyoneReachable = AudienceState(canHear: 1, reason: null);

  /// Empty-roster case (V2-FR-044/V2-VT-021): a target with no other members
  /// yet resolved always reads "Nobody is listening", independent of the
  /// presence matrix below.
  static const nobodyListening = AudienceState(
    canHear: 0,
    reason: 'Nobody is listening',
  );

  /// V2-VT-022: the {online, offline, DND, busy} × {contact, group} matrix.
  /// Only `PeerPresence.online` members count as reachable; `busy`/`dnd`/
  /// `offline` members do not, but the specific wording differs so the
  /// status line stays honest about *why* (Design §4).
  factory AudienceState.compute({
    required TalkTarget? target,
    required Map<String, PeerPresence> presenceByPeerId,
  }) {
    if (target == null) return everyoneReachable;
    final members = target.memberPeerIds;
    if (members.isEmpty) return nobodyListening;

    final statuses = members
        .map((id) => presenceByPeerId[id] ?? PeerPresence.offline)
        .toList(growable: false);
    final online = statuses.where((s) => s == PeerPresence.online).length;
    if (online > 0) return AudienceState(canHear: online, reason: null);

    final allOffline = statuses.every((s) => s == PeerPresence.offline);
    final allDnd = statuses.every((s) => s == PeerPresence.dnd);
    final allBusy = statuses.every((s) => s == PeerPresence.busy);
    final isContact = target.kind == TalkTargetKind.contact;

    final String reason;
    if (allOffline) {
      reason = isContact ? '${target.name} is offline' : 'Nobody is listening';
    } else if (allDnd) {
      reason = isContact
          ? '${target.name} has Do Not Disturb on'
          : 'Everyone has Do Not Disturb on';
    } else if (allBusy) {
      reason = isContact ? '${target.name} is busy' : 'Everyone is busy';
    } else {
      // Mixed offline/DND/busy with zero online — a generic but honest
      // fallback rather than picking one member's status arbitrarily.
      reason = 'Nobody is listening';
    }
    return AudienceState(canHear: 0, reason: reason);
  }

  @override
  bool operator ==(Object other) =>
      other is AudienceState && other.canHear == canHear && other.reason == reason;

  @override
  int get hashCode => Object.hash(canHear, reason);

  @override
  String toString() => 'AudienceState(canHear: $canHear, reason: $reason)';
}
