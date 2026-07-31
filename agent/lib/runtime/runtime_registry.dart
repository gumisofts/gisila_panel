import 'package:gisila_agent/runtime/runtime_plugin.dart';
import 'package:gisila_agent/runtimes/binary_plugin.dart';
import 'package:gisila_agent/runtimes/bun_plugin.dart';
import 'package:gisila_agent/runtimes/celery_plugin.dart';
import 'package:gisila_agent/runtimes/dart_plugin.dart';
import 'package:gisila_agent/runtimes/go_plugin.dart';
import 'package:gisila_agent/runtimes/node_plugin.dart';
import 'package:gisila_agent/runtimes/python_plugin.dart';
import 'package:gisila_agent/runtimes/rust_plugin.dart';
import 'package:gisila_agent/runtimes/static_plugin.dart';
import 'package:gisila_agent/runtimes/zig_plugin.dart';

/// `key -> RuntimePlugin` lookup, replacing the hand-written
/// `switch (runtime)` blocks that used to live in `gisila-agent.dart`.
///
/// This is the single place a brand-new runtime plugin gets wired in; every
/// call site (build dispatch, toolchain install/remove, validation) reads
/// from this registry instead of enumerating runtimes itself.
class RuntimeRegistry {
  RuntimeRegistry._();

  static final Map<String, RuntimePlugin> _plugins = {
    for (final p in <RuntimePlugin>[
      DartPlugin(),
      GoPlugin(),
      RustPlugin(),
      ZigPlugin(),
      BunPlugin(),
      NodePlugin(),
      PythonPlugin(),
      CeleryPlugin(),
      StaticPlugin(),
      BinaryPlugin(),
    ])
      p.key: p,
  };

  static bool has(String key) => _plugins.containsKey(key);

  static RuntimePlugin get(String key) {
    final plugin = _plugins[key];
    if (plugin == null) {
      throw ArgumentError('Unknown runtime/Application key: $key');
    }
    return plugin;
  }

  static Iterable<String> get keys => _plugins.keys;

  static Iterable<RuntimePlugin> get all => _plugins.values;
}
