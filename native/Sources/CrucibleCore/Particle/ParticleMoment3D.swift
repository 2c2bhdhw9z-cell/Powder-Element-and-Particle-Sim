// A 3D moment: the field as it is now, as a file any iPhone, iPad or Mac opens in 3D — turned in the hand, or stood in
// the room through the camera.
//
// ## What the file is
//
// A USDZ, which is what Apple's own Quick Look opens: a zip that is not compressed, holding one scene description
// written as plain text. Every body becomes a small solid — eight faces, enough to read as round at the size they are
// — and bodies of about the same colour are gathered into one shape with one material, sixteen colours at most,
// because that is what the viewers draw reliably: a colour given to each point separately is ignored by some of them.
//
// Written here rather than with Apple's own tools because those need a phone to run and this needs checking: the
// checks open the zip that comes out, find the text inside, and hold it to what the format requires. It has also been
// opened with Pixar's own USD library and passed through all twenty-eight of its validators, including the three for
// USDZ packages — which is how the missing declaration that each shape carries a material was found.
//
// ## Size
//
// About thirty centimetres across, so it sits on a table rather than filling the room, and at most six thousand
// bodies — a crowd of a hundred thousand is sampled evenly, since six thousand already reads as a crowd and a file of
// a hundred thousand solids is too large to send or to turn smoothly.

public enum USDZ {
    /// Packs files into a USDZ: a zip with nothing compressed, every file's contents starting on a sixty-four byte
    /// boundary, which the format requires so a reader can use them where they lie.
    public static func pack(_ files: [(name: String, data: [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for file in files {
            let name = Array(file.name.utf8)
            let crc = PNG.crc32(file.data)
            let offset = UInt32(out.count)
            // Where the contents would start with no padding, and how much padding puts them on a boundary. The
            // padding goes in the header's "extra" field, which is what readers skip.
            let headerSize = 30 + name.count
            let unpadded = out.count + headerSize + 4
            let padding = (64 - unpadded % 64) % 64
            let extraLength = 4 + padding
            // The local header.
            out += le32(0x0403_4B50)
            out += le16(10) // version needed
            out += le16(0) // flags
            out += le16(0) // stored, not compressed
            out += le16(0) + le16(0x21) // time, date: 1980-01-01
            out += le32(crc)
            out += le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            out += le16(UInt16(name.count)) + le16(UInt16(extraLength))
            out += name
            // An extra field of an unregistered kind, holding nothing but the padding.
            out += le16(0x1986) + le16(UInt16(padding))
            out += [UInt8](repeating: 0, count: padding)
            out += file.data
            // Its entry in the directory at the end.
            central += le32(0x0201_4B50)
            central += le16(10) + le16(10) + le16(0) + le16(0)
            central += le16(0) + le16(0x21)
            central += le32(crc)
            central += le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0)
            central += le16(0) + le16(0) + le32(0)
            central += le32(offset)
            central += name
        }
        let directoryAt = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50)
        out += le16(0) + le16(0)
        out += le16(UInt16(files.count)) + le16(UInt16(files.count))
        out += le32(UInt32(central.count)) + le32(directoryAt)
        out += le16(0)
        return out
    }

    static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
}

extension ParticleEngine {
    /// The most bodies a 3D moment holds.
    public static let momentMostBodies = 6_000
    /// How many colours it gathers the bodies into.
    public static let momentColours = 16

    /// One body in a moment: where, how big and what colour, in the world's pixels.
    struct MomentBody {
        var x: Double
        var y: Double
        var z: Double
        var radius: Double
        var colour: PackedColor
    }

    /// Every body worth putting in a moment: the object bodies, then the crowd sampled evenly up to the limit.
    func momentBodies(most: Int) -> [MomentBody] {
        var bodies: [MomentBody] = []
        for body in particles.prefix(most) {
            bodies.append(MomentBody(x: body.x, y: body.y, z: body.z, radius: max(1, body.radius), colour: body.color))
        }
        let room = most - bodies.count
        let crowd = swarm.count
        if room > 0, crowd > 0 {
            let stride = max(1, (crowd + room - 1) / room)
            let size = max(1.5, particleSize * 0.5)
            var index = 0
            while index < crowd, bodies.count < most {
                let x = Double(swarm.positions[index * 2])
                let y = Double(swarm.positions[index * 2 + 1])
                let z = storedDepthEnabled ? Double(swarm.depths[index]) : 0
                bodies.append(MomentBody(
                    x: x, y: y, z: z, radius: size, colour: PackedColor(packedRGBA: swarm.colors[index])
                ))
                index += stride
            }
        }
        return bodies.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }

