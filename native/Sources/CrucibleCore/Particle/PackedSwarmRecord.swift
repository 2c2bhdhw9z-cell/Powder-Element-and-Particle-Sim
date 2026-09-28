/// A large crowd written as one versioned block instead of millions of JSON numbers.
///
/// Small, older saves use ``SwarmRecord`` and remain readable. Above that format's practical size this stores the
/// exact same arrays as little-endian bytes and base64 text, which JSON can carry without importing Foundation into
/// CrucibleCore. Nothing is shortened: the count in the header must agree with the exact byte length and checksum or
/// the whole record is refused before the live field is changed.
public struct PackedSwarmRecord: Codable, Sendable {
    public var version: Int
    public var n: Int
    public var flags: UInt16
    public var bytes: String
    public var checksum: UInt32

    private static let currentVersion = 1
    private static let hasMasses: UInt16 = 1 << 0
    private static let hasLives: UInt16 = 1 << 1
    private static let hasRoles: UInt16 = 1 << 2
    private static let hasSizes: UInt16 = 1 << 3
    private static let hasGroups: UInt16 = 1 << 4
    private static let hasDepth: UInt16 = 1 << 5
    private static let knownFlags = hasMasses | hasLives | hasRoles | hasSizes | hasGroups | hasDepth

    /// Captures every live body. No limit is accepted on purpose: a save is either exact or it is not a save.
    static func capture(_ swarm: Swarm, width: Double, height: Double, depthEnabled: Bool) -> Self {
        let count = swarm.count
        var flags: UInt16 = 0
        for index in 0 ..< count where swarm.masses[index] != 1 {
            flags |= hasMasses
            break
        }
        if swarm.hasMortalBodies { flags |= hasLives }
        if swarm.hasRoles { flags |= hasRoles }
        if swarm.hasSizes { flags |= hasSizes }
        if swarm.hasGroups { flags |= hasGroups }
        if depthEnabled, swarm.hasDepth { flags |= hasDepth }

        let stride = byteStride(flags: flags)
        var raw: [UInt8] = []
        raw.reserveCapacity(count * stride)

        @inline(__always)
        func appendUInt32(_ value: UInt32) {
            raw.append(UInt8(truncatingIfNeeded: value))
            raw.append(UInt8(truncatingIfNeeded: value >> 8))
            raw.append(UInt8(truncatingIfNeeded: value >> 16))
            raw.append(UInt8(truncatingIfNeeded: value >> 24))
        }
        @inline(__always)
        func appendFloat(_ value: Float) { appendUInt32(value.bitPattern) }

        let centreX = Float(width / 2)
        let centreY = Float(height / 2)
        for index in 0 ..< count {
            let at = index * 2
            appendFloat(swarm.positions[at].isFinite ? swarm.positions[at] : centreX)
            appendFloat(swarm.positions[at + 1].isFinite ? swarm.positions[at + 1] : centreY)
        }
        for index in 0 ..< count {
            let at = index * 2
            appendFloat(swarm.velocities[at].isFinite ? swarm.velocities[at] : 0)
            appendFloat(swarm.velocities[at + 1].isFinite ? swarm.velocities[at + 1] : 0)
        }
        for index in 0 ..< count { appendUInt32(swarm.colors[index]) }
        if flags & hasMasses != 0 {
            for index in 0 ..< count {
                let value = swarm.masses[index]
                appendFloat(value.isFinite && value > 0 ? value : 1)
            }
        }
        if flags & hasLives != 0 {
            for index in 0 ..< count {
                let value = swarm.lives[index]
                appendFloat(value.isFinite ? value : -1)
            }
            for index in 0 ..< count {
                let value = swarm.maxLives[index]
                appendFloat(value.isFinite && value > 0 ? value : 1)
            }
        }
        if flags & hasRoles != 0 {
            for index in 0 ..< count { raw.append(swarm.roles[index] & Swarm.Role.known) }
            for index in 0 ..< count * Swarm.homeStride {
                let value = swarm.homes[index]
                appendFloat(value.isFinite ? value : 0)
            }
        }
        if flags & hasSizes != 0 {
            for index in 0 ..< count {
                let value = swarm.sizes[index]
                appendFloat(value.isFinite ? max(0, min(400, value)) : 0)
            }
        }
        if flags & hasGroups != 0 {
            for index in 0 ..< count { raw.append(swarm.groups[index]) }
        }
        if flags & hasDepth != 0 {
            for index in 0 ..< count {
                let value = swarm.depths[index]
                appendFloat(value.isFinite ? value : 0)
            }
            for index in 0 ..< count {
                let value = swarm.depthVelocities[index]
                appendFloat(value.isFinite ? value : 0)
            }
            for index in 0 ..< count {
                let value = swarm.homeDepths[index]
                appendFloat(value.isFinite ? value : 0)
            }
        }

        return Self(
            version: currentVersion,
            n: count,
            flags: flags,
            bytes: ParticleBase64.encode(raw),
            checksum: Self.checksum(raw)
        )
    }

