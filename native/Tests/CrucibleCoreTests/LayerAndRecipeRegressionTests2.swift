import Testing
@testable import CrucibleCore

@Suite("Review field faults two")
struct ReviewFieldFaultsTwo {
    // F15 was a false alarm: a body added to a coloured layer does wear its colour (checked in `addParticle`). The
    // probe painted the body red by hand afterwards, which is the painter tool's job and should be kept.

    // F16 — duplicateLayer claims to return nil when there is nothing to copy.
    @Test("F16 duplicating an empty layer is refused")
    func duplicateEmpty() {
        let engine = ParticleEngine(width: 300, height: 300, seed: 2)
        engine.clear()
        _ = engine.addLayer(named: "Empty")
        let made = engine.duplicateLayer(1)
        print("F16 duplicate of empty layer -> \(String(describing: made)), layers=\(engine.layers.count)")
        #expect(made == nil)
    }
}
