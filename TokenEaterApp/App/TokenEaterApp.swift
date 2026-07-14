import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var usageStore: UsageStore!
    var settingsStore: SettingsStore!
    var vendorStatusStore: VendorStatusStore!

    private var statusBarController: StatusBarController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        statusBarController = StatusBarController(
            usageStore: usageStore,
            settingsStore: settingsStore,
            vendorStatusStore: vendorStatusStore
        )
    }
}

@main
struct RaiUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let usageStore: UsageStore
    private let settingsStore: SettingsStore
    private let vendorStatusStore: VendorStatusStore

    init() {
        let tokenProvider = TokenProvider(
            oauthService: OAuthService(),
            oauthTokenStore: OAuthTokenStore()
        )
        self.usageStore = UsageStore(tokenProvider: tokenProvider)
        self.settingsStore = SettingsStore()
        self.vendorStatusStore = VendorStatusStore()

        NotificationService().setupDelegate()
        appDelegate.usageStore = usageStore
        appDelegate.settingsStore = settingsStore
        appDelegate.vendorStatusStore = vendorStatusStore
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