    /// Reads and validates the whole block. A bad count, flag, byte, length or checksum rejects all of it.
    func snapshot(width: Double, height: Double) -> Swarm.Snapshot? {
        guard version == Self.currentVersion, n >= 0, n <= Swarm.maximumCount, flags & ~Self.knownFlags == 0,
              let raw = ParticleBase64.decode(bytes), Self.checksum(raw) == checksum
        else { return nil }
        let stride = Self.byteStride(flags: flags)
        let (expected, overflow) = n.multipliedReportingOverflow(by: stride)
        guard !overflow, raw.count == expected else { return nil }

        var offset = 0
        @inline(__always)
        func readUInt32() -> UInt32 {
            defer { offset += 4 }
            return UInt32(raw[offset])
                | UInt32(raw[offset + 1]) << 8
                | UInt32(raw[offset + 2]) << 16
                | UInt32(raw[offset + 3]) << 24
        }
        @inline(__always)
        func readFloat() -> Float { Float(bitPattern: readUInt32()) }

        let reach = Float(max(width, height) * 4 + 1_000)
        func place(_ value: Float, fallback: Float) -> Float {
            value.isFinite ? max(-reach, min(reach, value)) : fallback
        }
        func speed(_ value: Float) -> Float {
            value.isFinite ? max(-10_000, min(10_000, value)) : 0
        }

        var result = Swarm.Snapshot(positions: [], velocities: [], colors: [])
        result.positions.reserveCapacity(n * 2)
        result.velocities.reserveCapacity(n * 2)
        result.colors.reserveCapacity(n)
        let centreX = Float(width / 2)
        let centreY = Float(height / 2)
        for _ in 0 ..< n {
            result.positions.append(place(readFloat(), fallback: centreX))
            result.positions.append(place(readFloat(), fallback: centreY))
        }
        for _ in 0 ..< n {
            result.velocities.append(speed(readFloat()))
            result.velocities.append(speed(readFloat()))
        }
        for _ in 0 ..< n { result.colors.append(readUInt32()) }
        if flags & Self.hasMasses != 0 {
            result.masses.reserveCapacity(n)
            for _ in 0 ..< n {
                let value = readFloat()
                result.masses.append(value.isFinite && value > 0 ? value : 1)
            }
        }
        if flags & Self.hasLives != 0 {
            result.lives.reserveCapacity(n)
            result.maxLives.reserveCapacity(n)
            for _ in 0 ..< n {
                let value = readFloat()
                result.lives.append(value.isFinite ? value : -1)
            }
            for _ in 0 ..< n {
                let value = readFloat()
                result.maxLives.append(value.isFinite && value > 0 ? value : 1)
            }
        }
        if flags & Self.hasRoles != 0 {
            result.roles.reserveCapacity(n)
            result.homes.reserveCapacity(n * Swarm.homeStride)
            for _ in 0 ..< n { result.roles.append(raw[offset] & Swarm.Role.known); offset += 1 }
            for _ in 0 ..< n * Swarm.homeStride {
                let value = readFloat()
                result.homes.append(value.isFinite ? max(-reach, min(reach, value)) : 0)
            }
        }
        if flags & Self.hasSizes != 0 {
            result.sizes.reserveCapacity(n)
            for _ in 0 ..< n {
                let value = readFloat()
                result.sizes.append(value.isFinite ? max(0, min(400, value)) : 0)
            }
        }
        if flags & Self.hasGroups != 0 {
            result.groups.reserveCapacity(n)
            for _ in 0 ..< n { result.groups.append(raw[offset]); offset += 1 }
        }
        if flags & Self.hasDepth != 0 {
            result.depths.reserveCapacity(n)
            result.depthVelocities.reserveCapacity(n)
            result.homeDepths.reserveCapacity(n)
            for _ in 0 ..< n { result.depths.append(place(readFloat(), fallback: 0)) }
            for _ in 0 ..< n { result.depthVelocities.append(speed(readFloat())) }
            for _ in 0 ..< n { result.homeDepths.append(place(readFloat(), fallback: 0)) }
        }
        guard offset == raw.count else { return nil }
        return result
    }

