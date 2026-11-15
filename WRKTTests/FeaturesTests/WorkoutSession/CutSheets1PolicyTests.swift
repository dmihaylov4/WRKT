import Testing
import UIKit
import SwiftUI
@testable import WRKT

@MainActor
@Suite(.serialized)
struct CutSheets1PolicyTests {
    @Test func kindsKeepBrowsersLargeAndConfirmWithoutClose() {
        #expect(CutSheetKind.choice.fitsContent)
        #expect(CutSheetKind.form.fitsContent)
        #expect(!CutSheetKind.browser.fitsContent)
        #expect(CutSheetKind.confirm.fitsContent)
        #expect(!CutSheetKind.confirm.showsClose)
        #expect(CutSheetKind.choice.showsClose)
        #expect(CutSheetKind.form.showsClose)
        #expect(CutSheetKind.browser.showsClose)
    }
    @Test func nestedSheetsUseRaisedLevels() {
        #expect(DS.Cut.SheetLevel.resolve(parentDepth: 0) == .base)
        #expect(DS.Cut.SheetLevel.resolve(parentDepth: 1) == .stacked)
        #expect(DS.Cut.SheetLevel.resolve(parentDepth: 2) == .nested)
        #expect(DS.Cut.SheetLevel.resolve(parentDepth: 4) == .nested)
    }
    @Test func contentFallsBackToLargeAtScreenLimit() {
        #expect(CutSheetSizing.resolve(parts: [80, 200, 80], screen: 844) == .fitted(360))
        #expect(CutSheetSizing.resolve(parts: [120, 900, 0], screen: 844) == .large)
        #expect(CutSheetSizing.resolve(parts: [80, 700], screen: 844) == .fitted(780))
        #expect(CutSheetSizing.resolve(parts: [80, 701], screen: 844) == .large)
    }
    @Test func pushedControllerDoesNotBecomeASheet() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let first = UIViewController()
        let nav = UINavigationController(rootViewController: first)
        await withCheckedContinuation { continuation in
            root.present(nav, animated: false) { continuation.resume() }
        }
        let sheetProbe = UIViewController(); first.addChild(sheetProbe)
        #expect(CutPresentationReader.Reader.isPresentationRoot(sheetProbe))
        let pushed = UIViewController(); nav.pushViewController(pushed, animated: false)
        let pushedProbe = UIViewController(); pushed.addChild(pushedProbe)
        #expect(!CutPresentationReader.Reader.isPresentationRoot(pushedProbe))
        #expect(!CutPresentationReader.Reader.isPresentationRoot(root))
        await withCheckedContinuation { continuation in
            nav.dismiss(animated: false) { continuation.resume() }
        }
    }
    @Test func detectsSwiftUISheetAndItsPushedDestination() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        var readings: [String: Bool] = [:]
        window.rootViewController = UIHostingController(rootView: CutSheets1NavigationFixture { readings[$0] = $1 })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .seconds(2))
        #expect(readings["root"] == true)
        #expect(readings["push"] == false)
    }

}


@MainActor
private struct CutSheets1NavigationFixture: View {
    let record: (String, Bool) -> Void
    @State private var path: [String] = []
    var body: some View {
        Text("Fixture presenter").sheet(isPresented: .constant(true)) {
            NavigationStack(path: $path) {
                Text("Fixture root").background(CutPresentationReader { record("root", $0) })
                    .navigationDestination(for: String.self) { _ in
                        Text("Fixture push").background(CutPresentationReader { record("push", $0) })
                    }
                    .task { try? await Task.sleep(for: .milliseconds(700)); path = ["push"] }
            }
        }
    }
}
