/// Saving, loading, and the compact format used to sync two players' worlds.
///
/// ## Two formats, for two different jobs
///
/// ``PowderState`` is the full-fidelity one, used for scene files and autosaves. It
/// carries the element in every cell, its temperature and its remaining lifetime, plus
/// the world's settings.
///
/// ``PowderLiteState`` carries only the layout, one byte per cell, and is what goes over
/// the network many times a second. Temperatures and lifetimes are rebuilt on arrival
/// from each element's own defaults, because sending them would multiply the payload by
/// seven for information that reconverges within a few ticks anyway.
///
/// Both use the field names the web implementation uses, so a scene saved in a browser
/// opens in the app and two players on different versions can still see the same world.
///
/// ## Why these types are `Codable` rather than producing JSON directly
///
/// The engine imports nothing — not even Foundation — so that the physics compiles and
/// is tested on any machine, with no Apple frameworks involved. `Codable` is part of the
/// standard library; `JSONEncoder` is not. So the shape of the data and every validation
/// rule live here, and turning it into bytes is left to whoever owns the file or the
/// socket. That also means the same structures can go into a different container later —
/// a binary one, say — without touching any of the rules below.
///
/// ## The rules are the interesting part
///
/// Everything here is reading data the simulation did not produce: a file someone
/// hand-edited, an autosave from a build that crashed halfway through writing it, a
/// packet from a peer running a different version. Each loader either applies the whole
/// thing or refuses it and leaves the world alone. Half-applying is what turns a bad
/// file into a world that looks loaded and is quietly wrong.

// MARK: - The full-fidelity format

/// A whole powder world, as saved to a file.
///
/// Momentum, the pressure field and the per-tick visited marks are deliberately absent,
/// exactly as in ``PowderHistory.Snapshot``: they regenerate within a tick or two, and
/// carrying them would multiply the size of every save for something nobody can see.
public struct PowderState: Codable, Sendable {
    public var width: Int
    public var height: Int
    public var gridType: [ElementID]
    public var gridTemp: [Float]
    public var gridLife: [UInt16]
    public var gravityX: Double
    public var gravityY: Double
    public var windX: Double
    public var ambientTemp: Double

    public init(
        width: Int,
        height: Int,
        gridType: [ElementID],
        gridTemp: [Float],
        gridLife: [UInt16],
        gravityX: Double,
        gravityY: Double,
        windX: Double,
        ambientTemp: Double
    ) {
        self.width = width
        self.height = height
        self.gridType = gridType
        self.gridTemp = gridTemp
        self.gridLife = gridLife
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.windX = windX
        self.ambientTemp = ambientTemp
    }
}

/// The compact layout-only format used for live multiplayer sync.
public struct PowderLiteState: Codable, Sendable {
    /// Width. Named `w` to match the wire format.
    public var w: Int
    public var h: Int
    /// One byte per cell, base64 encoded.
    public var t: String
    public var gx: Double?
    public var gy: Double?

    public init(w: Int, h: Int, t: String, gx: Double? = nil, gy: Double? = nil) {
        self.w = w
        self.h = h
        self.t = t
        self.gx = gx
        self.gy = gy
    }
}

// MARK: - Base64

/// Base64, implemented here rather than borrowed from Foundation.
///
/// The engine deliberately has no dependencies, and this has to be byte-for-byte
/// identical to what a browser produces or the two cannot exchange worlds at all.
enum Base64 {
    private static let alphabet: [UInt8] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
    )

    /// Decoding table: the value of each ASCII byte, or -1 if it is not a base64 digit.
    private static let reverse: [Int8] = {
        var table = [Int8](repeating: -1, count: 256)
        for (index, character) in alphabet.enumerated() {
            table[Int(character)] = Int8(index)
        }
        return table
    }()

    static func encode(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count + 2) / 3 * 4)

        var index = 0
        while index + 2 < bytes.count {
            let word = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            out.append(alphabet[(word >> 18) & 0x3F])
            out.append(alphabet[(word >> 12) & 0x3F])
            out.append(alphabet[(word >> 6) & 0x3F])
            out.append(alphabet[word & 0x3F])
            index += 3
        }
        // The tail, padded to a multiple of four with '='.
        let remaining = bytes.count - index
        if remaining == 1 {
            let word = Int(bytes[index]) << 16
            out.append(alphabet[(word >> 18) & 0x3F])
            out.append(alphabet[(word >> 12) & 0x3F])
            out.append(UInt8(ascii: "="))
            out.append(UInt8(ascii: "="))
        } else if remaining == 2 {
            let word = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8
            out.append(alphabet[(word >> 18) & 0x3F])
            out.append(alphabet[(word >> 12) & 0x3F])
            out.append(alphabet[(word >> 6) & 0x3F])
            out.append(UInt8(ascii: "="))
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Decodes, or returns `nil` for anything that is not valid base64.
    ///
    /// Returning `nil` rather than throwing or guessing matters: this is fed straight
    /// from the network, and the callers use the failure to mean "that packet carried
    /// nothing", which is the only safe reading of a message that cannot be understood.
    static func decode(_ text: String) -> [UInt8]? {
        var accumulator = 0
        var bitsHeld = 0
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count / 4 * 3)

        for byte in text.utf8 {
            if byte == UInt8(ascii: "=") { break }
            // Whitespace is tolerated, as every base64 reader does.
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { continue }
            let value = reverse[Int(byte)]
            if value < 0 { return nil }
            accumulator = accumulator << 6 | Int(value)
            bitsHeld += 6
            if bitsHeld >= 8 {
                bitsHeld -= 8
                out.append(UInt8((accumulator >> bitsHeld) & 0xFF))
            }
        }
        return out
    }
}

