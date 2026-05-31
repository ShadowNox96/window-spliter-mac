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

    func test_defaultsLoadCorrectly() {
        for action in WindowAction.allCases {
            let binding = store.bindings[action]!
            XCTAssertEqual(binding.keyCode, action.defaultKeyCode)
            XCTAssertEqual(binding.modifiers, action.defaultModifiers)
            XCTAssertTrue(binding.enabled)
        }
    }

    func test_saveAndReload() {
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: 123456, enabled: false)
        store.save(action: .leftHalf, binding: newBinding)

        let reloadedStore = SettingsStore(defaults: defaults)
        let loaded = reloadedStore.bindings[.leftHalf]!
        XCTAssertEqual(loaded.keyCode, 99)
        XCTAssertEqual(loaded.modifiers, 123456)
        XCTAssertFalse(loaded.enabled)
    }

    func test_saveDoesNotAffectOtherActions() {
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: 0, enabled: false)
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
}
