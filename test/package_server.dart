// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Serves the relevant subset of package listings
class PackageServer {
  /// The inner [DescriptorServer] that this uses to serve its descriptors.
  final shelf.Server _inner;

  PackageServer._(this._inner) {
    _inner.mount((request) {
      final path = request.url.path;

      final pathWithInitialSlash = '/$path';
      final match = _versionInfoPattern.matchAsPrefix(pathWithInitialSlash);
      if (match != null && match.end == pathWithInitialSlash.length) {
        final parts = request.url.pathSegments;
        assert(parts[0] == 'api');
        assert(parts[1] == 'packages');
        final name = parts[2];

        final package = _packages[name];
        if (package == null) {
          return shelf.Response.notFound('No package named $name');
        }
        return shelf.Response.ok(jsonEncode({
          'name': name,
          'uploaders': ['foo@pub.dev'],
          'versions': package.versions.values
              .map((version) => packageVersionApiMap(
                  _inner.url.toString(),
                  {'name': name, 'version': version.version.toString()},
                  version.published))
              .toList(),
        }));
      }

      return shelf.Response.notFound('Could not find ${request.url}');
    });
  }

  static final _versionInfoPattern = RegExp(r'/api/packages/([a-zA-Z_0-9]*)');

  static Future<PackageServer> start() async {
    return PackageServer._(await shelf_io.IOServer.bind('localhost', 0));
  }

  Future<void> close() async {
    await _inner.close();
  }

  /// The URL for the server.
  String get url => _inner.url.toString();

  /// A map from package names to the concrete packages to serve.
  final _packages = <String, _ServedPackage>{};

  /// Specifies that a package named [name] with [version] should be served.
  ///
  /// If [deps] is passed, it's used as the "dependencies" field of the pubspec.
  /// If [pubspec] is passed, it's used as the rest of the pubspec.
  ///
  /// If [contents] is passed, it's used as the contents of the package. By
  /// default, a package just contains a dummy lib directory.
  void serve(
    String name,
    String version, {
    required DateTime published,
  }) {
    var package = _packages.putIfAbsent(name, () => _ServedPackage());
    package.versions[version] =
        _ServedPackageVersion(Version.parse(version), published);
  }
}

class _ServedPackage {
  final versions = <String, _ServedPackageVersion>{};
}

/// A package that's intended to be served.
class _ServedPackageVersion {
  final Version version;
  final DateTime published;

  _ServedPackageVersion(this.version, this.published);
}

/// Returns a Map in the format used by the pub.dartlang.org API to represent a
/// package version.
///
/// [pubspec] is the parsed pubspec of the package version. If [full] is true,
/// this returns the complete map, including metadata that's only included when
/// requesting the package version directly.
Map packageVersionApiMap(String hostedUrl, Map pubspec, DateTime published) {
  var name = pubspec['name'];
  var version = pubspec['version'];
  var map = {
    'pubspec': pubspec,
    'version': version,
    'published': published.toString(),
    'archive_url': '$hostedUrl/packages/$name/versions/$version.tar.gz',
  };

  return map;
}
