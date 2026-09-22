# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`uvcc` is a CLI that reads and writes USB Video Class (UVC) camera controls — brightness, zoom, white balance, etc. It is an ESM-only TypeScript package published to npm, upstream at `github:joelpurra/uvcc`, GPL-3.0.

## Commands

Node >= 22 is required. In a non-interactive agent shell `node` may not be on `PATH` even though it is installed; source nvm first:

```bash
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
```

```bash
npm install                 # installs uvc-control from a git ref (github:joelpurra/node-uvc-control#v2)
npm run rebuild             # clean + tsc; do this before running anything, the bin is ./dist/index.js
npm run build:watch

npm test                    # NOTE: this is lint only — there is no test suite (see "Testing")
npm run lint                # xo + prettier + copyright-header check
npm run lint:fix            # xo --fix + prettier --write
npm run lint:copyright      # greps every .js/.ts for the "This file is part of uvcc" header

node ./dist/index.js devices        # exercise a local build
node ./dist/index.js export
npm run debug:run:break -- export   # node --inspect-brk; `--` separates npm args from uvcc args
```

`lint:prettier` only checks formatting, and only for `*.json` and `*.md`. `lint:xo` covers `*.ts`/`*.js` **and** applies content rules to `*.md` — a fenced code block with no language tag fails `markdown/fenced-code-language`, so Markdown edits have to satisfy both.

Husky `pre-commit` and `pre-push` hooks both run `npm test`.

Branching follows git-flow (git-flow-avh); `develop` is the working branch.

## Architecture

Layers, outermost first:

```text
index.ts (composition root)
  → runtime-configurator.ts   argv/env/config-file → RuntimeConfiguration
  → CommandManager            camera lifecycle, argument injection, JSON output
  → CommandHandlers           name → Command lookup
  → command-handlers/*.ts     one class per CLI verb
  → CameraHelper              gettable/settable/ranged enforcement, bulk get/set
  → CameraControlHelper       classifies the camera's supported controls
  → uvc-control (git dep) → usb / libusb
```

**`src/index.ts` is the only wiring.** Dependency injection is manual and constructor-based — no container, no decorators in practice. Every class asserts `arguments.length` and the type of each constructor argument, so adding or reordering a constructor parameter means updating those asserts too.

**Adding a CLI command** touches three places: a new `command-handlers/<name>.ts` implementing `Command`, an entry in the `commands` object in `index.ts`, and a `.command()` declaration in `runtime-configurator.ts` (yargs runs in `.strict()` mode, so an unregistered flag is a hard error).

**Argument passing is name-based, not positional.** A handler's `getArguments()` returns `RuntimeConfiguration` key names; `CommandManager` looks each one up in the runtime config and spreads them into `execute(...args)` in that order. The string `"cameraHelper"` (`CommandHandlerArgumentCameraHelper`) is a magic sentinel, not a config key: when present, `CommandManager` opens the camera, builds a `CameraHelper`, and `unshift`s it as the first argument. Handlers receive `...args: readonly unknown[]` and cast — the type system does not check this wiring, so the asserts in each handler are the guard.

**`CommandManager` owns the camera connection** — it is the only code that opens and closes it, including on the error path. Handlers never construct or close a camera.

**Output discipline:** `CommandManager` `JSON.stringify`s whatever `execute()` returns onto stdout; returning `undefined` means "no output". `Output.normal` goes to stdout, while `verbose`/`warning`/`error` go to **stderr** — this is deliberate, so `uvcc export > file.json` stays valid JSON. Do not `console.log` diagnostics.

**Control capability classification** lives in `CameraControlHelper`, which reads `uvc-control` internals (`control.requests` / `control.optional_requests` against `UvcControl.REQUEST.GET_CUR|GET_MIN|GET_MAX|SET_CUR`) to derive `isGettable` / `isRanged` / `isSettable`. `CameraHelper` refuses any operation on a control that lacks the matching flag. The comments marking `NOTE: relies on uvc-control internals` are load-bearing — that coupling breaks on uvc-control upgrades.

**`export` intentionally emits only settable controls,** because `import` hard-fails if the incoming JSON names a non-settable control. Bulk reads (`getRanges`, `getSettableControls`) swallow per-control errors to `verbose` output rather than aborting, since real cameras stall on individual controls; `setControls` instead validates _all_ names up front before setting any.

**Configuration precedence** (`runtime-configurator.ts`): passing `--config` disables implicit config-file loading entirely. Otherwise `.uvccrc` / `.uvccrc.json` is searched upward from cwd, then upward from `$HOME`. Env vars use the `UVCC_` prefix. A loaded config file may not itself set `config`.

**`uvc-control` ships no types.** They are hand-written as an ambient module declaration in `src/types/uvc-control.d.ts`; using a new API from that library means extending that file first.

## Conventions

- **Every `.js`/`.ts` file must carry the GPL copyright header** (`This file is part of uvcc …`) as its first block — `lint:copyright` fails the build otherwise. Copy it verbatim from any existing source file.
- Tabs for indentation in TS/JS; two spaces in JSON/Markdown (`.editorconfig`).
- ESM only: relative imports carry the `.js` extension even in TypeScript sources.
- `import type` / inline `type` qualifiers are used consistently; most parameters are wrapped in `ReadonlyDeep<T>`.
- Object keys are sorted (`sort-keys` lint rule); deliberate exceptions carry an `eslint-disable-next-line sort-keys` with a reason.

## Testing

There is no automated test suite — `npm test` only lints, and "Add tests" is an open item in `DEVELOP.md`. Verification is manual against real USB hardware (`node ./dist/index.js controls|ranges|export|get|set`). Say so plainly rather than implying a test run covered a change.

`examples/<vendor-model>/<vendorId>-<productId>/` holds captured `controls.json`, `devices.json`, `export.json`, `ranges.json`, and `metadata.json` per camera, regenerated by running `examples/update-example.sh` from inside that directory (needs `jq` and a connected camera). Ids in the directory name are decimal, unpadded. These are the closest thing to fixtures and are useful for reasoning about real control sets; `.prettierignore` excludes them from formatting.
