import CrucibleCore
import SwiftUI

/// What the app says to somebody opening it for the first time.
///
/// Six things, one screen each, swiped through — and a way out of it on every one. Nothing here is a tour that drives
/// the app: it says the handful of things that are invisible until somebody says them, and then gets out of the way.
///
/// What it says is `LabIntroduction` in the engine, where the words are checked for covering the things nobody would
/// otherwise find. This is the part that shows them.
struct WelcomeSheet: View {
    /// Called when it is finished with, whether read through or skipped.
    let onFinish: () -> Void
    /// Turns on the smaller lab, for somebody who is about to hand the phone over.
    let onWantsSimple: () -> Void

    @State private var at = 0

    private var steps: [LabIntroduction.Step] { LabIntroduction.steps }

    var body: some View {
        VStack(spacing: 0) {
            heading
            TabView(selection: $at) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    page(step, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            buttons
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
        .interactiveDismissDisabled()
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Crucible")
                    .font(.labDisplay(20))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.foreground)
                Text("A lab of falling material and moving bodies")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                onFinish()
            } label: {
                Text("Skip")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func page(_ step: LabIntroduction.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: step.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.primary)
                .accessibilityHidden(true)
            Text(step.title)
                .font(.labDisplay(22))
                .tracking(-0.4)
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.body)
                .font(.labBody(15))
                .lineSpacing(4)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            // The empty half of the page, filled with the thing itself happening. Only the page on screen runs.
            if index == at {
                IntroDemo(page: index)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 360)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if at == steps.count - 1 {
                // Offered only on the last page, where it has been explained.
                Button {
                    Haptics.selection()
                    onWantsSimple()
                    onFinish()
                } label: {
                    Text("Start simple")
                        .font(.labBody(14, .medium))
                        .foregroundStyle(Palette.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.simple")
            }
            Button {
                Haptics.tap()
                if at < steps.count - 1 {
                    withAnimation(.easeOut(duration: 0.2)) { at += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(at < steps.count - 1 ? "Next" : "Start")
                    .font(.labBody(15, .semiBold))
                    .foregroundStyle(Palette.primaryForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Palette.primary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.next")
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 4)
    }
}
