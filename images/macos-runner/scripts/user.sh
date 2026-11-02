#!/bin/bash
set -euo pipefail

NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

touch ~/.zprofile
ln -sfn ~/.zprofile ~/.profile
cat >>~/.zprofile <<'EOF'
export LANG=en_US.UTF-8
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
EOF

eval "$(/opt/homebrew/bin/brew shellenv)"
brew install git git-lfs gh jq yq wget xcodes
git lfs install

mkdir -p ~/.ssh
chmod 700 ~/.ssh
curl -fsSL https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' >>~/.ssh/known_hosts
