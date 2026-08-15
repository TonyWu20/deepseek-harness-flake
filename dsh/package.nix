{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  jq,
  makeWrapper,
  nodejs-slim,
  pnpmConfigHook,
  pnpm_11,
  yq-go,
  src,
  version,
  pnpmDepsHash,
  bashInteractive,
  runtimeDeps ? [ ],
}:

buildNpmPackage (finalAttrs: {
  pname = "deepseek-harness";
  inherit src version;

  nodejs = nodejs-slim;
  # nodejs-slim is a runtime dependency (the wrapper executes lib/bin.js with
  # it, and pnpmConfigHook rewrites node shebangs to its store path).
  disallowedReferences = [
    pnpm_11
  ];

  # Patch the workspace before any install:
  # - add every @deepseek-ai/* workspace package to the `dsh` CLI closure so
  #   `pnpm deploy --prod` produces a complete runtime,
  # - drop lifecycle scripts that need network access.
  postPatch = ''
    bash ${./patch-workspace.sh} dependencies
    bash ${./patch-workspace.sh} lifecycle
  '';

  pnpmDeps = (fetchPnpmDeps.override { yq = yq-go; }) {
    inherit (finalAttrs)
      pname
      version
      src
      postPatch
      ;
    nativeBuildInputs = [ yq-go ];
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = pnpmDepsHash;
  };

  nativeBuildInputs = [
    jq
    nodejs-slim.npm
    pnpm_11
    yq-go
  ];

  npmDeps = null;
  npmConfigHook = pnpmConfigHook;
  npmBuildScript = "build";

  # node-pty's install script cannot download prebuilt binaries during the
  # deploy (no network), so the deployed tree runs its postinstall through
  # `pnpm deploy`.  The subprocess-local postinstall would be rejected there;
  # it is executed manually below.
  preInstall = ''
    pnpm config set --location=project inject-workspace-packages true
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/lib/deepseek-harness"
    mkdir -p "$appDir"

    pnpm --filter @deepseek-ai/dsh deploy \
      --prod \
      --config.node-linker=hoisted \
      --config.link-workspace-packages=true \
      "$appDir"

    ${lib.getExe nodejs-slim} \
      "$appDir/node_modules/@deepseek-ai/dsh-subprocess-local/scripts/ensure-spawn-helper.mjs"

    mkdir -p "$out/bin"
    makeWrapper ${lib.getExe nodejs-slim} "$out/bin/dsh" \
      --add-flags "--expose-internals" \
      --add-flags "$appDir/lib/bin.js" \
      --prefix PATH : "${
        lib.makeBinPath ([
          bashInteractive
        ] ++ runtimeDeps)
      }"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    DSH_HOME="$TMPDIR/dsh-home" "$out/bin/dsh" --version
    runHook postInstallCheck
  '';

  meta = {
    description = "DeepSeek Harness agent CLI (dsh)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
