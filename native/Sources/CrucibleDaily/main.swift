import CrucibleCore
// Foundation for the clock and for writing files. The engine imports neither; this is a tool that runs on a machine,
// not shipped code.
import Foundation

// Draws the day's world without a phone.
//
// ## What this is for
//
// Everybody who opens the lab on a given day gets the same starting world, chosen by hashing the date. That is the one
// thing in the app that is shared, and up to now the only way to see it was to open the app — so nobody could look at
// tomorrow's, nobody could put a picture of today's anywhere, and nobody could tell whether a change had quietly
// altered what a given day produces.
//
// This renders it: the same engine, the same chooser, the same colours, out as a picture. A machine runs it once a day
// on a timer and publishes the result, and no phone is involved at any point.
//
//   swift run -c release crucible-daily --out pictures
//   swift run -c release crucible-daily --day 2026-12-25 --out pictures --scale 3
//
// ## Why it prints what it chose
//
// The picture alone cannot be checked. The name of the scene, the arrangement, and the hash they both came from can be —
// they are the same three things the app puts on its chip, so a mismatch between this and a phone is visible rather
// than a matter of opinion.

/// One argument's value, if it was given.
func option(_ name: String) -> String? {
    guard let at = CommandLine.arguments.firstIndex(of: "--\(name)"), at + 1 < CommandLine.arguments.count else {
        return nil
    }
    let value = CommandLine.arguments[at + 1]
    return value.hasPrefix("--") ? nil : value
}

/// Today, as the day-chooser wants it.
func today() -> String {
    var calendar = Calendar(identifier: .gregorian)
    // The same day everywhere, so two machines in different places publish the same world. Local midnight would give
    // Auckland one world and Los Angeles another, and the whole point is that it is shared.
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: Date())
    let year = parts.year ?? 2_026
    let month = parts.month ?? 1
    let day = parts.day ?? 1
    return String(format: "%04d-%02d-%02d", year, month, day)
}

/// Whether a day reads as a date at all, so a typo produces a complaint rather than a picture of the wrong world.
func looksLikeADay(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
    guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
    return year >= 1_970 && year <= 9_999 && month >= 1 && month <= 12 && day >= 1 && day <= 31
}

let day = option("day") ?? today()
guard looksLikeADay(day) else {
    FileHandle.standardError.write(Data("that is not a date: \(day) — wanted YYYY-MM-DD\n".utf8))
    exit(2)
}

let folder = option("out") ?? "."
let scale = max(1, Int(option("scale") ?? "") ?? 2)
// Long enough that a scene has done something — lava has run, snow has landed, the dam has given way — and short
// enough that a fire has not finished eating everything. Four seconds of world.
let steps = max(0, Int(option("steps") ?? "") ?? 240)

// The proportions of a phone held upright, at the coarseness the app uses for a full-screen world.
let powderWidth = Int(option("width") ?? "") ?? 220
let powderHeight = Int(option("height") ?? "") ?? 470

// MARK: The powder world

let powder = PowderEngine(width: powderWidth, height: powderHeight, seed: DailyWorld.hash(forDay: day))
let powderChoice = DailyWorld.applyPowder(forDay: day, to: powder)
for _ in 0 ..< steps { powder.step() }

// MARK: The field

// At the powder world's own size, then enlarged the same amount, so the two pictures come out the same shape and can
// sit side by side.
let field = ParticleEngine(width: Double(powderWidth), height: Double(powderHeight))
let fieldChoice = DailyWorld.applyParticle(forDay: day, to: field)
for _ in 0 ..< steps { field.step() }

// MARK: Out

let out = URL(fileURLWithPath: folder, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("could not make \(folder): \(error)\n".utf8))
    exit(1)
}

/// Writes one picture, and says so, so the log shows what was produced rather than only that it finished.
func write(_ bytes: [UInt8]?, named name: String) {
    guard let bytes else {
        FileHandle.standardError.write(Data("nothing to write for \(name)\n".utf8))
        exit(1)
    }
    let at = out.appendingPathComponent(name)
    do {
        try Data(bytes).write(to: at)
        print("  \(name) — \(bytes.count) bytes")
    } catch {
        FileHandle.standardError.write(Data("could not write \(name): \(error)\n".utf8))
        exit(1)
    }
}

print("The world for \(day)")
print("  powder: \(powderChoice.name)")
print("  field: \(fieldChoice.name)")
print("  hash: \(powderChoice.hash)")
print("  after \(steps) moments, enlarged \(scale)×")
print("  \(field.particles.count) bodies, drawn \(field.particleSize) across")
write(powder.pngBytes(scale: scale), named: "powder-\(day).png")
write(powder.pngBytes(overlay: .temperature, scale: scale), named: "powder-heat-\(day).png")
write(field.pngBytes(scale: scale), named: "field-\(day).png")

// A caption beside the pictures, in the words the app itself uses, so whoever publishes them does not have to invent
// any. Plain text rather than anything structured: it is meant to be read.
let caption = """
    The world for \(day)

    Powder: \(powderChoice.name)
    Field: \(fieldChoice.name)

    Everybody who opens the lab today starts from this. The scene was chosen by hashing the date — \
    \(powderChoice.hash) — so it is the same for everyone, everywhere, and it changes tomorrow.

    The pictures are the world after \(steps) moments of running, at \(powderWidth) by \(powderHeight) cells enlarged \
    \(scale) times. One shows it as it looks; the other shows how hot everything is. The third is the particle field's \
    arrangement, one dot a body.

    Drawn by a machine from the simulation itself. No phone was involved.
    """
do {
    try Data(caption.utf8).write(to: out.appendingPathComponent("caption-\(day).txt"))
    print("  caption-\(day).txt")
} catch {
    FileHandle.standardError.write(Data("could not write the caption: \(error)\n".utf8))
    exit(1)
}
