/// Build stamp, injected at compile time by `infra/build-defines.sh`
/// (`dart compile exe --define=GISILA_VERSION=…`). A build without the defines
/// — `dart run` in development — reports "dev".
const gisilaVersion =
    String.fromEnvironment('GISILA_VERSION', defaultValue: 'dev');

/// Short git commit the binary was built from, or empty when unknown.
const gisilaCommit = String.fromEnvironment('GISILA_COMMIT');

/// UTC ISO-8601 build time, or empty when unknown.
const gisilaBuiltAt = String.fromEnvironment('GISILA_BUILT_AT');
