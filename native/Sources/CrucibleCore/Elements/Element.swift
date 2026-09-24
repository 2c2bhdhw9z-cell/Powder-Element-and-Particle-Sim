/// Names for the built-in element identifiers.
///
/// The web implementation's chemistry is written directly against raw numbers —
/// `if (type === 22)`, `nType !== 17 && nType !== 47`, `setElementAt(x, y, 27)`.
/// That is the single largest source of risk in porting it: a transposed digit
/// produces code that compiles, runs, and quietly turns salt into nitroglycerin.
///
/// Every identifier gets a name here so the ported physics can be read and
/// reviewed as English. `Element.portalA` cannot be mistyped into something that
/// still compiles; `22` can.
public enum Element {
    /// The empty cell. Element zero doubles as "air", which is why nothing and
    /// air are indistinguishable in this simulation.
    public static let empty: ElementID = 0
    public static let air: ElementID = 0

    public static let sand: ElementID = 1
    public static let water: ElementID = 2
    public static let wood: ElementID = 3
    public static let fire: ElementID = 4
    public static let smoke: ElementID = 5
    public static let lava: ElementID = 6
    public static let stone: ElementID = 7
    public static let acid: ElementID = 8
    public static let oil: ElementID = 9
    public static let gunpowder: ElementID = 10
    public static let plant: ElementID = 11
    public static let glass: ElementID = 12
    public static let ice: ElementID = 13
    public static let steam: ElementID = 14
    public static let c4: ElementID = 15
    public static let spark: ElementID = 16
    public static let metal: ElementID = 17
    public static let virus: ElementID = 18
    public static let ant: ElementID = 19
    public static let void: ElementID = 20
    public static let clone: ElementID = 21
    public static let portalA: ElementID = 22
    public static let portalB: ElementID = 23
    public static let antiGravityPowder: ElementID = 24
    public static let wax: ElementID = 25
    public static let thermite: ElementID = 26
    public static let saltWater: ElementID = 27
    public static let nitro: ElementID = 28
    public static let bedrock: ElementID = 29
    public static let rubber: ElementID = 30
    public static let oxygen: ElementID = 31
    public static let plasma: ElementID = 32
    public static let fuseWire: ElementID = 33
    public static let honey: ElementID = 34
    public static let helium: ElementID = 35
    public static let laser: ElementID = 36
    public static let salt: ElementID = 37
    public static let snow: ElementID = 38
    public static let dirt: ElementID = 39
    public static let seed: ElementID = 40
    public static let coal: ElementID = 41
    public static let concrete: ElementID = 42
    public static let hydrogen: ElementID = 43
    public static let mercury: ElementID = 44
    public static let mud: ElementID = 45
    public static let obsidian: ElementID = 46
    public static let copper: ElementID = 47
    public static let fan: ElementID = 48
    public static let wetMix: ElementID = 49

    /// The number of built-in elements. Identifiers `0 ..< builtInCount` are
    /// reserved.
    public static let builtInCount: ElementID = 50

    /// First identifier available to user-authored elements.
    public static let customIDStart: ElementID = 50
    /// Last identifier available to user-authored elements.
    public static let customIDEnd: ElementID = 99

    /// One past the highest identifier the registry can hold. Storage is a dense
    /// array of this size, so lookups are a bounds-checked index rather than a
    /// hash.
    public static let capacity = Int(customIDEnd) + 1
}
