import Foundation

public enum ProjectSupport {
    public static let repository = URL(string: "https://github.com/rafaelreverberi/Minecraft-on-Mac")!
    public static func issueURL(errorCode: String? = nil) -> URL {
        // Only a bounded event code is prefilled; never include error messages,
        // account identifiers, paths, game output, or diagnostic attachments.
        let code = errorCode.flatMap { value in
            !value.isEmpty && value.count <= 64 && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") } ? value : nil
        }
        var url = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "title", value: code.map { "[Bug] \($0)" } ?? "[Bug] Describe the problem"),
            .init(name: "body", value: """
            What happened?

            Steps to reproduce:
            1.

            Expected behavior:

            Launcher version:
            macOS version:
            Game and version:
            \(code.map { "Error code: \($0)" } ?? "")

            Please remove personal information before attaching screenshots or reports.
            """
            )
        ]
        return url.url!
    }
}
