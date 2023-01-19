import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:args/args.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:http/http.dart';
import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';

late final ArgResults argResults;
Uri get host => Uri.parse(argResults['host']);

Future<void> main(List<String> args) async {
  final parser = ArgParser(
      usageLineLength: stdout.hasTerminal ? stdout.terminalLines : 80)
    ..addFlag('help', abbr: 'h', help: 'Display this usage information')
    ..addFlag('dev', defaultsTo: true, help: 'Include dev_dependencies')
    ..addFlag('transitive', help: 'Include transitive dependencies')
    ..addFlag('releases', help: 'Count the number of releases after current')
    ..addFlag('versions', help: 'Calculate the semver-delta')
    ..addOption(
      'host',
      defaultsTo: 'https://pub.dev',
      help: 'Use this host as pub.dev',
      hide: true,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show the age of each dependency, and other details.',
    );
  argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    exit(-1);
  }
  final pubspecLock = File('pubspec.lock');
  final pubspecYaml = File('pubspec.yaml');

  if (!pubspecLock.existsSync()) {
    if (pubspecYaml.existsSync()) {
      print('Found no pubspec.lock - run `dart pub get` / `flutter pub get`');
    } else {
      print('Found no pubspec.yaml - run in the root of a dart project.');
    }
  }

  final deps = loadYaml(pubspecLock.readAsStringSync());
  final packages = deps['packages'] as Map;

  var sum = Diffs.zero();
  for (final package in packages.entries) {
    if (package.value['source'] != 'hosted' ||
        Uri.parse(package.value['description']['url']) != host) {
      if (argResults['verbose']) {
        print('Package ${package.key} is not hosted at ${host} - skipping');
      }
      continue;
    }
    if (package.value['dependency'] == 'transitive' &&
        !argResults['transitive']) {
      continue;
    }
    if (package.value['dependency'] == 'direct dev' && !argResults['dev']) {
      continue;
    }
    sum += await age(package.key, Version.parse(package.value['version']));
  }

  print('Release age: ${sum.releaseCount}');
  print('Semver delta age: ${sum.versionDelta}');
  print('libdir age: ${formatAge(sum.duration)}');
}

String formatAge(Duration age) {
  return '${age.inDays ~/ 365} year(s) ${age.inDays % 365} day(s)';
}

Future<Diffs> age(String packageName, Version currentVersion) async {
  final listing =
      jsonDecode((await get(host.resolve('/api/packages/$packageName'))).body)[
          'versions'] as List;
  final current = listing.firstWhere(
      (version) => Version.parse(version['version']) == currentVersion,
      orElse: () {
    print('Could not find ${packageName} v$currentVersion on ${host}');
    exit(-1);
  });
  listing.sort((a, b) {
    final va = Version.parse(a['version']);
    final vb = Version.parse(b['version']);
    return va.compareTo(vb);
  });

  final noPrereleases =
      listing.where((a) => !Version.parse(a['version']).isPreRelease).toList();

  final relevantListing = currentVersion.isPreRelease
      ? listing
      : noPrereleases.isNotEmpty
          ? noPrereleases
          : listing;

  final latest = relevantListing.last;

  final currentIndex = relevantListing.indexWhere(
      (version) => Version.parse(version['version']) == currentVersion);

  final Version versionDelta = delta(
    currentVersion,
    Version.parse(latest['version']),
  );
  final int relasesSince = relevantListing.length - 1 - currentIndex;

  final dateDiff = DateTime.parse(latest['published'])
      .difference(DateTime.parse(current['published']));

  if (argResults['verbose']) {
    print(packageName);
    print('  latest: ${latest['version']} published: ${latest['published']}');
    print(
        '  current: ${current['version']} published: ${current['published']}');
    print('  age: ${formatAge(dateDiff)}');
    print('  newer releases: $relasesSince');
    print('  version delta: $versionDelta');
  }
  return Diffs(versionDelta,
      dateDiff > Duration.zero ? dateDiff : Duration.zero, relasesSince);
}

Version delta(Version a, Version b) {
  if (a.major != b.major) {
    return Version((a.major - b.major).abs(), 0, 0);
  }
  if (a.minor != b.minor) {
    return Version(0, (a.minor - b.minor).abs(), 0);
  }
  return Version(0, 0, (a.patch - b.patch).abs());
}

class Diffs {
  final Version versionDelta;
  final Duration duration;
  final int releaseCount;
  Diffs(this.versionDelta, this.duration, this.releaseCount);
  static Diffs zero() => Diffs(Version(0, 0, 0), Duration.zero, 0);

  Diffs operator +(Diffs other) => Diffs(
        Version(
          versionDelta.major + other.versionDelta.major,
          versionDelta.minor + other.versionDelta.minor,
          versionDelta.patch + other.versionDelta.patch,
        ),
        duration + other.duration,
        releaseCount + other.releaseCount,
      );
}
