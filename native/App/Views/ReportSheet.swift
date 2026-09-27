import SwiftUI

/// Shows a report before it is sent, and sends it.
///
/// The whole note is shown, not summarised. Somebody being asked to send something about their own use of an app
/// should be able to read every word of it first, and it is short enough to read.
struct ReportSheet: View {
    let report: Breadcrumbs.Report

    var body: some View {
        LabSheet(
            title: report.title,
            subtitle: report.urls.count > 1 ? "A note and a picture" : "A note"
        ) {
            LabGroup(footnote: "Nothing about you is in it: no account, no address, no file names. Only what the "
                + "simulation was.")
            {
                ShareLink(items: report.urls) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.labBody(13, .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 20)
                        Text("Send it")
                            .font(.labBody(13))
                            .foregroundStyle(Palette.foreground)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("report.send")
            }

            LabGroup("What it says") {
                // The note itself, in the same fixed-width face the readouts use, so its columns line up as written.
                Text(report.text)
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

/// The offer to send last time's note, and the sheet that shows a report before it is sent.
///
/// ## Why this is not written inline where it is used
///
/// Because it was, and the build machine refused it: "the compiler is unable to type-check this expression in
/// reasonable time". The app's main view had grown to the point where adding one more alert to the chain pushed the
/// type checker past its own limit — it compiles for a while and then gives up. Nothing was wrong with the alert; it
/// was the size of what it was added to. Anything else added around there belongs in a piece of its own like this.
struct Reporting: ViewModifier {
    let breadcrumbs: Breadcrumbs
    @Binding var report: Breadcrumbs.Report?

    /// Held as one string rather than built in the view, for the same reason as above.
    private static let lastTimeMessage = """
        Crucible closed by itself last time, or the phone closed it. A short note of what the world was doing was \
        kept. Nothing about you is in it.
        """

    func body(content: Content) -> some View {
        content
            .alert("Last time ended badly", isPresented: offering) {
                Button("Send the note") {
                    report = breadcrumbs.reportLastTime()
                    breadcrumbs.stopOffering()
                }
                Button("No thanks", role: .cancel) { breadcrumbs.stopOffering() }
            } message: {
                Text(Self.lastTimeMessage)
            }
            .sheet(item: $report) { target in
                ReportSheet(report: target)
            }
    }

    private var offering: Binding<Bool> {
        Binding(
            get: { breadcrumbs.offersLastTime },
            set: { if !$0 { breadcrumbs.stopOffering() } }
        )
    }
}

extension View {
    /// Offers to send last time's note when the last session ended badly, and shows a report before it is sent.
    func reporting(_ breadcrumbs: Breadcrumbs, report: Binding<Breadcrumbs.Report?>) -> some View {
        modifier(Reporting(breadcrumbs: breadcrumbs, report: report))
    }
}