// MARK: - Engine support

extension PowderEngine {
    /// The largest a world may be along either side.
    ///
    /// Note this bounds each side, not the area: the largest permitted world is over
    /// sixty-seven million cells, which is more than a gigabyte of grid. Anything
    /// wanting to offer that as a choice needs its own, tighter limit.
    public static let maximumDimension = 8192

    /// Whether a pair of dimensions can be used.
    public static func isValidSize(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maximumDimension && height <= maximumDimension
            && width * height <= maximumCells
    }

    /// The most cells a loaded world may have.
    ///
    /// Four million: more than one cell per pixel of the largest phone screen, and a quarter of a gigabyte
    /// less than the eight thousand by eight thousand the side limit alone allowed. A save file or a packet
    /// from another phone of a few bytes could ask for sixty-seven million cells, over a gigabyte, and the
    /// phone would stop the app to get the memory back.
    public static let maximumCells = 4_000_000

    /// Gravity from a file or another phone, pulled into a range the physics can use.
    ///
    /// Tilt gives at most about one either way, and nothing in the interface goes past four. Ten leaves plenty
    /// of room for anything legitimate and none for a number that crashes the fingerprint or flings every
    /// grain out of the world on the first moment.
    static func usableGravity(_ value: Double) -> Double {
        max(-10, min(10, value))
    }

    /// One cell as the compact format carries it.
    ///
    /// A single byte per cell, so anything that does not fit becomes empty. Both the
    /// encoder and ``hashLite()`` go through here; when they disagreed, the fingerprint
    /// described a world the receiver could not build and sync never converged.
    static func liteByte(_ id: ElementID) -> UInt8 {
        id > 0 && id <= 255 ? UInt8(id) : UInt8(Element.empty)
    }

    // MARK: Full fidelity

    /// Captures the whole world.
    public func captureState() -> PowderState {
        PowderState(
            width: width,
            height: height,
            gridType: Array(UnsafeBufferPointer(start: type, count: cellCount)),
            gridTemp: Array(UnsafeBufferPointer(start: temperature, count: cellCount)),
            gridLife: Array(UnsafeBufferPointer(start: life, count: cellCount)),
            gravityX: gravityX,
            gravityY: gravityY,
            windX: windX,
            ambientTemp: ambientTemp
        )
    }

    /// Loads a whole world, validating every value on the way in.
    ///
    /// - Returns: whether it was loaded. `false` leaves the current world untouched.
    ///
    /// The size is checked before anything is written, and the resize is checked after.
    /// The declared width is what sets the length of each row, so applying the cells
    /// under a size that was never adopted lays every row down at the wrong offset — the
    /// whole world sliding diagonally, with nothing reported. That was a real bug, and it
    /// is why this returns a result at all.
    @discardableResult
    public func apply(_ state: PowderState) -> Bool {
        guard Self.isValidSize(width: state.width, height: state.height) else { return false }
        if state.width != width || state.height != height {
            resize(width: state.width, height: state.height)
            guard state.width == width, state.height == height else { return false }
        }

        // Before the grid is reset, because resetting fills every cell at the ambient temperature and a cell
        // with an unreadable saved temperature falls back to it — both used the previous world's ambient.
        if state.ambientTemp.isFinite { ambientTemp = state.ambientTemp }
        resetGrid()
        let count = min(cellCount, state.gridType.count)

        // Every value is checked. Scene files are user data: an element id of 9999 used
        // to sit in the grid behaving as air while counting as a real particle forever,
        // and a temperature that was not a number spread through heat diffusion until it
        // had poisoned the whole world.
        for i in 0 ..< count {
            let id = state.gridType[i]
            let usable = id <= Element.customIDEnd ? id : Element.empty
            type[i] = usable
            // Loading is the second of the two ways a portal can enter the grid. Noticed
            // here, inside a walk that was happening anyway, rather than by a separate
            // pass afterwards.
            if usable == Element.portalB { portalBMayExist = true }
        }
        let temperatureCount = min(count, state.gridTemp.count)
        for i in 0 ..< temperatureCount {
            let value = state.gridTemp[i]
            temperature[i] = value.isFinite ? value : JS.toFloat32(ambientTemp)
        }
        let lifeCount = min(count, state.gridLife.count)
        for i in 0 ..< lifeCount {
            life[i] = state.gridLife[i]
        }

        if state.gravityX.isFinite { gravityX = Self.usableGravity(state.gravityX) }
        if state.gravityY.isFinite { gravityY = Self.usableGravity(state.gravityY) }
        // Through the clamp, like every other writer.
        if state.windX.isFinite { setWind(state.windX) }
        return true
    }

