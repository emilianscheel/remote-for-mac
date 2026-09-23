import AppKit

struct ApplicationContextService: ApplicationContextProviding {
    private static let contextsByBundleIdentifier: [String: ApplicationContext] = [
        "com.apple.Keynote": .keynote,
        "com.apple.iWork.Keynote": .keynote,
        "com.microsoft.Powerpoint": .powerPoint,
        "com.apple.Preview": .preview,
        "com.apple.Safari": .safari,
        "com.figma.Desktop": .figma,
    ]

    func currentContext() -> ApplicationContext {
        Self.context(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    static func context(for bundleIdentifier: String?) -> ApplicationContext {
        guard let bundleIdentifier else { return .standard }
        return contextsByBundleIdentifier[bundleIdentifier] ?? .standard
    }
}
