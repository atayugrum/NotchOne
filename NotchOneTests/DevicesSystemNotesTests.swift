import Foundation
import Testing
@testable import NotchOne

struct DeviceBatteryTests {
    private func device(_ name: String, _ levels: [DeviceBattery.Part: Int]) -> DeviceBattery {
        DeviceBattery(name: name, symbol: "airpods", levels: levels)
    }

    @Test func lowestIgnoresTheCaseUnlessItsAllThereIs() {
        #expect(device("AirPods", [.left: 80, .right: 60, .case: 10]).lowest == 60)
        #expect(device("Case only", [.case: 40]).lowest == 40)
        #expect(device("Mouse", [.single: 55]).lowest == 55)
    }

    @Test func sourcesMergeByNameAndLowestComesFirst() {
        let merged = DeviceBatteryLogic.merge([
            [device("Magic Mouse", [.single: 90]), device("Empty", [:])],
            [device("AirPods Pro", [.left: 30, .right: 35]), device("Magic Mouse", [.single: 10])],
        ])
        #expect(merged.map(\.name) == ["AirPods Pro", "Magic Mouse"])
        // The first source's reading wins for the same part.
        #expect(merged[1].levels[.single] == 90)
    }

    @Test func lowBatteryWarnsOnceUntilCharged() {
        var warned: Set<String> = []
        var result = DeviceBatteryLogic.lowWarnings([device("Mouse", [.single: 15])], warned: warned)
        #expect(result.warn.map(\.name) == ["Mouse"])
        warned = result.warned
        result = DeviceBatteryLogic.lowWarnings([device("Mouse", [.single: 12])], warned: warned)
        #expect(result.warn.isEmpty)
        // Charged past 30: it may warn again next time.
        result = DeviceBatteryLogic.lowWarnings([device("Mouse", [.single: 45])], warned: result.warned)
        #expect(result.warned.isEmpty)
    }

    @Test func readsMacOSBluetoothReport() {
        // Shaped like `system_profiler SPBluetoothDataType -json` on a Turkish Mac.
        let report = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Alex's AirPods Pro":{"device_batteryLevelCase":"%81","device_batteryLevelLeft":"%80","device_batteryLevelRight":"%80","device_minorType":"Headphones"}},
          {"AULA SC620":{"device_minorType":"Mouse"}},
          {"AULA-F99Pro 5.0 ":{"device_batteryLevelMain":"100%","device_minorType":"Keyboard"}}
        ],"device_not_connected":[{"Old":{"device_batteryLevelMain":"50%"}}]}]}
        """
        let devices = DeviceBatteryLogic.devices(fromBluetoothReport: Data(report.utf8))
        #expect(devices.map(\.name) == ["AirPods Pro", "AULA-F99Pro 5.0"])
        #expect(devices[0].levels == [.left: 80, .right: 80, .case: 81])
        #expect(devices[0].lowest == 80)
        #expect(devices[0].symbol == "airpodspro")
        #expect(devices[1].levels == [.single: 100])
        #expect(devices[1].symbol == "keyboard.fill")
        #expect(DeviceBatteryLogic.devices(fromBluetoothReport: Data("nope".utf8)).isEmpty)
    }

    @Test func ownerNamesAreLeftOut() {
        #expect(DeviceBatteryLogic.displayName("Alex's AirPods Pro 3") == "AirPods Pro 3")
        #expect(DeviceBatteryLogic.displayName("Alex’s Magic Mouse") == "Magic Mouse")
        #expect(DeviceBatteryLogic.displayName("AULA-F99Pro 5.0 ") == "AULA-F99Pro 5.0")
        // Only a single word before 's counts as an owner.
        #expect(DeviceBatteryLogic.displayName("Kid's Room Speaker's Remote") == "Room Speaker's Remote")
        #expect(DeviceBatteryLogic.displayName("Bose QC45") == "Bose QC45")
    }

    @Test func percentReadsAnyFormat() {
        #expect(DeviceBatteryLogic.percent("80%") == 80)
        #expect(DeviceBatteryLogic.percent("%80") == 80)
        #expect(DeviceBatteryLogic.percent("80 %") == 80)
        #expect(DeviceBatteryLogic.percent("") == nil)
    }

    @Test func impossibleLevelsAreDropped() {
        #expect(DeviceBatteryLogic.clamp(0) == nil)
        #expect(DeviceBatteryLogic.clamp(101) == nil)
        #expect(DeviceBatteryLogic.clamp(42) == 42)
    }
}

struct SystemMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func counters(busy: UInt64, total: UInt64, used: UInt64 = 4, inB: UInt64, outB: UInt64, at seconds: Double) -> SystemCounters {
        SystemCounters(cpuBusy: busy, cpuTotal: total, memoryUsed: used, memoryTotal: 16, bytesIn: inB, bytesOut: outB, diskFree: 1_000, time: t0 + seconds)
    }

    @Test func ratesComeFromTheDifference() {
        let sample = SystemMonitorLogic.sample(
            from: counters(busy: 100, total: 400, inB: 1_000, outB: 500, at: 0),
            to: counters(busy: 150, total: 600, used: 8, inB: 3_000, outB: 1_500, at: 2)
        )
        #expect(sample.cpu == 0.25)
        #expect(sample.memory == 0.5)
        #expect(sample.download == 1_000)
        #expect(sample.upload == 500)
    }

    @Test func aCounterResetIsNoTraffic() {
        let sample = SystemMonitorLogic.sample(
            from: counters(busy: 0, total: 0, inB: 9_000, outB: 9_000, at: 0),
            to: counters(busy: 0, total: 0, inB: 10, outB: 10, at: 1)
        )
        #expect(sample.download == 0)
        #expect(sample.cpu == 0)
    }

    @Test func noTrafficIsANumber() {
        #expect(SystemMonitorLogic.rate(0).first?.isNumber == true)
    }

    @Test func historyKeepsTheLastMinute() {
        var history: [Double] = []
        for value in 0..<75 { history = SystemMonitorLogic.append(Double(value), to: history) }
        #expect(history.count == SystemMonitorLogic.historyLength)
        #expect(history.last == 74)
    }

    @Test func thisMacsCountersAreReadable() {
        let counters = SystemCounterReader.read()
        #expect(counters.cpuTotal > 0)
        #expect(counters.memoryTotal > 0)
        #expect(counters.memoryUsed > 0 && counters.memoryUsed <= counters.memoryTotal)
    }

    @Test func sparklinePutsTheNewestOnTheRight() {
        let points = Sparkline.points([0, 0.5, 1], maximum: 1, size: CGSize(width: 118, height: 20))
        #expect(points.last?.x == 118)
        #expect(points.last?.y == 0)
        #expect(points.first?.y == 20)
    }
}

@MainActor
struct NotesStoreTests {
    @Test func notesSaveAndComeBack() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)/Notes.txt")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NotesStore(fileURL: url)
        #expect(store.isEmpty)
        store.text = "\n  Buy milk\nCall Ada"
        store.saveNow()
        #expect(store.firstLine == "Buy milk")
        #expect(NotesStore(fileURL: url).text == "\n  Buy milk\nCall Ada")
    }

    @Test func savingWaitsForAPauseInTyping() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)/Notes.txt")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NotesStore(fileURL: url)
        store.text = "draft"
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try await Task.sleep(for: .milliseconds(900))
        #expect((try? String(contentsOf: url, encoding: .utf8)) == "draft")
    }
}
