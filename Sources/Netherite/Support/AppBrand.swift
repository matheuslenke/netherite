import AppKit
import SwiftUI

enum AppBrand {
    static let displayName = "Netherite"
    static let logoResourceName = "NetheriteLogo"
    static let logoFileExtension = "png"
    static let vaultSupportDirectoryName = ".netherite"
    static let legacyVaultSupportDirectoryName = ".perfect-writing"
    static let ignoredVaultDirectoryNames: Set<String> = [
        ".git",
        vaultSupportDirectoryName,
        legacyVaultSupportDirectoryName
    ]

    private static let preferredFontNames = [
        "JetBrainsMono-Regular",
        "JetBrains Mono"
    ]

    static let logoImage: NSImage? = {
        for bundle in [Bundle.main, Bundle.module] {
            if let image = image(named: logoResourceName, in: bundle) {
                return image
            }
        }
        return nil
    }()

    static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontName = installedPreferredFontName {
            return .custom(fontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    private static let installedPreferredFontName: String? = {
        for name in preferredFontNames where NSFont(name: name, size: 12) != nil {
            return name
        }

        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: "JetBrains Mono") else {
            return nil
        }
        return members.compactMap { member in
            member.first as? String
        }.first
    }()

    private static func image(named name: String, in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: name, withExtension: logoFileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct BrandLogoView: View {
    var size: CGFloat

    var body: some View {
        logo
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .shadow(color: Color.purple.opacity(0.28), radius: size * 0.18, y: size * 0.07)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var logo: some View {
        if let image = AppBrand.logoImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(systemName: "diamond.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.purple)
            }
        }
    }
}
