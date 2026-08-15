# deepseek-harness flake

A Nix flake for [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
the DeepSeek Harness agent CLI (`dsh`).

The flake provides:

- a `dsh` package for `nix run` / `nix build`,
- a NixOS module,
- a Home Manager module,
- an overlay exposing `pkgs.deepseek-harness`,
- `lib.mkDsh` for building a configured wrapper,
- an `update` app that re-pins the upstream source.

The project is modeled on [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix).

> [!IMPORTANT]
> deepseek-harness is in developer preview.  Upstream changes frequently and
> breaks compatibility.  The pinned revision is recorded in `VERSION.json`.

## Package

Build and run the CLI:

```bash
nix build .#dsh
nix run .#dsh -- --version
nix run .#dsh -- web
```

`dsh web` serves the web UI at `http://127.0.0.1:3080`.

## NixOS module

```nix
{
  inputs.deepseek-harness.url = "github:TonyWu20/deepseek-harness-flake";

  outputs = { self, nixpkgs, deepseek-harness, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        deepseek-harness.nixosModules.default
        {
          programs.dsh.enable = true;
          programs.dsh.profile = "web";
        }
      ];
    };
  };
}
```

## Home Manager module

```nix
{
  imports = [ inputs.deepseek-harness.homeModules.default ];
  programs.dsh.enable = true;
  programs.dsh.settings = {
    model.provider = "deepseek";
  };
}
```

## Module options

| Option                     | Default | Description                                      |
| -------------------------- | ------- | ------------------------------------------------ |
| `programs.dsh.enable`      | `false` | Install dsh.                                     |
| `programs.dsh.package`     | flake   | The package to install.                          |
| `programs.dsh.profile`     | `null`  | Profile passed to `dsh --profile` by default.    |
| `programs.dsh.settings`    | `{}`    | Contents of `$DSH_HOME/settings.yaml`.           |
| `programs.dsh.environment` | `{}`    | Environment variables exported before dsh runs.  |
| `programs.dsh.extraArgs`   | `[]`    | Extra arguments appended to every invocation.    |

## Overlay

```nix
{
  nixpkgs.overlays = [ inputs.deepseek-harness.overlays.default ];
  environment.systemPackages = [ pkgs.deepseek-harness ];
}
```

## Updating

```bash
nix run .#update
```

The script pins the latest `master` commit and clears the dependency hash.
It also records the upstream version in `VERSION.json`.  Build the package to
learn the new hash, then set `pnpmDepsHash` in `VERSION.json`:

```bash
nix build .#dsh 2>&1 | rg 'got: sha256-'
```

## How the package is built

The upstream workspace uses pnpm 11.  The derivation:

1. patches the workspace so every `@deepseek-ai/*` package becomes a
   dependency of the `dsh` CLI, which makes the deployed runtime complete,
2. fetches all pnpm dependencies into a reproducible store,
3. runs the full upstream build (`tsc`, `tsdown`, `vite`),
4. deploys a production `node_modules` with `pnpm deploy --prod`,
5. wraps the `dsh` binary with `node --expose-internals`.

Native modules (`node-pty`, `koffi`, `node-addon-require-builtin`, `esbuild`)
resolve through platform packages or build from source during the deploy.
