import Testing

@testable import CrucibleCore

/// The note of what the world was doing.
@Suite("The note of what the world was doing")
struct LabBreadcrumbTests {
    @Test("The last things touched are kept and the oldest let go")
    func keepsTheLatest() {
        var note = LabBreadcrumb()
        for i in 1 ... LabBreadcrumb.mostActions + 15 {
            note.note("thing \(i)", secondsIn: Double(i))
        }
        #expect(note.actions.count == LabBreadcrumb.mostActions)
        #expect(note.actions.first?.what == "thing 16", "the wrong end was let go")
        #expect(note.actions.last?.what == "thing \(LabBreadcrumb.mostActions + 15)")
        // A time that is not a number cannot make a note unreadable.
        note.note("nonsense", secondsIn: .nan)
        #expect(note.actions.last?.secondsIn == 0)
    }

    @Test("A note that never finished is worth offering, and an empty or older one is not")
    func knowsABadEnding() {
        var note = LabBreadcrumb(seconds: 30)
        note.note("drew some sand", secondsIn: 4)
        #expect(note.describesABadEnding)

        var putAway = note
        putAway.endedCleanly = true
        #expect(!putAway.describesABadEnding, "a session put away properly was offered as a fault")

        var older = note
        older.version = LabBreadcrumb.currentVersion - 1
        #expect(!older.describesABadEnding, "a note of another shape was read anyway")

        // Nothing happened at all: opened and closed again within a second.
        let nothing = LabBreadcrumb(seconds: 0.5)
        #expect(!nothing.describesABadEnding)
    }

    @Test("The note reads as plain English, with what the world was and what was touched")
    func readsPlainly() {
        var note = LabBreadcrumb(
            appVersion: "0.1.0",
            build: "104",
            device: "iPhone 17 Pro Max",
            system: "iOS 26.1",
            seconds: 95
        )
        note.describe([
            LabBreadcrumb.Reading("Chamber", "Powder"),
            LabBreadcrumb.Reading("Grid", "420 × 910"),
        ])
        note.note("chose Lava", secondsIn: 61)
        note.note("opened the Field tray", secondsIn: 94.6)
        let text = note.text()
        #expect(text.hasPrefix("Crucible — what the world was doing\n"))
        #expect(text.contains("App 0.1.0 (build 104)"))
        #expect(text.contains("iPhone 17 Pro Max, iOS 26.1"))
        #expect(text.contains("Open for 1 minute 35 seconds"))
        #expect(text.contains("Did not finish"))
        #expect(text.contains("  Chamber: Powder"))
        #expect(text.contains("  Grid: 420 × 910"))
        #expect(text.contains("1 minute 1 second in — chose Lava"))
        #expect(text.contains("1 minute 35 seconds in — opened the Field tray"))
        #expect(text.hasSuffix("\n"))

        var putAway = note
        putAway.endedCleanly = true
        #expect(putAway.text().contains("Put away properly"))

        // An empty note still reads, rather than saying nothing at all.
        let empty = LabBreadcrumb()
        #expect(empty.text().contains("App unknown (build unknown)"))
        #expect(empty.text().contains("Open for 0 seconds"))
    }

    @Test("Lengths of time are said the way somebody would say them")
    func spellsTime() {
        #expect(LabBreadcrumb.spell(0) == "0 seconds")
        #expect(LabBreadcrumb.spell(1) == "1 second")
        #expect(LabBreadcrumb.spell(59.4) == "59 seconds")
        // Rounded up to the minute, which is how somebody would say it.
        #expect(LabBreadcrumb.spell(59.6) == "1 minute")
        #expect(LabBreadcrumb.spell(60) == "1 minute")
        #expect(LabBreadcrumb.spell(61) == "1 minute 1 second")
        #expect(LabBreadcrumb.spell(3_725) == "62 minutes 5 seconds")
        #expect(LabBreadcrumb.spell(.nan) == "0 seconds")
    }
}
