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
    func script(config: GitHubProvisionerConfig, runnerToken: String) -> [String] {
        let labels = labelsString(extraLabels: config.extraLabels)
        let url = runnerURL(organization: config.organization, repository: config.repository)
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
curl -fsSL -o actions-runner.tar.gz -L ${download_url}
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

    private func runnerURL(organization: String, repository: String?) -> String {
        if let repository {
            return "https://github.com/\(organization)/\(repository)"
        }
        return "https://github.com/\(organization)"
    }
}
