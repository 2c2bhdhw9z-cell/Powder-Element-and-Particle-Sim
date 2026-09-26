// Sending a whole world, often enough that sand appears to fall on both phones.
//
// ## The problem this exists to solve
//
// A follower cannot simulate for itself. The physics draws thousands of random numbers a tick from its
// own stream, so two engines stepping the same world diverge within a single frame — and that is not a
// flaw to be fixed, it is what makes the sand look like sand. So the host's world is the truth and the
// follower is *shown* it.
//
// That means the host has to send the world **continuously**, not once. Sand falls every tick; a
// follower that had received the world once and then only strokes would be watching a photograph.
//
// And a world is large. At the app's middle detail setting it is 150,000 cells, one byte each. Several
// times a second over a phone-to-phone link, that is megabytes a second — enough that the link becomes
// the bottleneck and the sand stutters anyway.
//
// ## Why run-length encoding, specifically
//
// A powder world is mostly air, in long horizontal runs. Encoding "how many, then which" instead of one
// byte per cell shrinks a typical world by a large factor, and it shrinks the *emptiest* worlds most —
// which is exactly the moment someone has just joined and is waiting to see anything at all.
//
// It is also honest about its worst case: a world where every cell differs from its neighbour encodes
// *larger* than the original. The codec notices that and sends the plain bytes instead, with a flag in
// the header, so the worst case is one byte of overhead rather than double the size.
//
// ## Why this is bytes rather than JSON
//
// Everything else a peer says is small and goes as JSON, where being able to read it is worth more than
// the bytes. This does not. It is the traffic that dominates the link, so it gets a binary frame:
//
//   - No base64. That inflates by a third, and here a third is tens of kilobytes per frame, dozens of
//     times a second, plus the processor time to encode and decode it on both phones for nothing.
//   - **The frame describes itself.** Width, height and gravity are in the header, so a frame is checked
//     against its own claims rather than against a size the receiver was told separately. The earlier
//     version took the expected cell count from a JSON field alongside the payload, which left room for
//     the header and the body to disagree — and a body laid down under the wrong row length shears the
//     entire world diagonally without reporting anything.
//   - A sequence number, so a frame that arrives after a newer one is dropped instead of showing the
//     past, and so the receiver can acknowledge frames and let the sender pace itself to the link.
//   - The host's fingerprint, so a follower can check the world it just built against the world the host
//     meant to send. That is a self-check on *this code*, not on the network, and it is precisely the
//     check that would have caught the fingerprint bug described in `RoomProtocol.swift` the first time
//     anyone shared a world.
//
// Nothing here is a general-purpose compressor. It is a few lines of arithmetic tuned to one shape of
// data, which is why it belongs in the engine where it can be measured against real worlds.

// MARK: - Reading and writing little-endian numbers

/// Byte order is written out by hand rather than reinterpreting memory.
///
/// Reinterpreting would make the frame mean different things on machines of different byte order. Both
/// ends are Apple hardware today; the frame format should not quietly depend on that.
private extension [UInt8] {
    /// Appends an integer, least significant byte first.
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var remaining = value
        for _ in 0 ..< (T.bitWidth / 8) {
            append(UInt8(truncatingIfNeeded: remaining))
            remaining >>= 8
        }
    }

    /// Reads an unsigned integer written least significant byte first.
    ///
    /// - Returns: the value, or `nil` if the frame is too short to contain one — which is the entire
    ///   point of returning an optional here. A truncated frame is the ordinary case on a bad link, not
    ///   an exceptional one.
    func littleEndianUnsigned<T: FixedWidthInteger & UnsignedInteger>(_: T.Type, at offset: Int) -> T? {
        let size = T.bitWidth / 8
        guard offset >= 0, offset <= count - size else { return nil }
        var value: T = 0
        var index = offset + size - 1
        while index >= offset {
            value = (value << 8) | T(self[index])
            index -= 1
        }
        return value
    }
}

// MARK: - The compression

/// Compressing a grid of element identifiers.
public enum RoomWorldCodec {
    /// The largest run one marker can describe.
    ///
    /// A byte, so 255. Longer runs are simply split, which costs two bytes per 255 cells — nothing
    /// against the saving.
    public static let maximumRun = 255

