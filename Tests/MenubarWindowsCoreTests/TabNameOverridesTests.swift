// TabNameOverridesTests: the custom tab name rules, and how a name shows in the tab label.

import Testing
@testable import MenubarWindowsCore

@Suite("Custom tab names")
struct TabNameOverridesTests {
    @Test func renameAndLookup() {
        var names = TabNameOverrides()
        #expect(names.name(for: 7) == nil)
        let changed = names.rename(7, to: "Inbox")
        #expect(changed)
        #expect(names.name(for: 7) == "Inbox")
        #expect(names.name(for: 8) == nil)
    }

    @Test func blankInputResets() {
        var names = TabNameOverrides()
        names.rename(7, to: "Inbox")
        let removed = names.rename(7, to: "   \n  ")
        #expect(removed)
        #expect(names.name(for: 7) == nil)
        let nothingToDo = names.rename(7, to: "")
        #expect(!nothingToDo)
    }

    @Test func trimsAndFlattensToOneLine() {
        #expect(TabNameOverrides.clean("  Work\nmail  ") == "Work mail")
        #expect(TabNameOverrides.clean("\t\n ") == nil)
    }

    @Test func sameNameChangesNothing() {
        var names = TabNameOverrides()
        names.rename(7, to: "Inbox")
        let changed = names.rename(7, to: "  Inbox ")
        #expect(!changed)
        #expect(names.name(for: 7) == "Inbox")
    }

    @Test func resetRemovesOnlyThatWindow() {
        var names = TabNameOverrides()
        names.rename(7, to: "A")
        names.rename(8, to: "B")
        names.reset(7)
        #expect(names.name(for: 7) == nil)
        #expect(names.name(for: 8) == "B")
    }

    @Test func pruneDropsClosedWindows() {
        var names = TabNameOverrides()
        names.rename(7, to: "A")
        names.rename(8, to: "B")
        names.prune(keeping: [8, 9])
        #expect(names.name(for: 7) == nil)
        #expect(names.name(for: 8) == "B")
    }
}

@Suite("Custom tab name in the label")
struct CustomNameLabelTests {
    @Test func customNameReplacesTheLabelInTextModes() {
        for mode in [TabLabelMode.appName, .windowTitle, .appAndTitle] {
            #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: mode, customName: "Lists") == "Lists")
        }
    }

    @Test func iconOnlyStaysEmpty() {
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .iconOnly, customName: "Lists") == "")
    }

    @Test func customNameIsTruncatedLikeAnyLabel() {
        let text = TabLabel.text(appName: "A", title: "", mode: .appName, customName: String(repeating: "x", count: 80))
        #expect(text.count == TabLabel.maximumLength)
        #expect(text.hasSuffix("…"))
    }

    @Test func withoutACustomNameTheLabelIsUnchanged() {
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .windowTitle, customName: nil) == "Groceries")
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .appAndTitle) == "Notes: Groceries")
    }

    @Test func prefillStartsFromTheCustomName() {
        let prefill = TabLabel.renamePrefill(appName: "Notes", title: "Groceries", mode: .appAndTitle, customName: "Lists")
        #expect(prefill == "Lists")
    }

    @Test func prefillIsUntruncated() {
        // The prompt must not start from a shortened label with an ellipsis, or Enter would keep the cut text.
        let long = String(repeating: "w", count: 60)
        let prefill = TabLabel.renamePrefill(appName: "App", title: long, mode: .windowTitle, customName: nil)
        #expect(prefill == long)
    }

    @Test func prefillInIconOnlyUsesTheAccessibilityText() {
        let prefill = TabLabel.renamePrefill(appName: "Notes", title: "Groceries", mode: .iconOnly, customName: nil)
        #expect(prefill == "Notes, Groceries")
    }
}
