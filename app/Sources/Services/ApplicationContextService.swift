import AppKit

struct ApplicationContextService: ApplicationContextProviding {
    private static let keynoteBundleIdentifier = "com.apple.iWork.Keynote"

    func currentContext() -> ApplicationContext {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.keynoteBundleIdentifier
            ? .keynote
            : .standard
    }
}
