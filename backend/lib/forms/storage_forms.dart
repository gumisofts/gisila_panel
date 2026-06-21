import 'package:gisila/gisila.dart';

/// `POST /storage/providers/minio` — install the self-hosted MinIO server.
class InstallMinioForm extends Form {
  final displayName =
      StringField(name: 'displayName', required: true, maxLength: 128);
  final port = IntField(name: 'port');
  final consolePort = IntField(name: 'consolePort');
  // Optional public base URL for reads (nginx-fronted MinIO or a CDN).
  final publicUrl = StringField(name: 'publicUrl', maxLength: 255);

  @override
  List<FormField<Object?>> collectFields() =>
      [displayName, port, consolePort, publicUrl];
}

/// `POST /storage/providers/external` — register an external S3 endpoint.
class AddConnectorForm extends Form {
  final displayName =
      StringField(name: 'displayName', required: true, maxLength: 128);
  final endpoint = StringField(name: 'endpoint', required: true, maxLength: 255);
  final region = StringField(name: 'region', maxLength: 64);
  final accessKey = StringField(name: 'accessKey', required: true, maxLength: 255);
  final secretKey = StringField(name: 'secretKey', required: true, maxLength: 255);
  final publicUrl = StringField(name: 'publicUrl', maxLength: 255);
  final forcePathStyle = BoolField(name: 'forcePathStyle');

  @override
  List<FormField<Object?>> collectFields() => [
        displayName,
        endpoint,
        region,
        accessKey,
        secretKey,
        publicUrl,
        forcePathStyle,
      ];
}

/// `POST /storage/providers/{id}/expose` — set/clear the public URL (and, for
/// MinIO, the nginx reverse-proxy that serves it).
class ExposeProviderForm extends Form {
  // Empty string clears the public URL (and removes the MinIO vhost).
  final publicUrl = StringField(name: 'publicUrl', maxLength: 255);

  @override
  List<FormField<Object?>> collectFields() => [publicUrl];
}

/// `POST /storage/providers/{id}/buckets` — create a bucket + scoped key.
class CreateBucketForm extends Form {
  final bucketName =
      StringField(name: 'bucketName', required: true, maxLength: 63);
  final isPublic = BoolField(name: 'isPublic');

  @override
  List<FormField<Object?>> collectFields() => [bucketName, isPublic];
}

/// `POST /storage/apps/{appId}/links` — link a bucket to an app (auto-injects
/// credentials as env vars).
class LinkBucketForm extends Form {
  final bucketId = IntField(name: 'bucketId', required: true);
  final envPrefix = StringField(name: 'envPrefix', maxLength: 32);

  @override
  List<FormField<Object?>> collectFields() => [bucketId, envPrefix];
}
