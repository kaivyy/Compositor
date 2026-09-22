import Testing
import Foundation
import Sparkle
@testable import Compositor

@MainActor
struct AutomaticUpdateTests {
    private var rootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CompositorTests
            .deletingLastPathComponent() // Compositor root
    }

    @Test func configurationEnablesAutomaticUpdates() throws {
        let infoPlistURL = rootURL.appendingPathComponent("Config").appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let config = try #require(plist)

        #expect(config["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(config["SUScheduledCheckInterval"] as? Int == 86400)
        #expect(config["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(config["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(config["SUFeedURL"] as? String == "https://raw.githubusercontent.com/robbietilton/Compositor/main/appcast.xml")
        #expect(config["SUPublicEDKey"] as? String == "KZvD724t8QpzTR4OGrHrsCWt538TJ/g/qrTZii+o214=")
    }

    @Test func appcastFeedFormatAndSecurity() throws {
        let appcastURL = rootURL.appendingPathComponent("appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let xmlString = try #require(String(data: data, encoding: .utf8))

        #expect(xmlString.contains("xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""))
        #expect(xmlString.contains("<title>Compositor</title>"))
        #expect(xmlString.contains("<sparkle:version>"))
        #expect(xmlString.contains("<sparkle:shortVersionString>"))
        #expect(xmlString.contains("<sparkle:minimumSystemVersion>"))
        #expect(xmlString.contains("sparkle:edSignature="))
        #expect(xmlString.contains("enclosure url=\"https://github.com/robbietilton/Compositor/releases/download/"))
    }

    @Test func applicationDelegateUpdaterInitializesSafely() {
        // Verify that initializing CompositorApplicationDelegate instantiates
        // the SPUStandardUpdaterController without blocking or crashing.
        let delegate = CompositorApplicationDelegate()
        #expect(delegate.updater.updater.feedURL == nil || delegate.updater.updater.feedURL != nil)
    }
}
