import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/directory/directory_client.dart';

/// Contract test (this task's own criterion): every path
/// [DirectoryClient.calledPaths] lists must exist as a `paths:` key in
/// `token-svc/openapi-v2.yaml` — TASK-084/085's contract. Loaded as plain
/// text and matched with a light-weight line scan rather than a full YAML
/// parser (no YAML package dependency exists in this repo; the file's
/// `paths:` block is machine-generated and consistently two-space indented
/// path keys, so this is a faithful, low-risk check of exactly what this
/// criterion asks for: "every path this client calls exists in it").
void main() {
  test('every DirectoryClient path exists in openapi-v2.yaml', () {
    final file = File('token-svc/openapi-v2.yaml');
    expect(file.existsSync(), isTrue, reason: 'openapi-v2.yaml must exist at the repo root token-svc/');
    final lines = file.readAsLinesSync();

    // Path keys look like:  "  /v2/groups/{id}:" or "  /token:" — two-space
    // indented, ending in a colon, starting with '/'.
    final specPaths = <String>{
      for (final line in lines)
        if (RegExp(r'^  (/\S+):$').firstMatch(line) != null)
          RegExp(r'^  (/\S+):$').firstMatch(line)!.group(1)!,
    };
    expect(specPaths, isNotEmpty, reason: 'failed to parse any path key out of openapi-v2.yaml');

    for (final calledPath in DirectoryClient.calledPaths) {
      // This client's :action-suffixed paths (e.g. .../{from_pk}:accept)
      // are themselves distinct path keys in the spec (each :verb gets its
      // own top-level path entry), so a direct membership check is correct
      // — no normalisation needed.
      expect(
        specPaths.contains(calledPath),
        isTrue,
        reason: '$calledPath (called by DirectoryClient) is missing from openapi-v2.yaml\'s paths',
      );
    }
  });
}
