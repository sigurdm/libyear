import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';
import 'package:test_descriptor/test_descriptor.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'package_server.dart';

void main() {
  test('Calculates correct distance', () async {
    final server = await PackageServer.start();
    addTearDown(() => server.close());

    desc(String name, String version, {String dependency = 'direct main'}) => {
          name: {
            'dependency': dependency,
            'source': 'hosted',
            'description': {'url': server.url},
            'version': version,
          }
        };

    await file(
      'pubspec.lock',
      jsonEncode(
        {
          'packages': {
            ...desc('args', '2.3.1'),
            ...desc('crypto', '3.0.2', dependency: 'transitive'),
            ...desc('file', '6.1.4', dependency: 'transitive'),
            ...desc('retry', '1.0.0-dev', dependency: 'direct dev'),
            ...desc('foo', '1.0.0', dependency: 'direct dev')
          }
        },
      ),
    ).create();

    server.serve('args', '2.3.0', published: DateTime(2021, 1, 1));
    server.serve('args', '2.3.1', published: DateTime(2023, 1, 1));
    server.serve('args', '2.3.2', published: DateTime(2023, 2, 1));
    server.serve('args', '3.0.0-dev', published: DateTime(2023, 2, 1));

    server.serve('crypto', '3.0.2', published: DateTime(2023, 1, 1));
    server.serve('crypto', '3.1.2', published: DateTime(2024, 1, 1));

    server.serve('file', '6.1.3', published: DateTime(2023, 1, 1));
    server.serve('file', '6.1.4', published: DateTime(2023, 1, 1));
    server.serve('file', '6.1.5', published: DateTime(2023, 1, 1));

    server.serve('retry', '1.0.0-dev', published: DateTime(2023, 1, 2));
    server.serve('retry', '1.0.0', published: DateTime(2023, 1, 2));
    server.serve('retry', '2.0.0-dev', published: DateTime(2023, 1, 7));

    server.serve('foo', '0.0.1', published: DateTime(2021, 1, 1));
    server.serve('foo', '1.0.0', published: DateTime(2023, 1, 1));

    Future<void> run(List<String> args, {required dynamic output}) async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          p.absolute('bin', 'libyear.dart'),
          '--host',
          server.url,
          ...args,
        ],
        workingDirectory: sandbox,
      );

      expect(result.stderr, '');
      expect(result.stdout, output);
      expect(result.exitCode, 0);
    }

    await run(
      ['--verbose'],
      output: 'args\n'
          '  latest: 2.3.2 published: 2023-02-01 00:00:00.000\n'
          '  current: 2.3.1 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 31 day(s)\n'
          '  newer releases: 1\n'
          '  version delta: 0.0.1\n'
          'retry\n'
          '  latest: 2.0.0-dev published: 2023-01-07 00:00:00.000\n'
          '  current: 1.0.0-dev published: 2023-01-02 00:00:00.000\n'
          '  age: 0 year(s) 5 day(s)\n'
          '  newer releases: 2\n'
          '  version delta: 1.0.0\n'
          'foo\n'
          '  latest: 1.0.0 published: 2023-01-01 00:00:00.000\n'
          '  current: 1.0.0 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 0 day(s)\n'
          '  newer releases: 0\n'
          '  version delta: 0.0.0\n'
          'Release age: 3\n'
          'Semver delta age: 1.0.1\n'
          'libdir age: 0 year(s) 36 day(s)\n'
          '',
    );
    await run(
      ['--transitive', '--verbose'],
      output: 'args\n'
          '  latest: 2.3.2 published: 2023-02-01 00:00:00.000\n'
          '  current: 2.3.1 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 31 day(s)\n'
          '  newer releases: 1\n'
          '  version delta: 0.0.1\n'
          'crypto\n'
          '  latest: 3.1.2 published: 2024-01-01 00:00:00.000\n'
          '  current: 3.0.2 published: 2023-01-01 00:00:00.000\n'
          '  age: 1 year(s) 0 day(s)\n'
          '  newer releases: 1\n'
          '  version delta: 0.1.0\n'
          'file\n'
          '  latest: 6.1.5 published: 2023-01-01 00:00:00.000\n'
          '  current: 6.1.4 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 0 day(s)\n'
          '  newer releases: 1\n'
          '  version delta: 0.0.1\n'
          'retry\n'
          '  latest: 2.0.0-dev published: 2023-01-07 00:00:00.000\n'
          '  current: 1.0.0-dev published: 2023-01-02 00:00:00.000\n'
          '  age: 0 year(s) 5 day(s)\n'
          '  newer releases: 2\n'
          '  version delta: 1.0.0\n'
          'foo\n'
          '  latest: 1.0.0 published: 2023-01-01 00:00:00.000\n'
          '  current: 1.0.0 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 0 day(s)\n'
          '  newer releases: 0\n'
          '  version delta: 0.0.0\n'
          'Release age: 5\n'
          'Semver delta age: 1.1.2\n'
          'libdir age: 1 year(s) 36 day(s)\n'
          '',
    );
    await run(
      ['--no-dev', '--verbose'],
      output: 'args\n'
          '  latest: 2.3.2 published: 2023-02-01 00:00:00.000\n'
          '  current: 2.3.1 published: 2023-01-01 00:00:00.000\n'
          '  age: 0 year(s) 31 day(s)\n'
          '  newer releases: 1\n'
          '  version delta: 0.0.1\n'
          'Release age: 1\n'
          'Semver delta age: 0.0.1\n'
          'libdir age: 0 year(s) 31 day(s)\n'
          '',
    );
  });
}