    /// The field as it is now, as a USDZ file. See the note at the top of this file.
    public func moment3D(sizeInMetres: Double = 0.3) -> [UInt8] {
        let text = momentScene(sizeInMetres: sizeInMetres)
        return USDZ.pack([(name: "moment.usda", data: Array(text.utf8))])
    }

    /// The scene description inside a moment, as text.
    func momentScene(sizeInMetres: Double) -> String {
        let bodies = momentBodies(most: Self.momentMostBodies)
        // Metres per world pixel, from the wider of the world's two sides. Up is up: the world's rows count down the
        // screen, the file's up counts up from the table.
        let across = max(1, width, height)
        let scale = (sizeInMetres.isFinite && sizeInMetres > 0 ? sizeInMetres : 0.3) / across
        let middleX = width / 2
        let middleY = height / 2
        // Stood on the table: the lowest point of the lowest body at nought, however high in the world it was.
        let lowest = bodies.map { (middleY - $0.y - $0.radius) * scale }.min() ?? 0

        // Gathered by colour, sixteen at most: by hue, with the greys in one of their own.
        var groups: [Int: [MomentBody]] = [:]
        for body in bodies { groups[Self.colourGroup(body.colour), default: []].append(body) }

        var text = """
        #usda 1.0
        (
            defaultPrim = "Moment"
            metersPerUnit = 1
            upAxis = "Y"
            doc = "A moment of Crucible's particle field"
        )

        def Xform "Moment" (
            kind = "component"
        )
        {

        """
        for key in groups.keys.sorted() {
            guard let members = groups[key], !members.isEmpty else { continue }
            let colour = Self.averageColour(members.map(\.colour))
            var points: [String] = []
            var counts: [String] = []
            var indices: [String] = []
            points.reserveCapacity(members.count * 6)
            for (at, body) in members.enumerated() {
                let r = body.radius * scale
                let cx = (body.x - middleX) * scale
                let cy = (middleY - body.y) * scale - lowest
                let cz = body.z * scale
                // An octahedron: six corners, eight faces.
                let corners = [
                    (cx + r, cy, cz), (cx - r, cy, cz), (cx, cy + r, cz),
                    (cx, cy - r, cz), (cx, cy, cz + r), (cx, cy, cz - r),
                ]
                for corner in corners {
                    points.append("(\(Self.number(corner.0)), \(Self.number(corner.1)), \(Self.number(corner.2)))")
                }
                let base = at * 6
                let faces = [
                    (0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4),
                    (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5),
                ]
                for face in faces {
                    counts.append("3")
                    indices.append("\(base + face.0), \(base + face.1), \(base + face.2)")
                }
            }
            text += """
                def Mesh "Bodies\(key)" (
                    prepend apiSchemas = ["MaterialBindingAPI"]
                )
                {
                    int[] faceVertexCounts = [\(counts.joined(separator: ", "))]
                    int[] faceVertexIndices = [\(indices.joined(separator: ", "))]
                    point3f[] points = [\(points.joined(separator: ", "))]
                    uniform token subdivisionScheme = "none"
                    rel material:binding = </Moment/Colour\(key)>
                }

                def Material "Colour\(key)"
                {
                    token outputs:surface.connect = </Moment/Colour\(key)/Surface.outputs:surface>

                    def Shader "Surface"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (\(Self.number(colour.0)), \(Self.number(colour.1)), \(Self.number(colour.2)))
                        color3f inputs:emissiveColor = (\(Self.number(colour.0 * 0.35)), \(Self.number(colour.1 * 0.35)), \(Self.number(colour.2 * 0.35)))
                        float inputs:roughness = 0.5
                        token outputs:surface
                    }
                }


            """
        }
        text += "}\n"
        return text
    }

    /// Which of the sixteen colour groups a colour goes in: fifteen slices of the colour wheel, and one for greys.
    static func colourGroup(_ colour: PackedColor) -> Int {
        let r = Double(colour.r) / 255, g = Double(colour.g) / 255, b = Double(colour.b) / 255
        let high = max(r, g, b), low = min(r, g, b)
        guard high - low > 0.08 else { return 0 }
        let hue = hsl(colour).hue
        return 1 + min(momentColours - 2, Int(hue / 360 * Double(momentColours - 1)))
    }

    /// The average of some colours, from nought to one each.
    static func averageColour(_ colours: [PackedColor]) -> (Double, Double, Double) {
        guard !colours.isEmpty else { return (1, 1, 1) }
        var r = 0.0, g = 0.0, b = 0.0
        for colour in colours {
            r += Double(colour.r)
            g += Double(colour.g)
            b += Double(colour.b)
        }
        let many = Double(colours.count) * 255
        return (r / many, g / many, b / many)
    }

    /// A number as the file writes it: plain, and never "nan".
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 100_000).rounded() / 100_000
        return rounded == 0 ? "0" : "\(rounded)"
    }
}
