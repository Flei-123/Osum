# Die Abnahmemodule der Runde SCHLEUSE, unveraendert

Damit SCHLEUSE-2 mit **denselben Modulen** abgenommen werden kann wie SCHLEUSE
(Auftrag Punkt 3), liegen sie hier im Baum statt nur in /tmp.

| Datei | Oktett | Herkunft | md5 |
|---|---|---|---|
| `hallo.wasm` | 313 | von Hand geschriebenes `.wat`, ueber `wat2wasm` | 93d8269ee11ced6b263bdd9d4ca683a0 |
| `hello2.wasm` | 47364 | Rust nach `wasm32-wasip1`, `-C debuginfo=0 -C strip=symbols` | 582abfbf5f8f392cf75fae6771de6970 |
| `dateitest.wasm` | 74713 | Rust, Datei anlegen/schreiben/zurueckleisen | ace2e3985b640f47836a6e9f02cd5817 |
| `prim.wasm` | 60713 | Rust, Primzahlen per Probedivision -- der Tempo-Bench | 801765194b6e3b97b7ff59e125216bac |
| `schleife.wasm` | 47395 | Rust, reine Zaehlschleife | bb2d991bab04b69d1fa7634c484bbb56 |
| `sqlite.wasm` | 1340817 | SQLite 3.45.0 Amalgamation, wasi-sdk 24, `wasm32-wasi` | 3d8a701f88d1af3e9cf495f181d20565 |

`sqlite.wasm` ist **dasselbe Modul**, das in SCHLEUSE unter dem Deuter lief.
Das ist die Voraussetzung dafuer, dass "byte-identisch zum Deuter-Lauf"
ueberhaupt eine Aussage ist.

Unter `quelle/` liegen die zugehoerigen Quelltexte (`.rs`, `.c`, `.wat`).
