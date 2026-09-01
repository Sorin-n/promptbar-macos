import AppKit
import CoreText
import SwiftUI

public struct PromptBarTheme {
    public let isDark: Bool
    public let fontMode: FontMode
    public let headerUsesSurfaceBand: Bool
    public let background: Color
    public let sidebarBackground: Color
    public let secondarySidebarBackground: Color
    public let surface: Color
    public let outline: Color
    public let separator: Color
    public let navigationDivider: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let hover: Color
    public let selection: Color
    public let bearAccent: Color
    public let galaxyPrimary: Color
    public let galaxySecondary: Color
    public let galaxyGlow: Color

    public static func resolve(for mode: ThemeMode, fontMode: FontMode, systemScheme: ColorScheme) -> PromptBarTheme {
        FontAssetRegistry.shared.prepare()
        let resolvedMode = switch mode {
        case .dark:
            ThemeMode.dark
        case .light:
            ThemeMode.light
        case .softRose:
            ThemeMode.softRose
        case .solitudeBlue:
            ThemeMode.solitudeBlue
        case .system:
            ThemeMode.light
        }

        if resolvedMode == .dark {
            return PromptBarTheme(
                isDark: true,
                fontMode: fontMode,
                headerUsesSurfaceBand: false,
                background: Color(red: 0.078, green: 0.078, blue: 0.082),
                sidebarBackground: Color(red: 0.118, green: 0.118, blue: 0.122),
                secondarySidebarBackground: Color(red: 0.132, green: 0.132, blue: 0.137),
                surface: Color(red: 0.102, green: 0.102, blue: 0.106),
                outline: Color(red: 0.34, green: 0.34, blue: 0.37).opacity(0.55),
                separator: Color(red: 0.40, green: 0.40, blue: 0.43).opacity(0.22),
                navigationDivider: Color(red: 0.56, green: 0.56, blue: 0.60).opacity(0.16),
                textPrimary: Color(red: 0.93, green: 0.92, blue: 0.90),
                textSecondary: Color(red: 0.74, green: 0.73, blue: 0.71),
                textTertiary: Color(red: 0.52, green: 0.52, blue: 0.55),
                hover: Color.white.opacity(0.05),
                selection: Color.white.opacity(0.08),
                bearAccent: Color(red: 0.74, green: 0.73, blue: 0.71).opacity(0.11),
                galaxyPrimary: Color(red: 0.82, green: 0.80, blue: 0.86).opacity(0.22),
                galaxySecondary: Color(red: 0.60, green: 0.58, blue: 0.66).opacity(0.16),
                galaxyGlow: Color(red: 0.95, green: 0.94, blue: 0.98).opacity(0.16)
            )
        }

        if resolvedMode == .solitudeBlue {
            return solitudeBlueTheme(fontMode: fontMode)
        }

        if resolvedMode == .softRose {
            return PromptBarTheme(
                isDark: false,
                fontMode: fontMode,
                headerUsesSurfaceBand: true,
                background: Color(red: 0.995, green: 0.992, blue: 0.991),
                sidebarBackground: Color(red: 0.945, green: 0.902, blue: 0.920),
                secondarySidebarBackground: Color(red: 0.953, green: 0.919, blue: 0.934),
                surface: Color(red: 0.971, green: 0.936, blue: 0.949),
                outline: Color(red: 0.80, green: 0.73, blue: 0.77).opacity(0.36),
                separator: Color(red: 0.82, green: 0.77, blue: 0.79).opacity(0.20),
                navigationDivider: Color(red: 0.80, green: 0.73, blue: 0.77).opacity(0.18),
                textPrimary: Color(red: 0.24, green: 0.21, blue: 0.23),
                textSecondary: Color(red: 0.47, green: 0.41, blue: 0.44),
                textTertiary: Color(red: 0.68, green: 0.61, blue: 0.65),
                hover: Color(red: 0.42, green: 0.28, blue: 0.34).opacity(0.05),
                selection: Color(red: 0.42, green: 0.28, blue: 0.34).opacity(0.072),
                bearAccent: Color(red: 0.80, green: 0.69, blue: 0.74).opacity(0.22),
                galaxyPrimary: .clear,
                galaxySecondary: .clear,
                galaxyGlow: .clear
            )
        }

        return PromptBarTheme(
            isDark: false,
            fontMode: fontMode,
            headerUsesSurfaceBand: false,
            background: Color(red: 0.978, green: 0.968, blue: 0.948),
            sidebarBackground: Color(red: 0.954, green: 0.943, blue: 0.918),
            secondarySidebarBackground: Color(red: 0.965, green: 0.955, blue: 0.932),
            surface: Color(red: 0.993, green: 0.989, blue: 0.982),
            outline: Color(red: 0.68, green: 0.69, blue: 0.82).opacity(0.5),
            separator: Color(red: 0.76, green: 0.74, blue: 0.7).opacity(0.26),
            navigationDivider: Color(red: 0.67, green: 0.66, blue: 0.72).opacity(0.18),
            textPrimary: Color(red: 0.17, green: 0.15, blue: 0.13),
            textSecondary: Color(red: 0.42, green: 0.38, blue: 0.33),
            textTertiary: Color(red: 0.62, green: 0.58, blue: 0.53),
            hover: Color.black.opacity(0.022),
            selection: Color.black.opacity(0.03),
            bearAccent: Color(red: 0.74, green: 0.69, blue: 0.64).opacity(0.3),
            galaxyPrimary: .clear,
            galaxySecondary: .clear,
            galaxyGlow: .clear
        )
    }