    /// Shrinks a grid of cell bytes.
    ///
    /// - Returns: the body to send, and whether it was worth encoding. When it was not, the body is the
    ///   original bytes and the caller records that in the frame's flags.
    ///
    /// Abandoned the moment it stops paying for itself, rather than finishing and then comparing. A world
    /// where no two neighbouring cells match would otherwise build an array twice the size of the world
    /// before throwing it away.
    public static func encodeBody(_ cells: [UInt8]) -> (body: [UInt8], runLengthEncoded: Bool) {
        guard !cells.isEmpty else { return ([], true) }

        var encoded: [UInt8] = []
        encoded.reserveCapacity(min(cells.count, 8192))

        var index = 0
        while index < cells.count {
            if encoded.count >= cells.count { return (cells, false) }
            let value = cells[index]
            var run = 1
            while index + run < cells.count,
                  cells[index + run] == value,
                  run < maximumRun {
                run += 1
            }
            encoded.append(UInt8(run))
            encoded.append(value)
            index += run
        }

        // Equal counts as "not worth it": the plain body decodes without doing any work.
        if encoded.count >= cells.count { return (cells, false) }
        return (encoded, true)
    }

    /// Expands what ``encodeBody(_:)`` produced.
    ///
    /// - Parameter expectedCount: how many cells the frame's own header says the world has. A body
    ///   describing a different number is refused rather than padded or truncated.
    /// - Returns: the cells, or `nil` if the body is unusable.
    public static func decodeBody(
        _ body: ArraySlice<UInt8>,
        runLengthEncoded: Bool,
        expectedCount: Int
    ) -> [UInt8]? {
        guard expectedCount >= 0 else { return nil }

        guard runLengthEncoded else {
            guard body.count == expectedCount else { return nil }
            return Array(body)
        }
        // Pairs of (count, value), so an odd length is a truncated or corrupt body.
        guard body.count % 2 == 0 else { return nil }

        var cells = [UInt8]()
        cells.reserveCapacity(expectedCount)
        var index = body.startIndex
        while index < body.endIndex {
            let run = Int(body[index])
            let value = body[body.index(after: index)]
            // A run of zero would make no progress and loop forever on a malformed body.
            guard run > 0 else { return nil }
            // Checked as it grows rather than at the end, so a body claiming far more cells than the
            // header allows cannot allocate its way to a crash before being rejected.
            guard cells.count + run <= expectedCount else { return nil }
            cells.append(contentsOf: repeatElement(value, count: run))
            index = body.index(index, offsetBy: 2)
        }
        guard cells.count == expectedCount else { return nil }
        return cells
    }
}

// MARK: - The frame

/// A whole world, packed small enough to send many times a second.
public struct RoomWorld: Sendable, Hashable {
    /// The frame format this build writes.
    ///
    /// A frame of any other version is refused outright. Guessing at a layout a future build invented is
    /// how a peer ends up displaying a world that was never sent.
    public static let version: UInt8 = 1

    /// version, flags, sequence, width, height, gravityX, gravityY, fingerprint.
    static let headerSize = 1 + 1 + 4 + 2 + 2 + 8 + 8 + 4

    /// Set when the body is run-length encoded.
    static let runLengthEncodedFlag: UInt8 = 1 << 0

    /// The most cells a frame may claim.
    ///
    /// ``PowderEngine/isValidSize(width:height:)`` bounds each side at 8192, which permits a world of
    /// sixty-seven million cells — far more than the app ever creates, and a large allocation to hand a
    /// stranger on the local network. The app's most detailed setting is 600,000 cells, so this is
    /// generous headroom and still bounds what one frame can ask for.
    public static let maximumCells = 4_000_000

    /// Which frame this is. Rises by one each time the host sends.
    public var sequence: UInt32
    public var width: Int
    public var height: Int
    public var gravityX: Double
    public var gravityY: Double
    /// The sender's ``PowderEngine/hashLite()`` for this world, for the receiver to check its own work.
    public var fingerprint: Int32
    /// One byte per cell, uncompressed. The compression happens in ``encoded()``.
    public var cells: [UInt8]

    public init(
        sequence: UInt32 = 0,
        width: Int,
        height: Int,
        gravityX: Double,
        gravityY: Double,
        fingerprint: Int32 = 0,
        cells: [UInt8]
    ) {
        self.sequence = sequence
        self.width = width
        self.height = height
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.fingerprint = fingerprint
        self.cells = cells
    }

    /// The bytes to put on the wire.
    ///
    /// - Returns: the frame, or `nil` for a world that cannot be represented — a size outside what the
    ///   header's fields hold, or a cell count that disagrees with the size. Failable rather than
    ///   clamping: a world that does not fit is a bug in the caller, and quietly sending a truncated
    ///   width would hand the receiver a sheared world that passes every check.
    public func encoded() -> [UInt8]? {
        guard PowderEngine.isValidSize(width: width, height: height) else { return nil }
        guard width * height <= Self.maximumCells else { return nil }
        guard cells.count == width * height else { return nil }

        let (body, runLengthEncoded) = RoomWorldCodec.encodeBody(cells)

        var frame: [UInt8] = []
        frame.reserveCapacity(Self.headerSize + body.count)
        frame.append(Self.version)
        frame.append(runLengthEncoded ? Self.runLengthEncodedFlag : 0)
        frame.appendLittleEndian(sequence)
        frame.appendLittleEndian(UInt16(width))
        frame.appendLittleEndian(UInt16(height))
        frame.appendLittleEndian(gravityX.bitPattern)
        frame.appendLittleEndian(gravityY.bitPattern)
        frame.appendLittleEndian(UInt32(bitPattern: fingerprint))
        frame.append(contentsOf: body)
        return frame
    }

