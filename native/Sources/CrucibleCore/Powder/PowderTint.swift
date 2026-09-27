/// Grains with a colour of their own: sand art, and a photograph turned into powder.
///
/// ## How a colour is kept
///
/// One word per cell in ``PowderEngine/tint``, packed exactly as the renderer packs a pixel — red in the lowest
/// byte, then green, then blue — with the top byte always full. Nought means the cell has no colour of its own and
/// is drawn in its material's colour. Because a real colour always has its top byte full, even pure black is not
/// nought, so no colour can be mistaken for "none".
///
/// ## What keeps a colour and what loses it
///
/// - Falling, flowing, being pushed, being carried by a belt or a portal: the colour goes with the grain.
/// - Becoming something else — sand melting into glass, water boiling away, a grain burnt to nothing — drops it,
///   because the new material is a new thing. Pink sand that melts is glass, not pink glass.
/// - Saving and undo keep it. A shared room does not: what travels between two phones is one small number per
///   cell, and a colour would be four more for every grain, many times a second. The other player sees the
///   material in its own colour.
///
/// Nothing in the physics reads a colour. It is carried, never consulted, so painting in colour cannot change how
/// anything behaves — a pink grain of sand falls exactly as a plain one does.
extension PowderEngine {
    /// A colour packed the way ``tint`` holds it.
    public static func tintWord(red: Int, green: Int, blue: Int) -> UInt32 {
        UInt32(UInt8(clamping: red)) | UInt32(UInt8(clamping: green)) << 8
            | UInt32(UInt8(clamping: blue)) << 16 | 0xFF00_0000
    }

    /// The colour a tint word holds, or nothing for nought.
    public static func tintChannels(_ word: UInt32) -> (red: Int, green: Int, blue: Int)? {
        guard word != 0 else { return nil }
        return (Int(word & 0xFF), Int((word >> 8) & 0xFF), Int((word >> 16) & 0xFF))
    }

    /// A cell's own colour, or nought if it has none or the point is outside the world.
    public func tintAt(_ x: Int, _ y: Int) -> UInt32 {
        isValid(x, y) ? tint[index(x, y)] : 0
    }

    /// Gives one cell a colour of its own, or takes it away again with nought.
    ///
    /// Air is left alone: there is nothing there to colour, and a colour left behind in an empty cell would turn
    /// up on whatever next fell into it.
    public func setTint(_ x: Int, _ y: Int, _ word: UInt32) {
        guard isValid(x, y) else { return }
        let i = index(x, y)
        guard type[i] != Element.empty else { return }
        if word == 0 {
            if tintMayExist { tint[i] = 0 }
            return
        }
        // The top byte is forced full, so a colour from anywhere — a file, a caller who packed it differently —
        // can never be read back as "none".
        tint[i] = word | 0xFF00_0000
        tintMayExist = true
    }

    /// How many cells have a colour of their own.
    public var tintedCellCount: Int {
        guard tintMayExist else { return 0 }
        var count = 0
        for i in 0 ..< cellCount where tint[i] != 0 { count += 1 }
        return count
    }

    // MARK: - In a saved world

    /// Every cell's colour as ``PowderState/gridTint`` holds it.
    func encodedTints() -> String {
        var bytes = [UInt8](repeating: 0, count: cellCount * 3)
        for i in 0 ..< cellCount {
            let word = tint[i]
            guard word != 0 else { continue }
            var red = UInt8(word & 0xFF)
            var green = UInt8((word >> 8) & 0xFF)
            var blue = UInt8((word >> 16) & 0xFF)
            // Pure black would read back as "no colour", so it is written a single step lighter.
            if red == 0 && green == 0 && blue == 0 { (red, green, blue) = (1, 1, 1) }
            bytes[i * 3] = red
            bytes[i * 3 + 1] = green
            bytes[i * 3 + 2] = blue
        }
        return Base64.encode(bytes)
    }

