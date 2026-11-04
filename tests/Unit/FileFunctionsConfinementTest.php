<?php

/**
 * File.Move / File.Copy are exported in the JS bridge, so a web view page can
 * call them through /_native/api/call (the api routes carry no middleware).
 * Left open that is a file-exfil primitive (copy a secret into public/, read it
 * back at /_assets/…) and a clobber/DoS primitive. The fix confines paths in the
 * native implementations, which no PHP test can execute — these assert the Swift
 * and Kotlin twins keep the guard, so one platform can't regress without the
 * other.
 */
function fileFunctionsSource(string $path): string
{
    return file_get_contents(dirname(__DIR__, 2).'/resources/'.$path);
}

$ios = 'ios/FileFunctions.swift';
$android = 'android/FileFunctions.kt';

it('confines both Move and Copy before the file operation on both platforms', function (string $path, string $callMarker, array $ops) {
    $source = fileFunctionsSource($path);

    // The confinement runs in each of Move and Copy.
    expect(substr_count($source, $callMarker))->toBe(2);

    // And it runs before the file is touched, in both.
    foreach ($ops as $op) {
        $guardAt = strpos($source, $callMarker);
        $opAt = strpos($source, $op);
        expect($guardAt)->toBeLessThan($opAt, "{$op} runs before the confinement guard");
    }
})->with([
    'iOS' => [$ios, 'confinementError(from: from, to: to)', ['moveItem', 'copyItem']],
    'Android' => [$android, 'confinementError(activity.applicationContext, from, to)', ['renameTo', 'copyTo']],
]);

it('canonicalises paths before checking them, so .. and symlinks cannot escape', function (string $path, string $needle) {
    expect(fileFunctionsSource($path))->toContain($needle);
})->with([
    'iOS resolves symlinks' => [$ios, 'resolvingSymlinksInPath()'],
    'Android resolves via canonicalPath' => [$android, 'canonicalPath'],
]);

it('confines the destination to the allowed trees on both platforms', function (string $path) {
    expect(fileFunctionsSource($path))->toContain('destinationRoots');
})->with([
    'iOS' => [$ios],
    'Android' => [$android],
]);

it('anchors the storage root to the real storage_path, not the ephemeral app extract', function (string $path, string $needle) {
    // storage_path() on both platforms points outside the swappable app tree
    // (iOS: Application Support via LARAVEL_STORAGE_PATH; Android:
    // persisted_data/storage). Anchoring the destination root anywhere under the
    // extracted app would both reject legitimate storage_path() moves and write
    // to storage that an update wipes. Pin the real source of truth.
    expect(fileFunctionsSource($path))->toContain($needle);
})->with([
    'iOS reads LARAVEL_STORAGE_PATH' => [$ios, 'getenv("LARAVEL_STORAGE_PATH")'],
    'Android uses LARAVEL_STORAGE_PATH' => [$android, 'LARAVEL_STORAGE_PATH'],
    'Android mirrors persisted_data/storage' => [$android, 'persisted_data/storage'],
]);

it('denies the sensitive sinks that sit inside an allowed tree', function (string $path, array $needles) {
    $source = fileFunctionsSource($path);
    foreach ($needles as $needle) {
        expect($source)->toContain($needle);
    }
})->with([
    // iOS allows the whole Documents dir, which contains the app extract
    // (public/, .env, the DB, bootstrap/cache) — so the extract is denied as a
    // whole, plus storage framework/logs.
    'iOS denies the extract and storage internals' => [$ios, ['extractRoot', 'deniedRoots', '/framework', '/logs']],
    // Android's extract lives under …/laravel, outside the storage tree, so only
    // framework/logs need an explicit deny inside the allowed tree.
    'Android denies storage internals' => [$android, ['deniedRoots', '/framework', '/logs']],
]);

it('refuses a destination whose leaf is a symlink, on both platforms', function (string $path, string $needle) {
    // canonical() resolves the parent but, for a dangling-symlink destination,
    // keeps the in-root leaf name — the copy/move would then follow the link out
    // of the allowed tree. Each twin refuses a symlink leaf (iOS lstats via
    // attributesOfItem; Android compares the leaf's canonical and absolute paths).
    expect(fileFunctionsSource($path))->toContain($needle);
})->with([
    'iOS lstats the dest leaf' => [$ios, 'typeSymbolicLink'],
    'Android checks the dest leaf link' => [$android, 'leaf.canonicalPath != leaf.absolutePath'],
]);
