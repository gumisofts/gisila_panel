import 'package:gisila_agent/services/mongo_express.dart';

/// Modular managed-service handler.
///
/// This is the *seam* that makes adding a host service easy: implement a
/// [ServiceHandler], register it in [kServiceHandlers], and add a matching
/// `ServiceDef` to the backend catalog. The agent's `_service*` dispatchers
/// consult [findServiceHandler] first and fall back to the legacy inline code
/// for services not yet migrated to this registry.
abstract class ServiceHandler {
  /// Stable service type, e.g. 'mongo-express'. Matches `ManagedService.serviceType`.
  String get type;

  /// systemd unit name used for start/stop/restart (defaults to `gisila-<type>`).
  String get unitName => 'gisila-$type';

  Future<void> install(Map<String, dynamic> config);
  Future<void> configure(Map<String, dynamic> config);
  Future<void> uninstall();
}

/// Registry of registry-based service handlers, keyed by service type.
final Map<String, ServiceHandler> kServiceHandlers = {
  for (final h in <ServiceHandler>[
    MongoExpressHandler(),
  ])
    h.type: h,
};

ServiceHandler? findServiceHandler(String type) => kServiceHandlers[type];
