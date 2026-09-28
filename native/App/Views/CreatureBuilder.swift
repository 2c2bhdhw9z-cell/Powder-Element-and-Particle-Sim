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
                    if !model.creatureReports.isEmpty {
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

    var body: some View {
        if model.isBuildingCreature || !model.creaturePlan.isEmpty {
            // Read here so the drawing follows the view as it moves; the plan and the stroke are what change it.
            let plan = model.creaturePlan
            let stroke = model.creatureStroke
            let kind = model.creatureLimb
            Canvas { context, _ in
                func point(_ x: Double, _ y: Double) -> CGPoint? { model.screenPoint(worldX: x, y: y) }
                for limb in plan.limbs {
                    guard let a = point(plan.joints[limb.a].x, plan.joints[limb.a].y),
                          let b = point(plan.joints[limb.b].x, plan.joints[limb.b].y)
                    else { continue }
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(limb.kind == .bone ? Palette.foreground : Palette.warn), style: Self.style(limb.kind))
                }
                if let stroke, let a = point(stroke.fromX, stroke.fromY), let b = point(stroke.toX, stroke.toY) {
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(Palette.primary.opacity(0.8)), style: Self.style(kind))
                }
                for joint in plan.joints {
                    guard let at = point(joint.x, joint.y) else { continue }
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)), with: .color(Palette.foreground))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    static func style(_ kind: CreaturePlan.Kind) -> StrokeStyle {
        kind == .bone
            ? StrokeStyle(lineWidth: 3, lineCap: .round)
            : StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 4])
    }
}
