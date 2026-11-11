import AppKit
import XCTest
@testable import WindowSplitter

final class SettingsStoreTests: XCTestCase {
    var store: SettingsStore!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsStoreTests")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        store = nil
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
        defaults = nil
        super.tearDown()
    }

    func test_defaultsLoadCorrectly() {
        for action in WindowAction.allCases {
            let binding = store.bindings[action]!
            XCTAssertEqual(binding.keyCode, action.defaultKeyCode)
            XCTAssertEqual(binding.modifiers, action.defaultModifiers)
            XCTAssertTrue(binding.enabled)
        }
    }

    func test_saveAndReload() {
        var disabled = store.bindings[.leftHalf]!
        disabled.enabled = false
        store.save(action: .leftHalf, binding: disabled)
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: Int(NSEvent.ModifierFlags.command.rawValue), enabled: false)
        store.save(action: .leftHalf, binding: newBinding)

        let reloadedStore = SettingsStore(defaults: defaults)
        let loaded = reloadedStore.bindings[.leftHalf]!
        XCTAssertEqual(loaded.keyCode, 99)
        XCTAssertEqual(loaded.modifiers, Int(NSEvent.ModifierFlags.command.rawValue))
        XCTAssertFalse(loaded.enabled)
    }

    func test_saveDoesNotAffectOtherActions() {
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: Int(NSEvent.ModifierFlags.option.rawValue), enabled: true)
        store.save(action: .leftHalf, binding: newBinding)

        let reloadedStore = SettingsStore(defaults: defaults)
        let rightHalf = reloadedStore.bindings[.rightHalf]!
        XCTAssertEqual(rightHalf.keyCode, WindowAction.rightHalf.defaultKeyCode)
        XCTAssertTrue(rightHalf.enabled)
    }

    func test_enabledBindings_excludesDisabled() {
        var binding = store.bindings[.leftHalf]!
        binding.enabled = false
        store.save(action: .leftHalf, binding: binding)

        let enabled = store.enabledBindings
        XCTAssertNil(enabled[.leftHalf])
        XCTAssertNotNil(enabled[.rightHalf])
    }

    func test_plainAndShiftOnlyProposalsDoNotOverwriteSavedShortcut() {
        for flags: NSEvent.ModifierFlags in [[], .shift, .capsLock, [.shift, .function]] {
            XCTAssertNotNil(store.save(action: .leftHalf, binding: ShortcutBinding(keyCode: 99, modifiers: Int(flags.rawValue), enabled: false)))
            XCTAssertEqual(store.bindings[.leftHalf]?.keyCode, 0)
            XCTAssertTrue(store.bindings[.leftHalf]!.enabled)
            XCTAssertNil(defaults.object(forKey: "leftHalf.keyCode"))
        }
    }

    func test_duplicateIncludingDisabledAndReservedProposalsAreRejected() {
        var disabled = store.bindings[.rightHalf]!
        disabled.enabled = false
        store.save(action: .rightHalf, binding: disabled)
        for key in [2, 49] {
            XCTAssertNotNil(store.save(action: .leftHalf, binding: ShortcutBinding(keyCode: key, modifiers: WindowAction.leftHalf.defaultModifiers, enabled: true)))
            XCTAssertEqual(store.bindings[.leftHalf]?.keyCode, 0)
            XCTAssertNil(defaults.object(forKey: "leftHalf.keyCode"))
        }
    }

    func test_newChordPreservesCurrentEnabledNotStaleProposal() {
        var disabled = store.bindings[.leftHalf]!
        disabled.enabled = false
        store.save(action: .leftHalf, binding: disabled)
        store.save(action: .leftHalf, binding: ShortcutBinding(keyCode: 99, modifiers: Int(NSEvent.ModifierFlags.control.rawValue), enabled: true))
        XCTAssertEqual(store.bindings[.leftHalf]?.keyCode, 99)
        XCTAssertFalse(store.bindings[.leftHalf]!.enabled)
        XCTAssertFalse(SettingsStore(defaults: defaults).bindings[.leftHalf]!.enabled)
    }

    func test_existingLegacyBindingsLoadAndCanToggleWithoutRevalidation() {
        defaults.set(99, forKey: "leftHalf.keyCode")
        defaults.set(123456, forKey: "leftHalf.modifiers")
        store = SettingsStore(defaults: defaults)
        var binding = store.bindings[.leftHalf]!
        XCTAssertEqual(binding.modifiers, 123456)
        binding.enabled = false
        store.save(action: .leftHalf, binding: binding)
        let reloaded = SettingsStore(defaults: defaults).bindings[.leftHalf]!
        XCTAssertEqual(reloaded.keyCode, 99)
        XCTAssertEqual(reloaded.modifiers, 123456)
        XCTAssertFalse(reloaded.enabled)
    }

    func test_incidentalFlagsAreNormalizedAndConflictsMatchNormalizedSavedBindings() {
        defaults.set(WindowAction.rightHalf.defaultModifiers | Int(NSEvent.ModifierFlags.capsLock.rawValue), forKey: "rightHalf.modifiers")
        store = SettingsStore(defaults: defaults)
        XCTAssertNotNil(store.save(action: .leftHalf, binding: ShortcutBinding(keyCode: 2, modifiers: WindowAction.leftHalf.defaultModifiers, enabled: true), recording: true))
        XCTAssertNil(store.save(action: .leftHalf, binding: ShortcutBinding(keyCode: 99, modifiers: Int(NSEvent.ModifierFlags([.command, .capsLock, .function]).rawValue), enabled: false), recording: true))
        XCTAssertEqual(store.bindings[.leftHalf]?.modifiers, Int(NSEvent.ModifierFlags.command.rawValue))
        XCTAssertTrue(store.bindings[.leftHalf]!.enabled)
    }
}
