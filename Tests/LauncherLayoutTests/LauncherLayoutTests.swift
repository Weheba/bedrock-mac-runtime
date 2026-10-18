import AppKit
import SwiftUI
import XCTest
@testable import MinecraftMacLauncher

final class LauncherLayoutTests: XCTestCase {
    @MainActor
    func testExpandedContentDoesNotChangeColumnMinimumSize() {
        // Mirrors the controls inserted by Advanced, including a long path.
        // No AppModel, real library, account, or game process is involved.
        let host = NSHostingView(rootView: detail(expanded: false))
        for expanded in [false, true, false, true] {
            host.rootView = detail(expanded: expanded)
            // Expanded controls must not contribute a column minimum.
            XCTAssertEqual(host.fittingSize, NSSize(width: 10, height: 10))
            for size in [NSSize(width: 630, height: 650), NSSize(width: 1100, height: 850)] {
                host.frame.size = size
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.frame.size, size)
                XCTAssertTrue(host.constraints.allSatisfy { $0.constant.isFinite })
            }
        }
    }

    @MainActor
    private func detail(expanded: Bool) -> some View {
        LauncherDetailViewport {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Minecraft")
                    if expanded {
                        GroupBox("Microsoft package account") {
                            VStack {
                                LabeledContent("Account", value: "Not checked")
                                HStack {
                                    Button("Sign In") {}
                                    Button("Check Ownership / Updates") {}
                                    Button("Sign Out…") {}
                                }
                                Text(String(repeating: "/long-installation-path", count: 30))
                                    .textSelection(.enabled)
                            }
                        }
                        ForEach(0..<20) { _ in Text("Storage and maintenance") }
                    }
                }
            }
        }
    }
}
