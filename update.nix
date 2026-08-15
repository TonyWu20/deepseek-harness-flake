{
  pkgs,
}:

pkgs.writeShellApplication {
  name = "dsh-update";
  runtimeInputs = with pkgs; [
    curl
    jq
    nix
    nix-prefetch-git
  ];
  text = # bash
    ''
      set -euo pipefail

      repo="deepseek-ai/deepseek-harness"

      rev="$(
        curl -fsSL "https://api.github.com/repos/$repo/commits/master" \
          | jq -r .sha
      )"

      current="$(jq -r .rev VERSION.json)"
      if [ "$rev" = "$current" ]; then
        echo "dsh-update: already at $rev"
        exit 0
      fi

      echo "dsh-update: $current -> $rev"

      hash="$(
        nix-prefetch-git \
          --url "https://github.com/$repo.git" \
          --rev "$rev" \
          --fetch-submodules \
          2>/dev/null \
          | jq -r .sha256
      )"

      jq \
        --arg rev "$rev" \
        --arg hash "$hash" \
        '.rev = $rev | .hash = $hash | .pnpmDepsHash = ""' \
        VERSION.json > VERSION.json.tmp
      mv VERSION.json.tmp VERSION.json

      echo "dsh-update: VERSION.json updated"
      echo "dsh-update: build the package to learn the new pnpmDepsHash"
    '';
}
