# helix_remote_db

Local database for the Helix Remote v2 client: drift over SQLCipher, opened on
a background isolate, with DAOs and watch queries for the engine. Pure Dart
(no Flutter).

```dart
final db = await HelixDb.open(File(path), key: DatabaseKey(keyBytes));
final chat = await db.conversationsDao.ensureDirect(peer, now: now);
db.conversationsDao.watchList().listen(render);
```

Schema, rules, regeneration and migrations: [MODULE.md](MODULE.md).

```
dart test                            # run from this directory
dart run tool/codegen.dart --check   # generated code is current
```
