struct GitHubProvisionerConfig: Decodable {
    let appId: Int
    let organization: String
    let repository: String?
    let privateKeyPath: String
    let runnerName: String
    let extraLabels: [String]?

    init(
        appId: Int,
        organization: String,
        repository: String?,
        privateKeyPath: String,
        runnerName: String,
        extraLabels: [String]?
    ) {
        self.appId = appId
        self.organization = organization
        self.repository = repository
        self.privateKeyPath = privateKeyPath
        self.runnerName = runnerName
        self.extraLabels = extraLabels
    }
}

struct GitHubProvisioner {
    static let runnerCacheMountTag = "actions-runner-cache"

    func script(config: GitHubProvisionerConfig, runnerToken: String, cacheDirectory: String? = nil) -> [String] {
        let labels = labelsString(extraLabels: config.extraLabels)
        let url = runnerURL(organization: config.organization, repository: config.repository)
        let cacheScript = runnerCacheScript(cacheDirectory: cacheDirectory)
        return [
            """
os=$(uname -s)
case "$os" in
  Darwin) runner_os=osx ;;
  Linux) runner_os=linux ;;
  *) echo "unsupported os: $os"; exit 1 ;;
esac
arch=$(uname -m)
case "$arch" in
  x86_64|amd64) runner_arch=x64 ;;
  arm64|aarch64) runner_arch=arm64 ;;
  armv7l|armv6l) runner_arch=arm ;;
  *) echo "unsupported arch: $arch"; exit 1 ;;
esac
version="2.330.0"
asset=actions-runner-${runner_os}-${runner_arch}-${version}.tar.gz
download_url=https://github.com/actions/runner/releases/download/v${version}/${asset}
echo $download_url
\(cacheScript)
""",
            "rm -rf ~/actions-runner && mkdir ~/actions-runner",
            "tar xzf ./actions-runner.tar.gz -C ~/actions-runner",
            "echo \"Runner downloaded and extracted\"",
            "~/actions-runner/config.sh --url \(url) --name \(config.runnerName) --token \(runnerToken) --ephemeral --unattended --replace --labels \(labels)",
            "echo \"Runner script downloaded, starting ~/actions-runner/run.sh\"",
            "~/actions-runner/run.sh"
        ]
    }

    private func labelsString(extraLabels: [String]?) -> String {
        var labels = ["sand"]
        if let extraLabels {
            labels.append(contentsOf: extraLabels)
        }
        return labels.joined(separator: ",")
    }

    private func runnerCacheScript(cacheDirectory: String?) -> String {
        guard let cacheDirectory else {
            return "curl -fsSL -o actions-runner.tar.gz -L ${download_url}"
        }
        return """
cache_dir_name="\(cacheDirectory)"
if [ -z "$cache_dir_name" ]; then
  curl -fsSL -o actions-runner.tar.gz -L ${download_url}
  exit 0
fi
cache_candidates=()
case "$cache_dir_name" in
  /*)
    cache_candidates+=("$cache_dir_name")
    ;;
  *)
    if [ "$(uname -s)" = "Darwin" ]; then
      cache_candidates+=("/Volumes/My Shared Files/$cache_dir_name")
      cache_candidates+=("$HOME/$cache_dir_name")
    else
      cache_candidates+=("$HOME/$cache_dir_name")
    fi
    ;;
esac
cache_dir=""
for candidate in "${cache_candidates[@]}"; do
  if [ -d "$candidate" ]; then
    cache_dir="$candidate"
    break
  fi
done
if [ -z "$cache_dir" ]; then
  echo "runner cache unavailable: $cache_dir_name not mounted"
  curl -fsSL -o actions-runner.tar.gz -L ${download_url}
  exit 0
fi
cache_file="${cache_dir}/${asset}"
if [ -f "$cache_file" ]; then
  echo "runner cache hit: $cache_file"
  cp "$cache_file" actions-runner.tar.gz
else
  echo "runner cache miss: downloading"
  curl -fsSL -o actions-runner.tar.gz -L ${download_url}
  if [ -w "$cache_dir" ]; then
    tmp_file="${cache_dir}/.${asset}.tmp.$$"
    cp actions-runner.tar.gz "$tmp_file" && mv "$tmp_file" "$cache_file"
    echo "runner cache populated: $cache_file"
  fi
fi
"""
    }

    private func runnerURL(organization: String, repository: String?) -> String {
        if let repository {
            return "https://github.com/\(organization)/\(repository)"
        }
        return "https://github.com/\(organization)"
    }
}