    public static func resolveWorkspace(
        workspaceMode: WorkspaceThemeMode,
        primaryMode: ThemeMode,
        fontMode: FontMode,
        systemScheme: ColorScheme
    ) -> PromptBarTheme {
        return resolve(
            for: workspaceMode.resolvedThemeMode(fallback: primaryMode),
            fontMode: fontMode,
            systemScheme: systemScheme
        )
    }

    private static func solitudeBlueTheme(fontMode: FontMode) -> PromptBarTheme {
        FontAssetRegistry.shared.prepare()
        return PromptBarTheme(
            isDark: true,
            fontMode: fontMode,
            headerUsesSurfaceBand: false,
            background: Color(red: 0.050, green: 0.090, blue: 0.158),
            sidebarBackground: Color(red: 0.072, green: 0.114, blue: 0.184).opacity(0.82),
            secondarySidebarBackground: Color(red: 0.086, green: 0.132, blue: 0.214).opacity(0.78),
            surface: Color(red: 0.160, green: 0.248, blue: 0.372).opacity(0.60),
            outline: Color(red: 0.77, green: 0.85, blue: 0.96).opacity(0.22),
            separator: Color(red: 0.78, green: 0.87, blue: 0.98).opacity(0.12),
            navigationDivider: Color(red: 0.74, green: 0.83, blue: 0.95).opacity(0.14),
            textPrimary: Color(red: 0.94, green: 0.97, blue: 1.00),
            textSecondary: Color(red: 0.76, green: 0.84, blue: 0.93),
            textTertiary: Color(red: 0.58, green: 0.67, blue: 0.80),
            hover: Color.white.opacity(0.05),
            selection: Color(red: 0.72, green: 0.84, blue: 1.0).opacity(0.10),
            bearAccent: Color(red: 0.69, green: 0.82, blue: 0.98).opacity(0.18),
            galaxyPrimary: Color(red: 0.56, green: 0.72, blue: 0.97).opacity(0.32),
            galaxySecondary: Color(red: 0.31, green: 0.52, blue: 0.83).opacity(0.24),
            galaxyGlow: Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.24)
        )
    }

    public func titleFont(size: CGFloat) -> Font {
        switch fontMode {
        case .standard:
            return .custom("Times New Roman", size: size)
        case .drunkRiverGrass:
            return customFont(named: FontAssetRegistry.shared.drunkRiverGrassName, size: size, fallback: .custom("Times New Roman", size: size))
        case .telma:
            return customFont(named: FontAssetRegistry.shared.telmaName, size: size, fallback: .custom("Times New Roman", size: size))
        }
    }

    public func navigationFont(size: CGFloat) -> Font {
        switch fontMode {
        case .standard:
            return .custom("Songti SC", size: size)
        case .drunkRiverGrass:
            return customFont(named: FontAssetRegistry.shared.drunkRiverGrassName, size: size, fallback: .custom("Songti SC", size: size))
        case .telma:
            return customFont(named: FontAssetRegistry.shared.telmaName, size: size, fallback: .custom("Songti SC", size: size))
        }
    }

    public func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch fontMode {
        case .standard:
            return .system(size: size, weight: weight)
        case .drunkRiverGrass:
            return customFont(named: FontAssetRegistry.shared.drunkRiverGrassName, size: size, fallback: .system(size: size, weight: weight))
        case .telma:
            return customFont(named: FontAssetRegistry.shared.telmaName, size: size, fallback: .system(size: size, weight: weight))
        }
    }

    private func customFont(named name: String?, size: CGFloat, fallback: Font) -> Font {
        guard let name else { return fallback }
        return .custom(name, size: size)
    }
}

