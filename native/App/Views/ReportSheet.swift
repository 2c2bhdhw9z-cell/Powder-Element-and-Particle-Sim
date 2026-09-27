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
