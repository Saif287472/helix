// Generates a text dependency graph for the workspace.
// P4-014: Dependency graph artifact for CI.
//
// Usage:  dart run tool/dep_graph.dart [--dot]
//   default: prints a human-readable list
//   --dot:   prints a Graphviz DOT file (pipe to `dot -Tsvg` to render)
//
// The graph covers workspace packages only; external pub dependencies are omitted.

import 'dart:io';

// Maps package names to their workspace-relative source roots.
// Keep in sync with tool/check_boundaries.dart _workspacePackageRoots.
const _nodes = <String, String>{
  'helix': 'apps/helix_local/lib/',
  'helix_remote': 'apps/helix_remote/lib/',
  'helix_local_domain': 'packages/local/helix_local_domain/lib/',
  'helix_local_protocol': 'packages/local/helix_local_protocol/lib/',
  'helix_local_crypto': 'packages/local/helix_local_crypto/lib/',
  'helix_local_transport': 'packages/local/helix_local_transport/lib/',
  'helix_local_storage': 'packages/local/helix_local_storage/lib/',
  'helix_local_platform': 'packages/local/helix_local_platform/lib/',
  'helix_local_calls': 'packages/local/helix_local_calls/lib/',
  'helix_local_messaging': 'packages/local/helix_local_messaging/lib/',
  'helix_local_transfer': 'packages/local/helix_local_transfer/lib/',
  'helix_local_groups': 'packages/local/helix_local_groups/lib/',
  'helix_local_discovery': 'packages/local/helix_local_discovery/lib/',
  'helix_remote_domain': 'packages/remote/helix_remote_domain/lib/',
  'helix_remote_api': 'packages/remote/helix_remote_api/lib/',
  'helix_remote_crypto': 'packages/remote/helix_remote_crypto/lib/',
};

Future<void> main(List<String> args) async {
  final dotMode = args.contains('--dot');
  final root = Directory.current;
  final edges = await buildEdges(root);

  if (dotMode) {
    _printDot(edges);
  } else {
    _printText(edges);
  }
}

/// Detects cycles in the workspace dependency graph.
/// Returns a list of cycle descriptions, empty if the graph is acyclic.
Future<List<String>> detectCycles(Directory root) async {
  final edges = await buildEdges(root);
  final cycles = <String>[];
  final visited = <String>{};
  final stack = <String>[];

  void dfs(String node) {
    if (stack.contains(node)) {
      final cycleStart = stack.indexOf(node);
      cycles.add((stack.sublist(cycleStart)..add(node)).join(' -> '));
      return;
    }
    if (visited.contains(node)) return;
    visited.add(node);
    stack.add(node);
    for (final dep in edges[node] ?? <String>{}) {
      dfs(dep);
    }
    stack.removeLast();
  }

  for (final node in edges.keys) {
    dfs(node);
  }
  return cycles;
}

Future<Map<String, Set<String>>> buildEdges(Directory root) async {
  final edges = <String, Set<String>>{
    for (final k in _nodes.keys) k: <String>{},
  };

  final importRe = RegExp(r'''import\s+['"]package:([a-z_]+)/''');

  for (final entry in _nodes.entries) {
    final pkg = entry.key;
    final libDir = Directory('${root.path}/${entry.value}');
    if (!libDir.existsSync()) continue;

    await for (final entity in libDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = await entity.readAsString();
      for (final match in importRe.allMatches(content)) {
        final dep = match.group(1)!;
        if (_nodes.containsKey(dep) && dep != pkg) {
          edges[pkg]!.add(dep);
        }
      }
    }
  }

  return edges;
}

void _printText(Map<String, Set<String>> edges) {
  stdout.writeln('Workspace dependency graph\n');
  final sortedEntries = edges.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in sortedEntries) {
    final deps = entry.value.toList()..sort();
    if (deps.isEmpty) {
      stdout.writeln('  ${entry.key}  (no workspace deps)');
    } else {
      for (final dep in deps) {
        stdout.writeln('  ${entry.key} -> $dep');
      }
    }
  }
}

void _printDot(Map<String, Set<String>> edges) {
  stdout.writeln('digraph helix_workspace {');
  stdout.writeln('  rankdir=LR;');
  stdout.writeln('  node [shape=box, fontname="monospace"];');
  for (final entry in edges.entries) {
    for (final dep in entry.value) {
      stdout.writeln('  "${entry.key}" -> "$dep";');
    }
  }
  stdout.writeln('}');
}