    private static func byteStride(flags: UInt16) -> Int {
        var bytes = 20 // x, y, vx, vy and colour.
        if flags & hasMasses != 0 { bytes += 4 }
        if flags & hasLives != 0 { bytes += 8 }
        if flags & hasRoles != 0 { bytes += 1 + 4 * Swarm.homeStride }
        if flags & hasSizes != 0 { bytes += 4 }
        if flags & hasGroups != 0 { bytes += 1 }
        if flags & hasDepth != 0 { bytes += 12 }
        return bytes
    }

    /// FNV-1a is small, deterministic and enough to distinguish a complete block from a cut or changed one.
    private static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in bytes {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

/// Standard base64 without Foundation, so the platform-independent engine stays platform-independent.
private enum ParticleBase64 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let decodeTable: [Int16] = {
        var table = [Int16](repeating: -1, count: 256)
        for (index, byte) in alphabet.enumerated() { table[Int(byte)] = Int16(index) }
        return table
    }()

    static func encode(_ input: [UInt8]) -> String {
        guard !input.isEmpty else { return "" }
        var output: [UInt8] = []
        output.reserveCapacity((input.count + 2) / 3 * 4)
        var index = 0
        while index + 2 < input.count {
            let value = UInt32(input[index]) << 16 | UInt32(input[index + 1]) << 8 | UInt32(input[index + 2])
            output.append(alphabet[Int((value >> 18) & 63)])
            output.append(alphabet[Int((value >> 12) & 63)])
            output.append(alphabet[Int((value >> 6) & 63)])
            output.append(alphabet[Int(value & 63)])
            index += 3
        }
        let remaining = input.count - index
        if remaining > 0 {
            var value = UInt32(input[index]) << 16
            if remaining == 2 { value |= UInt32(input[index + 1]) << 8 }
            output.append(alphabet[Int((value >> 18) & 63)])
            output.append(alphabet[Int((value >> 12) & 63)])
            output.append(remaining == 2 ? alphabet[Int((value >> 6) & 63)] : 61)
            output.append(61)
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func decode(_ text: String) -> [UInt8]? {
        let input = Array(text.utf8)
        guard input.count % 4 == 0 else { return nil }
        if input.isEmpty { return [] }
        var output: [UInt8] = []
        output.reserveCapacity(input.count / 4 * 3)
        var index = 0
        while index < input.count {
            let isLast = index + 4 == input.count
            let a = input[index]
            let b = input[index + 1]
            let c = input[index + 2]
            let d = input[index + 3]
            guard a != 61, b != 61,
                  let av = value(a), let bv = value(b),
                  (c != 61 || isLast), (d != 61 || isLast), !(c == 61 && d != 61)
            else { return nil }
            let cv = c == 61 ? 0 : value(c)
            let dv = d == 61 ? 0 : value(d)
            guard let cv, let dv else { return nil }
            let bits = UInt32(av) << 18 | UInt32(bv) << 12 | UInt32(cv) << 6 | UInt32(dv)
            output.append(UInt8((bits >> 16) & 255))
            if c != 61 { output.append(UInt8((bits >> 8) & 255)) }
            if d != 61 { output.append(UInt8(bits & 255)) }
            if (c == 61 || d == 61) && !isLast { return nil }
            index += 4
        }
        return output
    }

    @inline(__always)
    private static func value(_ byte: UInt8) -> UInt8? {
        let value = decodeTable[Int(byte)]
        return value >= 0 ? UInt8(value) : nil
    }
}
