import 'dart:convert';
import 'dart:io';

/// A tiny wrapper around `Process.run` that streams stdout/stderr line-by-line
/// to the caller and aborts on non-zero exit codes.
class ShellExec {
  static Future<int> run(
    String executable,
    List<String> args, {
    String? cwd,
    Map<String, String>? env,
    bool requireSuccess = true,
    String? logPrefix,
  }) async {
    final prefix = logPrefix ?? '$executable ${args.join(' ')}';
    stdout.writeln('[agent] $prefix');
    final process = await Process.start(
      executable,
      args,
      workingDirectory: cwd,
      environment: env,
      runInShell: false,
    );

    await Future.wait<void>([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => stdout.writeln(line)),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => stderr.writeln(line)),
    ]);

    final exit = await process.exitCode;
    if (requireSuccess && exit != 0) {
      throw ProcessException(executable, args, 'exited with $exit', exit);
    }
    return exit;
  }
}
