// Serialization for elements, deliberately matching the web implementation's
// JSON shape key for key.
//
// The web version stores custom elements as JSON under a browser local-storage
// key, and the same shape appears inside shared scenes. Matching it exactly means
// an element authored in one version can be opened in the other, and that scenes
// already saved by the web version remain loadable. The cost is a hand-written
// coding layer instead of the synthesized one, which is worth it — the
// alternative is stranding whatever the user already made.
//
// Key names therefore keep the web spellings: `decayIntoId` rather than
// `decayIntoID`, `description` rather than `info`, `targetElementId` rather than
// `targetElementID`.

extension InteractionRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case targetElementID = "targetElementId"
        case chance
        case resultSelfID = "resultSelfId"
        case resultTargetID = "resultTargetId"
        case spawnElementID = "spawnElementId"
        case tempChange
        case explosionRadius
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targetElementID: try container.decode(ElementID.self, forKey: .targetElementID),
            chance: try container.decode(Double.self, forKey: .chance),
            resultSelfID: try container.decodeIfPresent(ElementID.self, forKey: .resultSelfID),
            resultTargetID: try container.decodeIfPresent(ElementID.self, forKey: .resultTargetID),
            spawnElementID: try container.decodeIfPresent(ElementID.self, forKey: .spawnElementID),
            tempChange: try container.decodeIfPresent(Double.self, forKey: .tempChange) ?? 0,
            explosionRadius: try container.decodeIfPresent(Int.self, forKey: .explosionRadius) ?? 0
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetElementID, forKey: .targetElementID)
        try container.encode(chance, forKey: .chance)
        try container.encodeIfPresent(resultSelfID, forKey: .resultSelfID)
        try container.encodeIfPresent(resultTargetID, forKey: .resultTargetID)
        try container.encodeIfPresent(spawnElementID, forKey: .spawnElementID)
        // Omitted when zero so the output matches what the web version writes for
        // a rule that changes no temperature and causes no explosion.
        if tempChange != 0 { try container.encode(tempChange, forKey: .tempChange) }
        if explosionRadius != 0 { try container.encode(explosionRadius, forKey: .explosionRadius) }
    }
}

extension ElementDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case state
        case color
        case colorVariation
        case density
        case viscosity
        case flammability
        case burnRate
        case acidResistance
        case heatConductivity
        case ignitionTemp
        case defaultTemp
        case decayTicks
        case decayIntoID = "decayIntoId"
        case gravityFactor
        case isConductor
        case interactions
        case info = "description"
    }

    /// Decodes an element, applying the same defaults as the main initializer.
    ///
    /// Absent optional properties are filled in rather than rejected, because the
    /// web implementation's stored elements legitimately omit most of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(ElementID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            category: try container.decode(ElementCategory.self, forKey: .category),
            state: try container.decode(ElementState.self, forKey: .state),
            color: try container.decode(PackedColor.self, forKey: .color),
            colorVariation: try container.decodeIfPresent(Double.self, forKey: .colorVariation) ?? 0,
            density: try container.decode(Double.self, forKey: .density),
            // Routed through the main initializer, so a stored zero still
            // normalises to one exactly as the web implementation's
            // `def.viscosity || 1` would.
            viscosity: try container.decodeIfPresent(Double.self, forKey: .viscosity) ?? 1,
            flammability: try container.decodeIfPresent(Double.self, forKey: .flammability) ?? 0,
            burnRate: try container.decodeIfPresent(Double.self, forKey: .burnRate) ?? 0,
            acidResistance: try container.decodeIfPresent(Double.self, forKey: .acidResistance) ?? 0,
            heatConductivity: try container.decodeIfPresent(Double.self, forKey: .heatConductivity) ?? 0,
            ignitionTemp: try container.decodeIfPresent(Double.self, forKey: .ignitionTemp),
            defaultTemp: try container.decodeIfPresent(Double.self, forKey: .defaultTemp),
            decayTicks: try container.decodeIfPresent(Int.self, forKey: .decayTicks) ?? 0,
            decayIntoID: try container.decodeIfPresent(ElementID.self, forKey: .decayIntoID) ?? emptyElementID,
            gravityFactor: try container.decodeIfPresent(Double.self, forKey: .gravityFactor) ?? 1,
            isConductor: try container.decodeIfPresent(Bool.self, forKey: .isConductor) ?? false,
            interactions: try container.decodeIfPresent([InteractionRule].self, forKey: .interactions) ?? [],
            info: try container.decodeIfPresent(String.self, forKey: .info) ?? ""
        )
    }

    /// Encodes an element, omitting properties left at their default so the output
    /// stays as compact and as close to the hand-written web table as possible.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(state, forKey: .state)
        try container.encode(color, forKey: .color)
        try container.encode(density, forKey: .density)

        if colorVariation != 0 { try container.encode(colorVariation, forKey: .colorVariation) }
        if viscosity != 1 { try container.encode(viscosity, forKey: .viscosity) }
        if flammability != 0 { try container.encode(flammability, forKey: .flammability) }
        if burnRate != 0 { try container.encode(burnRate, forKey: .burnRate) }
        if acidResistance != 0 { try container.encode(acidResistance, forKey: .acidResistance) }
        if heatConductivity != 0 { try container.encode(heatConductivity, forKey: .heatConductivity) }
        try container.encodeIfPresent(ignitionTemp, forKey: .ignitionTemp)
        try container.encodeIfPresent(defaultTemp, forKey: .defaultTemp)
        if decayTicks != 0 { try container.encode(decayTicks, forKey: .decayTicks) }
        if decayIntoID != emptyElementID { try container.encode(decayIntoID, forKey: .decayIntoID) }
        if gravityFactor != 1 { try container.encode(gravityFactor, forKey: .gravityFactor) }
        if isConductor { try container.encode(isConductor, forKey: .isConductor) }
        if !interactions.isEmpty { try container.encode(interactions, forKey: .interactions) }
        if !info.isEmpty { try container.encode(info, forKey: .info) }
    }
}