public extension WorkspaceThemeMode {
    func resolvedThemeMode(fallback: ThemeMode) -> ThemeMode {
        switch self {
        case .followPrimary:
            fallback == .system ? .light : fallback
        case .light:
            .light
        case .dark:
            .dark
        case .softRose:
            .softRose
        case .solitudeBlue:
            .solitudeBlue
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .followPrimary:
            nil
        case .light:
            .light
        case .dark:
            .dark
        case .softRose:
            .light
        case .solitudeBlue:
            .dark
        }
    }

    func nsAppearance(fallback: ThemeMode) -> NSAppearance? {
        resolvedThemeMode(fallback: fallback).nsAppearance
    }
}

public final class FontAssetRegistry: @unchecked Sendable {
    public static let shared = FontAssetRegistry()

    public private(set) var drunkRiverGrassName: String?
    public private(set) var telmaName: String?

    private var didPrepare = false

    private init() {}

    public func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        drunkRiverGrassName = registerFont(
            resource: "YeZiGongChangZuiHanJiangXingCao-2",
            ext: "ttf",
            preferredName: "YEFONTZuiHanJiangXingCao-Regular",
            legacySubdirectory: "Fonts"
        )
        telmaName = registerFont(
            resource: "Telma-Variable",
            ext: "ttf",
            preferredName: "Telma-Variable-Black_Regular",
            legacySubdirectory: "Fonts"
        )
    }

    private func registerFont(resource: String, ext: String, preferredName: String, legacySubdirectory: String) -> String? {
        guard let url = Bundle.module.promptBarResourceURL(
            forResource: resource,
            withExtension: ext,
            legacySubdirectory: legacySubdirectory
        ) else {
            return nil
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return nil
        }

        let availableNames = descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
        }

        if availableNames.contains(preferredName) {
            return preferredName
        }

        for postScriptName in availableNames {
            return postScriptName
        }

        for descriptor in descriptors {
            if let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                return postScriptName
            }
        }

        return nil
    }
}

extension Bundle {
    func promptBarResourceURL(forResource resource: String, withExtension ext: String, legacySubdirectory: String) -> URL? {
        if let rootURL = url(forResource: resource, withExtension: ext) {
            return rootURL
        }

        return url(forResource: resource, withExtension: ext, subdirectory: legacySubdirectory)
    }
}

public extension ThemeMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            .light
        case .light:
            .light
        case .dark:
            .dark
        case .softRose:
            .light
        case .solitudeBlue:
            .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            NSAppearance(named: .aqua)
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .softRose:
            NSAppearance(named: .aqua)
        case .solitudeBlue:
            NSAppearance(named: .darkAqua)
        }
    }
}
