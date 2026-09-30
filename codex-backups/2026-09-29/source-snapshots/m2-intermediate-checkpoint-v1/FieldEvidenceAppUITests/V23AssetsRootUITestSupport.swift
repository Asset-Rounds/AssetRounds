import XCTest

extension XCUIApplication {
    /// V23 replaced the S10 two-tab shell (Signs, Reports) with Today, Work, Assets and
    /// Reports. A fresh launch, and the rebuilt shell after Erase All, opens Today; a
    /// relaunch restores the last saved root. The released S10 Signs journeys (welcome,
    /// sign list and sign detail) live on Assets, which keeps the incumbent
    /// `s1.tab.signs` automation identity.
    ///
    /// S-class and S10-era UI tests call this before their unchanged wait for the first
    /// Signs-root screen, so each journey starts where it started in S10. Assets is
    /// tapped only when it is hittable and not already the visible root, so a restored
    /// Assets path is never popped. With `screen`, it also waits through a shell rebuild
    /// (an old Assets root still under the Erase All or restore sheet) until that screen
    /// shows or the rebuilt shell offers Assets. It asserts only that the Assets tab
    /// appeared; the caller's own screen wait remains the journey assertion.
    @MainActor
    func selectAssetsRootForS10Journey(
        awaiting screen: XCUIElement? = nil,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let assetsTab = descendants(matching: .any)
            .matching(identifier: "s1.tab.signs")
            .firstMatch
        let assetsRoot = descendants(matching: .any)
            .matching(identifier: "s1.shell.screen")
            .firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let screen, screen.exists {
                return
            }
            // One snapshot per poll: reading an attribute of a tab that a shell rebuild
            // just removed would fail the test instead of waiting for the new shell.
            if let tab = try? assetsTab.snapshot() {
                if !tab.isSelected && !assetsRoot.exists {
                    // A tab still covered by a dismissing sheet waits for the next poll.
                    if assetsTab.isHittable {
                        assetsTab.tap()
                        return
                    }
                } else if screen == nil {
                    return
                }
                _ = (screen ?? assetsRoot).waitForExistence(timeout: 1)
            } else {
                _ = assetsTab.waitForExistence(timeout: 1)
            }
        } while Date() < deadline
        if !assetsTab.exists {
            XCTFail(
                "The V23 Assets tab (s1.tab.signs) did not appear.",
                file: file,
                line: line
            )
        }
    }
}
