<?php
// rewrite-config.php <source config.php> <output config.php> <overrides.json>
// Produces a config.php for the new add-on from an existing instance's config.php.
// Preserves instanceid, passwordsalt, secret (required for encryption, tokens, 2FA), version, app settings.
// Drops keys that point at paths/services specific to the old container. Prints dropped keys to stdout.
if ($argc !== 4) { fwrite(STDERR, "usage: rewrite-config.php SRC OUT OVERRIDES.json\n"); exit(2); }
include $argv[1];
if (!isset($CONFIG) || !is_array($CONFIG)) { fwrite(STDERR, "source is not a Nextcloud config.php\n"); exit(1); }
$over = json_decode(file_get_contents($argv[3]), true);
if (!is_array($over)) { fwrite(STDERR, "bad overrides\n"); exit(1); }

$drop = [
    'apps_paths', 'logfile', 'logfile_audit', 'tempdirectory', 'updatedirectory', 'upgrade.disable-web',
    'trusted_proxies', 'overwritehost', 'overwriteprotocol', 'overwrite.cli.url', 'overwritewebroot',
    'overwritecondaddr', 'trusted_domains', 'redis', 'redis.cluster', 'memcache.distributed', 'memcache.locking',
    'mail_smtpsecure_unused', 'datadirectory', 'dbtype', 'dbhost', 'dbname', 'dbuser', 'dbpassword', 'dbport',
];
$dropped = [];
foreach ($drop as $k) {
    if (array_key_exists($k, $CONFIG)) { unset($CONFIG[$k]); if (!array_key_exists($k, $over)) { $dropped[] = $k; } }
}
// APCu local cache is available in the official image; anything else is dropped.
if (isset($CONFIG['memcache.local']) && $CONFIG['memcache.local'] !== '\\OC\\Memcache\\APCu') {
    $dropped[] = 'memcache.local'; unset($CONFIG['memcache.local']);
}
foreach ($over as $k => $v) { $CONFIG[$k] = $v; }
$CONFIG['maintenance'] = false;

$out = "<?php\n\$CONFIG = " . var_export($CONFIG, true) . ";\n";
file_put_contents($argv[2], $out);
chmod($argv[2], 0640);
echo implode("\n", $dropped), "\n";
