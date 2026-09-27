struct GitHubProvisionerConfig: Decodable, Sendable {
    let appId: Int
    let organization: String
    let repository: String?
    let privateKeyPath: String
    let runnerName: String
    let extraLabels: [String]?
    let runnerGroup: String?

    init(
        appId: Int,
        organization: String,
        repository: String?,
        privateKeyPath: String,
        runnerName: String,
        extraLabels: [String]?,
        runnerGroup: String? = nil
    ) {
        self.appId = appId
        self.organization = organization
        self.repository = repository
        self.privateKeyPath = privateKeyPath
        self.runnerName = runnerName
        self.extraLabels = extraLabels
        self.runnerGroup = runnerGroup
    }
}

struct GitHubProvisioner: Sendable {
    static let tarballRemotePath = "actions-runner.tar.gz"

    static func uniqueRunnerName(base: String) -> String {
        "\(base)-\(String(format: "%05x", Int.random(in: 0..<0x100000)))"
    }

    func script(
        config: GitHubProvisionerConfig,
        runnerName: String,
        runnerToken: String
    ) -> [String] {
        let labels = labelsString(extraLabels: config.extraLabels)
        let url = runnerURL(organization: config.organization, repository: config.repository)
        let runnerGroupArgument = config.runnerGroup.map { " --runnergroup \(Self.shellQuote($0))" } ?? ""
        return [
            "rm -rf ~/actions-runner && mkdir ~/actions-runner",
            "tar xzf ~/\(Self.tarballRemotePath) -C ~/actions-runner",
            "echo \"Runner extracted\"",
            "~/actions-runner/config.sh --url \(url) --name \(runnerName) --token \(runnerToken) --ephemeral --unattended --replace --labels \(labels)\(runnerGroupArgument)",
            "echo \"Runner configured, starting ~/actions-runner/run.sh\"",
            "~/actions-runner/run.sh"
        ]
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
