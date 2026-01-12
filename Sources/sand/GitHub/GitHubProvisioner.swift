import Foundation

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
    func script(config: GitHubProvisionerConfig, runnerToken: String, downloadURL: URL) -> String {
        let labels = labelsString(extraLabels: config.extraLabels)
        let url = runnerURL(organization: config.organization, repository: config.repository)
        return [
            "curl -so actions-runner.tar.gz -L \(downloadURL.absoluteString)",
            "rm -rf ~/actions-runner && mkdir ~/actions-runner",
            "tar xzf ./actions-runner.tar.gz -C ~/actions-runner",
            "~/actions-runner/config.sh --url \(url) --name \(config.runnerName) --token \(runnerToken) --ephemeral --unattended --replace --labels \(labels)",
            "~/actions-runner/run.sh"
        ].joined(separator: "\n")
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
