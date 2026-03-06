import Carbon
import Testing
@testable import TypeThisPlease

struct HotKeyTests {
    @Test
    func defaultHotKeysProduceDisplayStringsWithoutCrashing() {
        #expect(HotKey.defaultRecording.displayString == "⇧⌘;")
        #expect(HotKey.defaultCheckpoint.displayString == "⇧⌘'")
    }

    @Test
    func alphanumericKeysUseExplicitVirtualKeyMapping() {
        let letter = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command])
        let digit = HotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: [.option, .shift])

        #expect(letter.displayString == "⌘A")
        #expect(digit.displayString == "⌥⇧7")
    }
}
