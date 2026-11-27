// OwnWindowRuleTests.swift
// Only the Settings window of this app becomes a tab. The strip panel and other own windows do not.

import Testing
@testable import MenubarWindowsCore

@Suite("Own windows")
struct OwnWindowRuleTests {
    @Test func settingsWindowIsATab() {
        #expect(OwnWindowRule.isTabWindow(identifier: OwnWindowRule.settingsIdentifier))
    }

    @Test func windowWithoutIdentifierIsNotATab() {
        #expect(!OwnWindowRule.isTabWindow(identifier: nil))
    }

    @Test func otherOwnWindowsAreNotTabs() {
        #expect(!OwnWindowRule.isTabWindow(identifier: ""))
        #expect(!OwnWindowRule.isTabWindow(identifier: "mw.onboarding"))
        #expect(!OwnWindowRule.isTabWindow(identifier: "mw.strip"))
    }

    @Test func identifierMatchIsExact() {
        #expect(!OwnWindowRule.isTabWindow(identifier: "MW.SETTINGS"))
        #expect(!OwnWindowRule.isTabWindow(identifier: "\(OwnWindowRule.settingsIdentifier)-extra"))
    }
}
