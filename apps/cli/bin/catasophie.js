#!/usr/bin/env node
// Thin dispatcher: `catasophie <command> [args...]` just starts the
// corresponding shell script under apps/cli/scripts/, forwarding all
// remaining args and inheriting stdio (so the scripts' own interactive
// prompts - whiptail/dialog/plain-text, `read -p`, etc. - work exactly
// as if invoked directly). All actual install/uninstall/backup/restore/
// update logic lives in those shell scripts (and, per-app, in
// apps/<id>/install.sh + apps/<id>/uninstall.sh) - this CLI does not
// reimplement any of it.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = path.join(__dirname, "..", "scripts");

const COMMANDS = {
  install: "install.sh",
  uninstall: "uninstall.sh",
  up: "up.sh",
  down: "down.sh",
  update: "update.sh",
  backup: "backup.sh",
  restore: "restore.sh",
  "add-app": "add-app.sh",
};

function printHelp() {
  console.log(`Usage: catasophie <command> [args...]

Commands:
  install [app-id...]           Interactively pick + install app(s), or install the given ones
  uninstall [app-id...] [flags] Uninstall app(s), or everything if none given
  up <app-id...>                 Start the named app(s)
  down <app-id...>               Stop the named app(s)
  update [app-id...] [flags]    git pull + update installed app(s), with backup/rollback
  backup [app-id...] [--keep N] Back up app data + .env
  restore <app-id> [which]       Restore an app from a backup
  add-app <app-id> <port>        Scaffold a new app from apps/_template

Each command just starts the matching shell script under
apps/cli/scripts/ (or, for per-app install/uninstall, the app's own
apps/<id>/install.sh / uninstall.sh) - run \`catasophie <command> --help\`
style flags are documented in that script's own header comment.`);
}

const [, , command, ...args] = process.argv;

if (!command || command === "-h" || command === "--help" || command === "help") {
  printHelp();
  process.exit(command ? 0 : 1);
}

const scriptName = COMMANDS[command];
if (!scriptName) {
  console.error(`error: unknown command '${command}'`);
  printHelp();
  process.exit(1);
}

const scriptPath = path.join(SCRIPTS_DIR, scriptName);
const result = spawnSync("bash", [scriptPath, ...args], { stdio: "inherit" });

if (result.error) {
  console.error(`error: failed to start ${scriptPath}: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
