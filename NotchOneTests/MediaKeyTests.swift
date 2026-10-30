import AppKit
import Testing
@testable import NotchOne

struct MediaKeyParserTests {
    /// Builds `data1` the way the system does: key code in the high 16 bits,
    /// state (0xA down / 0xB up) in bits 8–15, repeat flag in bit 0.
    private func data1(_ key: MediaKey, down: Bool, repeating: Bool = false) -> Int {
        (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8) | (repeating ? 1 : 0)
    }

    @Test func parsesVolumeUpDown() {
        let event = MediaKeyParser.parse(subtype: 8, data1: data1(.soundUp, down: true))
        #expect(event == MediaKeyEvent(key: .soundUp, isDown: true, isRepeat: false))
    }

    @Test func parsesKeyUpAndRepeat() {
        #expect(MediaKeyParser.parse(subtype: 8, data1: data1(.brightnessDown, down: false))?.isDown == false)
        #expect(MediaKeyParser.parse(subtype: 8, data1: data1(.mute, down: true, repeating: true))?.isRepeat == true)
    }

    @Test func ignoresOtherSubtypesAndKeys() {
        #expect(MediaKeyParser.parse(subtype: 7, data1: data1(.soundUp, down: true)) == nil)
        // NX_KEYTYPE_PLAY (16) is not ours.
        #expect(MediaKeyParser.parse(subtype: 8, data1: (16 << 16) | (0xA << 8)) == nil)
        // Unknown state byte.
        #expect(MediaKeyParser.parse(subtype: 8, data1: (0 << 16) | (0x3 << 8)) == nil)
    }
}

struct LevelMathTests {
    @Test func stepsBySixteenths() {
        #expect(LevelMath.step(0.5, up: true, fine: false) == 0.5625)
        #expect(LevelMath.step(0.5, up: false, fine: false) == 0.4375)
    }

    @Test func fineStepsBySixtyFourths() {
        #expect(LevelMath.step(0.5, up: true, fine: true) == 0.5156)
    }

    @Test func snapsOffGridValuesFirst() {
        // 0.53 snaps to the nearest step (0.5), then steps.
        #expect(LevelMath.step(0.53, up: true, fine: false) == 0.5625)
        // 0.56 snaps to 0.5625, then steps down.
        #expect(LevelMath.step(0.56, up: false, fine: false) == 0.5)
    }

    @Test func clampsAtEnds() {
        #expect(LevelMath.step(1, up: true, fine: false) == 1)
        #expect(LevelMath.step(0, up: false, fine: false) == 0)
        #expect(LevelMath.step(.nan, up: true, fine: false) == 0.0625)
    }

    @Test @MainActor func symbolsExist() {
        let names = [
            LevelSymbols.volume(level: 0, muted: false),
            LevelSymbols.volume(level: 0.2, muted: false),
            LevelSymbols.volume(level: 0.5, muted: false),
            LevelSymbols.volume(level: 0.9, muted: false),
            LevelSymbols.volume(level: 0.9, muted: true),
            LevelSymbols.brightness(level: 0.2),
            LevelSymbols.brightness(level: 0.8),
        ]
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing \(name)")
        }
        #expect(LevelSymbols.volume(level: 0.9, muted: true) == "speaker.slash.fill")
    }

    @Test func levelPeeksGetWiderEars() {
        #expect(EarLayout.width(for: .peek(.volume(level: 0.5, muted: false))) == EarLayout.levelWidth)
        #expect(EarLayout.width(for: .peek(.brightness(level: 0.5))) == EarLayout.levelWidth)
        #expect(EarLayout.width(for: .peek(.bluetooth(symbol: "airpods", connected: true, battery: nil))) == EarLayout.peekWidth)
    }
}

struct BluetoothDeviceKindTests {
    @Test func namesWinOverClass() {
        #expect(BluetoothDeviceKind.symbol(name: "My AirPods Pro", majorClass: 0x04, minorClass: 0) == "airpodspro")
        #expect(BluetoothDeviceKind.symbol(name: "AirPods Max", majorClass: 0x04, minorClass: 0) == "airpodsmax")
        #expect(BluetoothDeviceKind.symbol(name: "AirPods", majorClass: 0x04, minorClass: 0) == "airpods")
    }

    @Test func classesMapToSymbols() {
        #expect(BluetoothDeviceKind.symbol(name: "Speaker", majorClass: 0x04, minorClass: 0) == "headphones")
        #expect(BluetoothDeviceKind.symbol(name: "MX", majorClass: 0x05, minorClass: 0x20) == "computermouse.fill")
        #expect(BluetoothDeviceKind.symbol(name: "Keys", majorClass: 0x05, minorClass: 0x10) == "keyboard.fill")
        #expect(BluetoothDeviceKind.symbol(name: "Pad", majorClass: 0x05, minorClass: 0x02) == "gamecontroller.fill")
        #expect(BluetoothDeviceKind.symbol(name: "?", majorClass: 0x1F, minorClass: 0) == "dot.radiowaves.left.and.right")
    }

    @Test @MainActor func allSymbolsExist() {
        let names = [
            "airpodsmax", "airpodspro", "airpods", "hand.point.up.left.fill", "headphones",
            "computermouse.fill", "keyboard.fill", "gamecontroller.fill", "iphone", "laptopcomputer",
            "dot.radiowaves.left.and.right", "checkmark.circle.fill", "xmark.circle.fill",
        ]
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing \(name)")
        }
    }
}
