/// A text/icon description for one row of Design §4's state presentation
/// catalogue — deliberately framework-agnostic (no `IconData`, no
/// `BuildContext`) so `lib/core/presentation/**` stays testable without
/// Flutter widgets and colour stays the theme layer's job (Design §3.2's
/// token table), not this one's. [iconId] is a stable semantic key a
/// screen's icon-mapping table resolves to a concrete glyph/asset; it is
/// never itself a rendered value.
///
/// Design §4: "every state also needs text or an icon" (redundant with
/// colour, never colour alone) — this type is how that requirement is
/// represented at the projection boundary.
class PresentationCue {
  const PresentationCue({required this.label, required this.iconId});

  /// Plain-language label matching Design §4/§5's copy exactly (e.g.
  /// "Hold to talk", "Channel busy") — never a raw exception or internal
  /// service name (Design §5).
  final String label;

  /// Stable semantic icon identifier (e.g. `'mic'`, `'wifi_off'`) — a
  /// screen resolves this to its own icon family (Design §3.4); it is not
  /// a `String` the projection expects to be displayed verbatim.
  final String iconId;

  @override
  bool operator ==(Object other) =>
      other is PresentationCue && other.label == label && other.iconId == iconId;

  @override
  int get hashCode => Object.hash(label, iconId);

  @override
  String toString() => 'PresentationCue($label, icon: $iconId)';
}