    /// Reads a frame from the wire.
    ///
    /// - Returns: the world, or `nil` for anything that cannot be trusted. Every field is checked
    ///   against the others before a single cell is allocated, because this is the one place in the app
    ///   where bytes arrive from a device nobody controls.
    public static func decode(_ frame: [UInt8]) -> RoomWorld? {
        guard frame.count >= headerSize else { return nil }
        guard frame[0] == version else { return nil }

        let flags = frame[1]
        // An unrecognised flag means a newer build is describing the body in a way this one does not
        // understand. Refused, rather than read as though the flag were absent.
        guard flags & ~runLengthEncodedFlag == 0 else { return nil }
        let runLengthEncoded = flags & runLengthEncodedFlag != 0

        guard let sequence = frame.littleEndianUnsigned(UInt32.self, at: 2),
              let rawWidth = frame.littleEndianUnsigned(UInt16.self, at: 6),
              let rawHeight = frame.littleEndianUnsigned(UInt16.self, at: 8),
              let rawGravityX = frame.littleEndianUnsigned(UInt64.self, at: 10),
              let rawGravityY = frame.littleEndianUnsigned(UInt64.self, at: 18),
              let rawFingerprint = frame.littleEndianUnsigned(UInt32.self, at: 26)
        else { return nil }

        let width = Int(rawWidth)
        let height = Int(rawHeight)
        guard PowderEngine.isValidSize(width: width, height: height) else { return nil }
        let expectedCount = width * height
        guard expectedCount <= maximumCells else { return nil }

        guard let cells = RoomWorldCodec.decodeBody(
            frame[headerSize...],
            runLengthEncoded: runLengthEncoded,
            expectedCount: expectedCount
        ) else { return nil }

        return RoomWorld(
            sequence: sequence,
            width: width,
            height: height,
            gravityX: Double(bitPattern: rawGravityX),
            gravityY: Double(bitPattern: rawGravityY),
            fingerprint: Int32(bitPattern: rawFingerprint),
            cells: cells
        )
    }
}

// MARK: - The engine's side of it

extension PowderEngine {
    /// The world, ready to be packed and sent.
    ///
    /// Carries the same narrowed cell identifiers the compact save format uses, through
    /// ``PowderEngine/liteByte(_:)``, so the fingerprint and the payload agree about what a cell is.
    /// They once did not, and the drift check was permanently wrong as a result.
    public func captureRoomWorld(sequence: UInt32 = 0) -> RoomWorld {
        var bytes = [UInt8](repeating: 0, count: cellCount)
        for i in 0 ..< cellCount { bytes[i] = Self.liteByte(type[i]) }
        return RoomWorld(
            sequence: sequence,
            width: width,
            height: height,
            gravityX: gravityX,
            gravityY: gravityY,
            fingerprint: hashLite(),
            cells: bytes
        )
    }

    /// Adopts a world from the host.
    ///
    /// - Returns: whether it was applied. `false` leaves the current world untouched, decided before
    ///   anything is cleared — one unreadable message must not wipe the receiving player's world.
    ///
    /// Once this returns `true`, comparing ``hashLite()`` against the frame's
    /// ``RoomWorld/fingerprint`` says whether the world that was built is the world that was meant. A
    /// disagreement there is a fault in this code rather than on the link, since the frame arrived
    /// intact enough to decode.
    @discardableResult
    public func apply(roomWorld world: RoomWorld) -> Bool {
        guard Self.isValidSize(width: world.width, height: world.height) else { return false }
        guard world.cells.count == world.width * world.height else { return false }

        // Gravity before the cells. It changes nothing about how they are laid down, but it does feed
        // the fingerprint — and the caller compares fingerprints the moment this returns, so the world
        // has to be complete in every respect the fingerprint covers by then.
        let previousGravityX = gravityX
        let previousGravityY = gravityY
        if world.gravityX.isFinite { gravityX = Self.usableGravity(world.gravityX) }
        if world.gravityY.isFinite { gravityY = Self.usableGravity(world.gravityY) }

        guard adoptCompactCells(world.cells, width: world.width, height: world.height) else {
            // Put back, so a refused frame really does leave everything as it was.
            gravityX = previousGravityX
            gravityY = previousGravityY
            return false
        }
        return true
    }
}