    // MARK: Compact

    /// Lays a grid of one-byte-per-cell identifiers into the world, resizing first if needed.
    ///
    /// This is the shared body of every compact-format loader. ``apply(lite:)`` and
    /// ``apply(roomWorld:)`` differ *only* in how they get these bytes out of a payload —
    /// one from base64, one from a compressed binary frame — and everything that happens
    /// afterwards is identical.
    ///
    /// It lives in one place on purpose. The two loaders started life with a copy each,
    /// and every comment below marks a bug that was found once and would then have had to
    /// be fixed twice. That is the whole argument: this is the routine where getting it
    /// wrong produces a world that looks loaded and is quietly incorrect.
    ///
    /// - Returns: whether the world was adopted. `false` leaves it untouched.
    func adoptCompactCells(_ bytes: [UInt8], width newWidth: Int, height newHeight: Int) -> Bool {
        guard Self.isValidSize(width: newWidth, height: newHeight) else { return false }

        if newWidth != width || newHeight != height {
            resize(width: newWidth, height: newHeight)
            // Checked, not assumed. `resize` returns quietly when a size cannot be used,
            // and the declared width is what sets the length of a row — so laying the
            // cells down under a size that was never adopted puts every row at the wrong
            // offset, the whole world sliding diagonally, with nothing reported. That was
            // a real bug, and it is why this returns a result at all.
            guard newWidth == width, newHeight == height else { return false }
        }

        // Cleared only now that the payload is known to be usable. Clearing first meant a
        // single unreadable message — from a peer on a different version, or a packet that
        // arrived damaged — wiped the receiving player's world and left them staring at
        // nothing.
        resetGrid()
        let count = min(cellCount, bytes.count)
        for i in 0 ..< count {
            let id = ElementID(bytes[i])
            let usable = id <= Element.customIDEnd ? id : Element.empty
            type[i] = usable
            // Arriving over the wire is one of the ways a portal can enter the grid.
            // Noticed here, inside a walk that was happening anyway, rather than by a
            // separate pass afterwards.
            if usable == Element.portalB { portalBMayExist = true }
            // Every cell gets the temperature and lifetime its element should start with,
            // since the compact format carries neither — without that, incoming ice
            // landed at the temperature of the lava it replaced and melted on the spot,
            // and incoming fire arrived with no lifetime and vanished on the next tick.
            let physics = elements[usable]
            temperature[i] = JS.toFloat32(physics.usesAmbientTemp ? ambientTemp : physics.defaultTemp)
            // Clamped into range rather than converted blindly: a lifetime is a 16-bit
            // field and the registry's is a wider signed one, so an absurd value in a
            // custom element would otherwise trap here.
            life[i] = UInt16(max(0, min(Int32(UInt16.max), physics.decayTicks)))
        }
        return true
    }

    /// Captures just the layout, for sending to another player.
    public func captureLiteState() -> PowderLiteState {
        var bytes = [UInt8](repeating: 0, count: cellCount)
        for i in 0 ..< cellCount { bytes[i] = Self.liteByte(type[i]) }
        return PowderLiteState(
            w: width,
            h: height,
            t: Base64.encode(bytes),
            gx: gravityX,
            gy: gravityY
        )
    }

    /// Adopts a layout from another player.
    ///
    /// - Returns: whether it was applied.
    ///
    /// The payload is decoded *before* the world is cleared. Clearing first meant a
    /// single unreadable message — from a peer on a different version, or a packet that
    /// arrived damaged — wiped the receiving player's world and left them staring at
    /// nothing.
    @discardableResult
    public func apply(lite state: PowderLiteState) -> Bool {
        guard let bytes = Base64.decode(state.t) else { return false }
        guard adoptCompactCells(bytes, width: state.w, height: state.h) else { return false }
        if let gx = state.gx, gx.isFinite { gravityX = Self.usableGravity(gx) }
        if let gy = state.gy, gy.isFinite { gravityY = Self.usableGravity(gy) }
        return true
    }
}
