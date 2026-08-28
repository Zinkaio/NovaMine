<p align="center">
	<img src=".github/novamine-logo.png" alt="NovaMine" width="320" />
</p>

<h1 align="center">NovaMine</h1>

<p align="center">
	<b>Server software for Minecraft: Bedrock Edition — PocketMine-MP, kept on the latest Bedrock release.</b>
</p>

<p align="center">
	<img alt="Minecraft: Bedrock Edition 1.26.45" src="https://img.shields.io/badge/minecraft-bedrock%201.26.45-44b528">
	<img alt="Protocol 2169" src="https://img.shields.io/badge/protocol-2169-1f6feb">
	<img alt="PHP 8.1+ 64-bit" src="https://img.shields.io/badge/php-8.1%2B%2064--bit-777bb4?logo=php&logoColor=white">
	<img alt="Plugin API 5.x" src="https://img.shields.io/badge/plugin%20API-5.x-8957e5">
	<img alt="Licence LGPL-3.0" src="https://img.shields.io/badge/licence-LGPL--3.0-blue">
	<a href="https://github.com/Zinkaio/NovaMine/commits"><img alt="Last commit" src="https://img.shields.io/github/last-commit/Zinkaio/NovaMine"></a>
</p>

---

## What is NovaMine?

NovaMine is a build of [PocketMine-MP](https://github.com/pmmp/PocketMine-MP) maintained by **Zinkaio** for
**NovaPE**, updated to the current Minecraft: Bedrock protocol so servers don't have to wait to accept
players on the newest client.

If you already run a PocketMine-MP server, nothing changes: same config files, same worlds, same plugin API.
Drop the `.phar` in and start it.

| | |
|---|---|
| **Minecraft: Bedrock** | 1.26.45 |
| **Network protocol** | 2169 |
| **Engine base** | PocketMine-MP 5.44.2 |
| **Plugin API** | 5.x — existing PMMP 5 plugins work unchanged |
| **PHP** | 8.1 or newer, 64-bit |

> **Players must be on Minecraft 1.26.45.** Bedrock clients only connect to a server built for their own
> version, so anyone still on 1.26.44 or older will see *outdated client* until they update. Keep the
> `.phar` current and your players will always be able to get in on release day.

---

## What's new

**Minecraft 1.26.45 (protocol 2169).** Clients on 1.26.45 connect again; the previous build spoke
2168 and turned them away with *Incompatible protocol version*.

This one was a **code-only** bump — the Bedrock block palette and item registry are byte-identical to
1.26.44, so worlds and custom blocks carry over untouched. The protocol changes are small and
self-contained: `SetScorePacket` drops the old empty-string workaround, `MolangItemDescriptor` reads
its version as a signed short, and the `PersonaSkinPiece` / `SkinAnimation` enums shift by one for a
new "unknown" entry. Nothing in the plugin API moved, so **existing PMMP 5 plugins keep working with
no changes**.

**CPU load in `/status`.** The status output now reports **CPU load** alongside TPS and
memory — both since boot and since the previous `/status`, and as a share of one core
as well as of the whole machine:

```
Thread count: 4
CPU load (since boot): 3.2% of one core (0.2% of 16 cores)
CPU load (since last /status): 41.7% of one core (2.6% of 16 cores)
```

The since-last-call figure is the useful one while diagnosing lag: it measures the
window between the two commands instead of averaging away a spike across your whole
uptime. It covers the entire process — the main thread, the network thread and the
async workers — so it is real OS CPU time, not the tick-usage percentage already shown
next to TPS.

Worth knowing what it tells you: PocketMine ticks the world on a **single thread**, so
"100% of one core" is the ceiling for game logic no matter how many cores the box has.
If that number is pinned while the whole-machine share stays low, more cores will not
help — the fix is less work per tick (fewer loaded worlds, fewer ticking entities), not
bigger hardware.

---

## Quick start

**Windows**

1. Download `NovaMine.phar`, `start.cmd` and `setup.ps1` into an empty folder.
2. Run `start.cmd`, type `run`, press Enter.

**Linux / macOS**

1. Download `NovaMine.phar` and `start.sh` into an empty folder.
2. `chmod +x start.sh && ./start.sh`, type `run`, press Enter.

That's the whole setup. **You don't need to install PHP yourself** — on first launch the
starter downloads the PHP build PocketMine-MP uses, drops it in `bin/php/`, and tunes it
(see [First-run setup](#first-run-setup)). Later launches skip all of it and start
immediately.

```
your-server/
├── NovaMine.phar
├── start.cmd + setup.ps1     (Windows)
├── start.sh                  (Linux / macOS)
└── bin/php/                  ← created for you on first run
```

The first launch writes `server.properties`, `pocketmine.yml` and a `plugins/` folder next to the `.phar`,
then generates a world. Stop the server cleanly at any time with `stop` in the console.

---

## First-run setup

The starter does two things once, then never again:

**Installs PHP.** Grabs the official
[pmmp/PHP-Binaries](https://github.com/pmmp/PHP-Binaries/releases) build for your
platform — Windows x64, Linux x86_64, macOS Intel or Apple Silicon — and unpacks it to
`bin/php/`. Already have a PHP there? It's left alone.

**Turns on PHP's JIT compiler.** The prebuilt PHP ships an OPcache compiled *without*
JIT, so the `opcache.jit` settings don't exist and setting them by hand does nothing.
On Windows the starter replaces that OPcache with the official PHP build of the **same
version and ABI**, which does include JIT, and switches it on. Measured on a benchmark
shaped like the server's hot path — vector maths, squared length, AABB overlap:

| | before | after | |
|---|---|---|---|
| single thread | 0.507 s | 0.168 s | **3.0×** |
| 8 concurrent worker threads | 0.119 s | 0.064 s | **1.9×** |

Real ticking does more allocation and hashing than a tight maths loop, so treat those as
the ceiling rather than the gain to expect. On Linux/macOS the starter enables JIT when
your PHP build supports it and quietly skips it when it doesn't.

It is careful about it:

- A PHP extension must match the interpreter's ABI **exactly** — version, thread safety,
  compiler — or the process crashes on startup. The ABI is compared byte for byte and
  anything that doesn't match is refused.
- Your original OPcache is kept as `php_opcache.dll.nojit-backup`.
- Setup failures (no network, unavailable download) print a warning and the server starts
  normally anyway. It will never leave you unable to run.

**To undo:**

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1 -Revert   # Windows
```
```bash
./start.sh --revert-jit                                      # Linux / macOS
```

---

## Updating

When a new Bedrock version ships, replace `NovaMine.phar` with the latest one from here — that file *is*
the server. Stop the server, swap the `.phar`, start it again. Your worlds, configs and plugins are all
stored beside it and are left untouched, so nothing else needs changing.

Keep a copy of the old `.phar` until you've confirmed players can join; rolling back is just swapping it
back.

---

## Requirements

PHP **8.1+, 64-bit**, with the extensions PocketMine-MP needs:

```
chunkutils2  crypto  ctype  curl  date  gmp  hash  igbinary  json
leveldb  mbstring  morton  openssl  pcre  phar  pmmpthread
reflection  simplexml  sockets  spl  yaml  zip  zlib
```

A stock PHP install won't have `pmmpthread`, `leveldb`, `chunkutils2` or `morton` — which is why the
starter fetches a prebuilt bundle from [pmmp/PHP-Binaries](https://github.com/pmmp/PHP-Binaries/releases)
(`pm5-latest`) for you on first run. If you'd rather do it by hand, unpack that release so `bin/php/` sits
next to the `.phar` and the starter will use it as-is.

---

## Plugins

NovaMine loads standard PocketMine-MP 5 plugins. Drop a plugin `.phar` into `plugins/` and restart.

- [Poggit](https://poggit.pmmp.io/plugins) — plugin repository
- [Plugin developer docs](https://devdoc.pmmp.io)
- [API reference](https://apidoc.pmmp.io)

---

## Not a vanilla server

This is inherited from PocketMine-MP and worth knowing before you install it: **NovaMine is not a vanilla
Minecraft server.** Vanilla world generation, redstone and mob AI are largely absent — it is built for
custom servers driven by plugins (minigames, hubs, practice servers).

If you want vanilla survival multiplayer, use
[Mojang's official Bedrock server](https://minecraft.net/download/server/bedrock) instead. Otherwise, most
gaps can be filled with plugins.

---

## Credits & licence

Built on [PocketMine-MP](https://github.com/pmmp/PocketMine-MP) by the PMMP Team, licensed under
**LGPL-3.0**. NovaMine is distributed under the same licence — see [LICENSE](LICENSE).

NovaMine, NovaPE and PocketMine-MP are not affiliated with Mojang or Microsoft. Minecraft is a trademark of
Mojang AB. All brands and trademarks belong to their respective owners.
