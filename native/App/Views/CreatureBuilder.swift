import CrucibleCore
import SwiftUI

/// The creature builder, in the field's tray: ready-made creatures to start from, and a pen for bones and muscles.
///
/// ## How it is used
///
/// Switch Build on, choose Bone or Muscle, and drag on the world: each drag is one limb, joined at either end to any
/// joint already near. Then Bring it to life. Nothing holds a creature up but what was drawn, so a stick falls, a
/// triangle stands, and a creature whose muscles take turns — muscles drawn one after another do — may walk.
///
/// Its own view, like the movie studio, so drawing does not rebuild the whole tray.
struct FieldCreatureControls: View {
    let model: ParticleFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CREATURES")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            if model.depthEnabled {
                Text("Creatures stand on the floor of a flat field. Switch 3D off to build one.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LabFlow(spacing: 6) {
                    ForEach(ReadyCreature.allCases, id: \.self) { kind in
                        pill(kind.name, symbol: "figure.walk", lit: false) { model.addReadyCreature(kind) }
                            .accessibilityIdentifier("creature.ready.\(kind.rawValue)")
                    }
                    // Whenever there is anything to take away — a living creature or one half drawn. It used to wait for
                    // the once-a-second report, so a creature you had just made could have no way to remove it.
                    if model.hasAnyCreature {
                        pill("Take them away", symbol: "trash", lit: false) { model.removeCreatures() }
                            .accessibilityIdentifier("creature.removeAll")
                    }
                }
                Text(ReadyCreature.allCases.map { "\($0.name): \($0.about)" }.joined(separator: "\n"))
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)

                building

                ForEach(model.creatureReports, id: \.self) { line in
                    Text(line)
                        .font(.labBody(11, .medium))
                        .foregroundStyle(line.hasSuffix("fallen over.") ? Palette.warn : Palette.foreground)
                }
                .accessibilityIdentifier("creature.report")
            }
        }
    }

    @ViewBuilder
    private var building: some View {
        LabFlow(spacing: 6) {
            pill(model.isBuildingCreature ? "Building — drag on the world" : "Build your own", symbol: "pencil.and.outline",
                 lit: model.isBuildingCreature) {
                Haptics.selection()
                model.isBuildingCreature.toggle()
            }
            .accessibilityIdentifier("creature.build")
            if model.isBuildingCreature {
                pill("Bone", symbol: "line.diagonal", lit: model.creatureLimb == .bone) { model.creatureLimb = .bone }
                    .accessibilityIdentifier("creature.bone")
                pill("Muscle", symbol: "waveform.path", lit: model.creatureLimb == .muscle) { model.creatureLimb = .muscle }
                    .accessibilityIdentifier("creature.muscle")
            }
        }
        if model.isBuildingCreature || !model.creaturePlan.isEmpty {
            Text(planSummary)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
            LabFlow(spacing: 6) {
                pill("Bring it to life", symbol: "bolt.heart", lit: model.creaturePlan.problem == nil) {
                    model.bringCreatureToLife()
                }
                .accessibilityIdentifier("creature.live")
                .opacity(model.creaturePlan.problem == nil ? 1 : 0.5)
                if !model.creaturePlan.isEmpty {
                    pill("Undo the last limb", symbol: "arrow.uturn.backward", lit: false) {
                        model.creaturePlan.removeLast()
                    }
                    .accessibilityIdentifier("creature.undoLimb")
                    pill("Start again", symbol: "xmark", lit: false) { model.creaturePlan = CreaturePlan() }
                        .accessibilityIdentifier("creature.discard")
                }
            }
        }
        if let problem = model.creatureProblem {
            Text(problem)
                .font(.labBody(10))
                .foregroundStyle(Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planSummary: String {
        let plan = model.creaturePlan
        if plan.isEmpty {
            return "Close the tray and drag on the world: each drag is a bone or a muscle, joined to any joint near its "
                + "ends. Triangles stand; squares fold. Muscles drawn one after another take turns, which is what "
                + "walking is made of."
        }
        let bones = plan.limbs.filter { $0.kind == .bone }.count
        let muscles = plan.limbs.count - bones
        var line = "\(plan.joints.count) joints, \(bones) \(bones == 1 ? "bone" : "bones"), "
            + "\(muscles) \(muscles == 1 ? "muscle" : "muscles")."
        if let problem = plan.problem { line += " " + problem }
        return line
    }

    private func pill(_ title: String, symbol: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.labBody(12, .semiBold))
                .foregroundStyle(lit ? Palette.primaryForeground : Palette.foreground)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(lit ? Palette.primary : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

/// The creature being drawn, laid over the world: its bones solid, its muscles dashed, its joints as dots, and the
/// limb under the finger as it is dragged.
struct CreaturePlanOverlay: View {
    let model: ParticleFieldModel

    /// One line to draw, already on the screen.
    struct Line {
        var from: CGPoint
        var to: CGPoint
        var kind: CreaturePlan.Kind
    }

    var body: some View {
        if model.isBuildingCreature || !model.creaturePlan.isEmpty {
            // Worked out here, on the main thread, and handed to the canvas finished: the canvas draws somewhere the
            // model cannot be asked anything.
            let plan = model.creaturePlan
            let lines: [Line] = plan.limbs.compactMap { limb in
                guard let a = model.screenPoint(worldX: plan.joints[limb.a].x, y: plan.joints[limb.a].y),
                      let b = model.screenPoint(worldX: plan.joints[limb.b].x, y: plan.joints[limb.b].y)
                else { return nil }
                return Line(from: a, to: b, kind: limb.kind)
            }
            let dots = plan.joints.compactMap { model.screenPoint(worldX: $0.x, y: $0.y) }
            let stroke: Line? = model.creatureStroke.flatMap { stroke in
                guard let a = model.screenPoint(worldX: stroke.fromX, y: stroke.fromY),
                      let b = model.screenPoint(worldX: stroke.toX, y: stroke.toY)
                else { return nil }
                return Line(from: a, to: b, kind: model.creatureLimb)
            }
            Canvas { context, _ in
                for line in lines {
                    var path = Path()
                    path.move(to: line.from)
                    path.addLine(to: line.to)
                    context.stroke(
                        path,
                        with: .color(line.kind == .bone ? Palette.foreground : Palette.warn),
                        style: Self.style(line.kind)
                    )
                }
                if let stroke {
                    var path = Path()
                    path.move(to: stroke.from)
                    path.addLine(to: stroke.to)
                    context.stroke(path, with: .color(Palette.primary.opacity(0.8)), style: Self.style(stroke.kind))
                }
                for at in dots {
                    context.fill(
                        Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)),
                        with: .color(Palette.foreground)
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    nonisolated static func style(_ kind: CreaturePlan.Kind) -> StrokeStyle {
        kind == .bone
            ? StrokeStyle(lineWidth: 3, lineCap: .round)
            : StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 4])
    }
}
