struct GitHubRunnerCache: Decodable {
    let hostPath: String
    let guestFolder: String
    let readOnly: Bool

    init(hostPath: String, guestFolder: String, readOnly: Bool = false) {
        self.hostPath = hostPath
        self.guestFolder = guestFolder
        self.readOnly = readOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hostPath = try container.decode(String.self, forKey: .hostPath)
        self.guestFolder = try container.decode(String.self, forKey: .guestFolder)
        self.readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case hostPath
        case guestFolder
        case readOnly
    }
}

struct GitHubProvisionerConfig: Decodable {
    let appId: Int
    let organization: String
    let repository: String?
    let privateKeyPath: String
    let runnerName: String
    let extraLabels: [String]?
    let runnerCache: GitHubRunnerCache?

    init(
        appId: Int,
        organization: String,
        repository: String?,
        privateKeyPath: String,
        runnerName: String,
        extraLabels: [String]?,
        runnerCache: GitHubRunnerCache?
    ) {
        self.appId = appId
        self.organization = organization
        self.repository = repository
        self.privateKeyPath = privateKeyPath
        self.runnerName = runnerName
        self.extraLabels = extraLabels
        self.runnerCache = runnerCache
    }
}

struct GitHubProvisioner {
    func script(config: GitHubProvisionerConfig, runnerToken: String) -> [String] {
        let labels = labelsString(extraLabels: config.extraLabels)
        let url = runnerURL(organization: config.organization, repository: config.repository)
        let cacheScript = runnerCacheScript(cache: config.runnerCache)
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

    private func runnerCacheScript(cache: GitHubRunnerCache?) -> String {
        guard let cache else {
            return "curl -fsSL -o actions-runner.tar.gz -L ${download_url}"
        }
        let guestFolder = cache.guestFolder
        return """
cache_dir="\(guestFolder)"
case "$cache_dir" in
  /*) ;;
  *) cache_dir="$HOME/$cache_dir" ;;
esac
cache_file="${cache_dir}/${asset}"
if [ -d "$cache_dir" ] && [ -f "$cache_file" ]; then
  echo "runner cache hit: $cache_file"
  cp "$cache_file" actions-runner.tar.gz
else
  echo "runner cache miss: downloading"
  curl -fsSL -o actions-runner.tar.gz -L ${download_url}
  if [ -d "$cache_dir" ] && [ -w "$cache_dir" ]; then
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
