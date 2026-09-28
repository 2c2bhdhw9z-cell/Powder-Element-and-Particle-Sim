import CrucibleCore
import SwiftUI

/// Talking to the lab, waving at it, looking round it with your head, and putting it on a table.
///
/// All four use the phone's camera or microphone, and all four say so before they ask for either. None has been tried
/// on a phone yet — the lab is built on machines with neither — and the panel says that too, rather than letting
/// somebody think a quiet failure is the design.
struct SensesSheet: View {
    let speech: SpeechListener
    let camera: CameraSenses
    let onTable: () -> Void

    var body: some View {
        LabSheet(title: "Talk, wave, look", subtitle: "The lab through the microphone and the camera") {
            LabGroup(
                "Talk to it",
                footnote: "Say things like “make it rain”, “give me lava”, “boom”, “turn it upside down”, “show me the "
                    + "galaxy”, “slow motion”, “pause”. Heard on the phone itself where it can be; nothing is kept."
            ) {
                LabToggle(
                    label: "Listen for what I say",
                    isOn: Binding(get: { speech.isListening }, set: { $0 ? speech.start() : speech.stop() })
                )
                if speech.isListening || speech.lastUnderstood != nil {
                    LabDivider()
                    LabRow(label: "Heard", value: speech.lastHeard.isEmpty ? "…" : String(speech.lastHeard.suffix(40)))
                    if let understood = speech.lastUnderstood {
                        LabDivider()
                        LabRow(label: "Did", value: understood, tint: Palette.ok)
                    }
                }
                if let problem = speech.problem { problemLine(problem) }
            }

            LabGroup(
                "Wave at it",
                footnote: "The front camera watches for a hand. In the field an open hand pushes and a pinch pulls; in "
                    + "the powder world a pinch paints with whatever is chosen."
            ) {
                LabToggle(
                    label: "Watch for my hand",
                    isOn: Binding(get: { camera.watchesHands }, set: { camera.setWatchesHands($0) })
                )
                if camera.watchesHands {
                    LabDivider()
                    LabRow(label: "Hand", value: camera.hand.map { $0.grabbing ? "pinching" : "open" } ?? "not seen")
                }
            }

            LabGroup(
                "Look round with your head",
                footnote: "The front camera watches your face, and moving your head moves the view round the field "
                    + "in 3D, as if through a window. Where your head is when it starts is straight on."
            ) {
                LabToggle(
                    label: "Follow my head",
                    isOn: Binding(get: { camera.watchesHead }, set: { camera.setWatchesHead($0) })
                )
                if camera.watchesHead {
                    LabDivider()
                    LabRow(label: "Face", value: camera.seesFace ? "seen" : "not seen")
                    LabDivider()
                    LabAction(label: "This is straight on", symbol: "scope") { camera.recentre() }
                }
            }
            if let problem = camera.problem { problemLine(problem) }

            LabGroup(
                "On your table",
                footnote: "The powder world, running, stood on a real table through the back camera. Walk round it."
            ) {
                LabAction(label: "Put it on a table", symbol: "arkit") { onTable() }
            }

            Text("None of these has been tried on a phone yet: they were built without a camera or a microphone to test "
                + "them with. What they decide is checked; whether they hear and see is not. If one does nothing, "
                + "“That looked wrong” in the Lab panel sends what it was doing.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func problemLine(_ text: String) -> some View {
        Text(text)
            .font(.labBody(11))
            .foregroundStyle(Palette.warn)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