    /// Puts saved colours back on the grains they belong to. Call once the cells are down.
    ///
    /// - Parameter cells: how many cells the file said it held. The colours must describe exactly that many, or
    ///   they are describing some other world and are ignored rather than smeared across this one.
    ///
    /// A colour saved over air — which a hand-edited file could hold — is dropped rather than left waiting for the
    /// next thing to fall into that cell.
    func adoptTints(_ text: String, cells: Int) {
        guard let bytes = Base64.decode(text), bytes.count == cells * 3 else { return }
        for i in 0 ..< min(cellCount, cells) where type[i] != Element.empty {
            let red = bytes[i * 3]
            let green = bytes[i * 3 + 1]
            let blue = bytes[i * 3 + 2]
            guard red != 0 || green != 0 || blue != 0 else { continue }
            tint[i] = Self.tintWord(red: Int(red), green: Int(green), blue: Int(blue))
            tintMayExist = true
        }
    }

    // MARK: - A photograph as powder

    /// Which material one colour of a photograph becomes.
    ///
    /// The picture is made of real things that behave like what they look like: blue sky and sea become water and
    /// run, white becomes snow, fierce orange and red become lava — which really is hot, and really does set fire to
    /// what is beside it — and everything else is sand. Every grain keeps the colour of its own point of the picture
    /// whatever it is made of, so the picture is recognisable until it falls apart.
    ///
    /// The tests are strict on purpose. A face is pinkish orange, and loosening the lava test until skin qualified
    /// would pour lava down every portrait.
    public static func pictureMaterial(red: Int, green: Int, blue: Int) -> ElementID {
        if min(red, green, blue) >= 215 { return Element.snow }
        if red >= 190 && green <= 110 && blue <= 70 && red - green >= 100 { return Element.lava }
        if blue >= 110 && blue > red + 25 && blue >= green - 10 { return Element.water }
        return Element.sand
    }

    /// Lays a picture into the world, one grain for each point of it, sized to fit and centred.
    ///
    /// - Parameters:
    ///   - rgba: four bytes for each point — red, green, blue, and how solid it is — row by row from the top.
    ///   - pictureWidth: points across.
    ///   - pictureHeight: points down.
    ///   - fill: how much of the world the picture may take up, from a tenth to all of it. Its shape is kept, so it
    ///     fills this share of whichever way the world is tighter.
    /// - Returns: how many cells were placed. Nought for a picture that does not describe itself — a byte count
    ///   that does not match its size — rather than guessing where the rows start.
    ///
    /// Points that are mostly see-through are skipped, so a cut-out keeps its shape. Whatever is already in the
    /// world stays where the picture does not cover it; clearing first is the caller's decision.
    @discardableResult
    public func placePicture(rgba: [UInt8], width pictureWidth: Int, height pictureHeight: Int, fill: Double = 0.9) -> Int {
        guard width > 0, height > 0, pictureWidth > 0, pictureHeight > 0 else { return 0 }
        guard pictureWidth <= 100_000, pictureHeight <= 100_000,
              rgba.count == pictureWidth * pictureHeight * 4 else { return 0 }
        let share = fill.isFinite ? max(0.1, min(1, fill)) : 0.9
        let scale = min(Double(width) * share / Double(pictureWidth), Double(height) * share / Double(pictureHeight))
        let placedWidth = max(1, min(width, Int((Double(pictureWidth) * scale).rounded(.down))))
        let placedHeight = max(1, min(height, Int((Double(pictureHeight) * scale).rounded(.down))))
        let left = (width - placedWidth) / 2
        let top = (height - placedHeight) / 2

        var placed = 0
        for row in 0 ..< placedHeight {
            let fromY = min(pictureHeight - 1, row * pictureHeight / placedHeight)
            for column in 0 ..< placedWidth {
                let fromX = min(pictureWidth - 1, column * pictureWidth / placedWidth)
                let at = (fromY * pictureWidth + fromX) * 4
                guard rgba[at + 3] >= 128 else { continue }
                let red = Int(rgba[at])
                let green = Int(rgba[at + 1])
                let blue = Int(rgba[at + 2])
                let x = left + column
                let y = top + row
                setElement(x, y, Self.pictureMaterial(red: red, green: green, blue: blue))
                setTint(x, y, Self.tintWord(red: red, green: green, blue: blue))
                placed += 1
            }
        }
        return placed
    }
}
