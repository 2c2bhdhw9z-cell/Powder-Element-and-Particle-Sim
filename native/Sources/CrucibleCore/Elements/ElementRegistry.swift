/// Somewhere to keep user-authored elements between launches.
///
/// The web implementation writes them straight to browser local storage. The
/// engine here has no access to a filesystem by design — it imports no Foundation
/// — so persistence is injected instead. The app supplies an implementation
/// backed by a file; tests supply one backed by memory, or none at all.
public protocol CustomElementStore: AnyObject {
    /// Elements restored from the last session. Implementations should return
    /// what they can and drop what they cannot parse, rather than failing
    /// wholesale — one damaged element must not cost the user the rest.
    func loadCustomElements() -> [ElementDefinition]

    /// Records the current set of user-authored elements.
    func saveCustomElements(_ elements: [ElementDefinition])
}

/// The set of elements the simulation knows about: the fifty built-ins, plus up
/// to fifty user-authored ones.
///
/// This is the editable, main-thread-facing model. The simulation itself does not
/// use it — it uses the ``table`` snapshot, which is a value type it can safely
/// carry across threads. The table is rebuilt whenever the element set changes,
/// which happens when someone edits an element, not sixty times a second.
public final class ElementRegistry {
    /// Dense storage over the whole identifier range. An array index rather than
    /// a dictionary: identifiers are small and contiguous by construction, so
    /// hashing would be pure overhead.
    private var storage: [ElementDefinition?]

    /// Where custom elements are kept between launches, if anywhere.
    private let store: CustomElementStore?

    /// The packed, thread-safe snapshot the simulation reads.
    ///
    /// Rebuilt on every change to the element set, so reading it costs nothing.
    public private(set) var table: ElementTable

    /// Creates a registry holding the built-in elements, plus any custom elements
    /// the store can supply.
    public init(store: CustomElementStore? = nil) {
        self.store = store
        self.storage = [ElementDefinition?](repeating: nil, count: Element.capacity)
        self.table = ElementTable(definitions: DefaultElements.all)
        resetToDefaults()
        loadCustom()
    }

    // MARK: - Reading

    /// The definition for an identifier.
    ///
    /// Unknown identifiers resolve to air, matching the web implementation's
    /// `this.elements.get(id) || this.elements.get(0)`. Scene files are user data
    /// and can name elements that no longer exist.
    public func element(_ id: ElementID) -> ElementDefinition {
        let index = Int(id)
        if index < storage.count, let found = storage[index] {
            return found
        }
        // Air is always present: `resetToDefaults` cannot remove it and
        // `delete` refuses built-ins.
        return storage[Int(Element.empty)] ?? DefaultElements.all[Int(Element.empty)]
    }

    /// Every registered element, ordered by identifier.
    public var allElements: [ElementDefinition] {
        storage.compactMap { $0 }
    }

    /// Everything offerable in the element picker — that is, everything except
    /// the empty cell.
    public var paletteElements: [ElementDefinition] {
        storage.compactMap { definition in
            guard let definition, definition.id != Element.empty else { return nil }
            return definition
        }
    }

    /// The pickable elements in one category, ordered by identifier.
    public func elements(in category: ElementCategory) -> [ElementDefinition] {
        paletteElements.filter { $0.category == category }
    }

    /// Whether an identifier belongs to a built-in element, which cannot be
    /// deleted or overwritten.
    public func isBuiltIn(_ id: ElementID) -> Bool {
        id < Element.customIDStart
    }

    /// The lowest free custom identifier, or `nil` when all fifty slots are used.
    ///
    /// The web implementation returns `-1` when full. Returning `nil` instead
    /// makes the "no room left" case impossible to overlook — a caller cannot
    /// accidentally use it as an identifier.
    public var nextAvailableID: ElementID? {
        for id in Element.customIDStart ... Element.customIDEnd {
            if storage[Int(id)] == nil { return id }
        }
        return nil
    }

    // MARK: - Writing

    /// Restores the built-in elements, discarding any custom ones.
    public func resetToDefaults() {
        storage = [ElementDefinition?](repeating: nil, count: Element.capacity)
        for definition in DefaultElements.all {
            storage[Int(definition.id)] = definition
        }
        rebuildTable()
    }

    /// Adds or replaces a user-authored element.
    ///
    /// Returns `false` — changing nothing — when the identifier is outside the
    /// range reserved for custom elements. Built-ins are not overwritable,
    /// because the physics and the test suite are both written against them.
    @discardableResult
    public func register(_ element: ElementDefinition) -> Bool {
        guard element.id >= Element.customIDStart, element.id <= Element.customIDEnd else {
            return false
        }
        storage[Int(element.id)] = element
        rebuildTable()
        persistCustom()
        return true
    }

    /// Removes a user-authored element.
    ///
    /// Returns `false` for built-in identifiers and for identifiers that hold
    /// nothing.
    @discardableResult
    public func deleteCustomElement(_ id: ElementID) -> Bool {
        guard id >= Element.customIDStart, Int(id) < storage.count else { return false }
        guard storage[Int(id)] != nil else { return false }
        storage[Int(id)] = nil
        rebuildTable()
        persistCustom()
        return true
    }

    // MARK: - Persistence

    /// The user-authored elements only.
    public var customElements: [ElementDefinition] {
        storage.compactMap { definition in
            guard let definition, definition.id >= Element.customIDStart else { return nil }
            return definition
        }
    }

    private func rebuildTable() {
        table = ElementTable(definitions: allElements)
    }

    private func persistCustom() {
        store?.saveCustomElements(customElements)
    }

    private func loadCustom() {
        guard let store else { return }
        var changed = false
        for definition in store.loadCustomElements() {
            guard definition.id >= Element.customIDStart, definition.id <= Element.customIDEnd else {
                // Skip rather than reject the batch: a single out-of-range entry
                // should not cost the user their other elements.
                continue
            }
            storage[Int(definition.id)] = definition
            changed = true
        }
        if changed { rebuildTable() }
    }
}
