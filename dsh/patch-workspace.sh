#!/usr/bin/env bash
# Patch the deepseek-harness workspace so a self-contained `dsh` runtime can
# be deployed with `pnpm deploy`.
#
# The upstream `apps/cli/package.json` declares runtime plugins as
# devDependencies or peerDependencies only (for example
# `@deepseek-ai/cordis-plugin-group`).  `pnpm deploy --prod` therefore omits
# them from the deployed node_modules and the CLI crashes at startup.
#
# This hook adds every `@deepseek-ai/*` workspace package as a regular
# dependency of `apps/cli`, in both `apps/cli/package.json` and the
# `importers."apps/cli"` section of `pnpm-lock.yaml`.  A subsequent
# `pnpm deploy --prod` then carries the complete runtime closure.
set -euo pipefail

# Every publishable workspace package, as shell glob patterns.  The depth
# keeps test fixtures (which live deeper in the tree) out of the closure.
WORKSPACE_PACKAGE_GLOBS=(
  vendor/*/package.json
  packages/*/*/package.json
)

workspaceDeps() {
  local deps_file
  deps_file="${TMPDIR:-/tmp}/dsh-workspace-dependencies.json"

  yq ea -o=json -I=0 '
    (select(.name | test("^@deepseek-ai/")) | {
      (.name): "workspace:^"
    }) as $item ireduce ({}; . * $item)
  ' "${WORKSPACE_PACKAGE_GLOBS[@]}" >"$deps_file"

  DEPS_FILE="$deps_file" yq -i \
    '.dependencies *= load(strenv(DEPS_FILE))' \
    apps/cli/package.json
}

workspaceLockDeps() {
  local lock_deps_file
  lock_deps_file="${TMPDIR:-/tmp}/dsh-workspace-lock-dependencies.json"

  # `link:` paths inside an importer are relative to the importer directory,
  # hence the leading `../../` from `apps/cli`.
  yq ea -o=json -I=0 '
    (select(.name | test("^@deepseek-ai/")) | {
      (.name): {
        "specifier": "workspace:^",
        "version": "link:" + (filename | sub("/package.json$"; "") | sub("^"; "../../"))
      }
    }) as $item ireduce ({}; . * $item)
  ' "${WORKSPACE_PACKAGE_GLOBS[@]}" >"$lock_deps_file"

  DEPS_FILE="$lock_deps_file" yq -i \
    '.importers."apps/cli".dependencies *= load(strenv(DEPS_FILE))' \
    pnpm-lock.yaml
}

dropLifecycleScripts() {
  # The root postinstall installs lefthook git hooks and needs network
  # access.  It is unnecessary for a Nix build.
  yq -i 'del(.scripts.postinstall)' package.json

  # The subprocess-local postinstall restores the node-pty spawn helper
  # executable bit.  It is run manually after the deploy instead, because
  # pnpm deploy rejects this build script.
  yq -i 'del(.scripts.postinstall)' packages/subprocess/subprocess-local/package.json
}

patchDshWorkspace() {
  local phase="${1:-}"
  shift || true

  case "$phase" in
    dependencies)
      workspaceDeps
      workspaceLockDeps
      ;;
    lifecycle)
      dropLifecycleScripts
      ;;
    *)
      printf 'patchDshWorkspace: unknown phase "%s"\n' "$phase" >&2
      return 1
      ;;
  esac
}

patchDshWorkspace "$@"
