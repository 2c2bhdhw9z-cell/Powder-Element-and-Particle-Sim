import CrucibleCore
import SwiftUI

/// Worlds other people have published.
///
/// Browsing, liking and opening need no account, matching the website exactly — the app must not be a way
/// around its rules, in either direction. Publishing does, because it puts a name on something.
///
/// Only the powder chamber is published. That is not an oversight: the workshop's table on the server
/// holds a grid, and the field is a list of bodies. Sharing fields would be a second kind of thing in one
/// column, which is how a table ends up full of rows nothing can read.
struct WorkshopSheet: View {
    let account: CloudAccount
    let powder: SimulationModel
    let glass: GlassLevel

    @State private var maps: [CloudMapSummary] = []
    @State private var failure: CloudFailure?
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var sort: CloudMapSort = .recent
    @State private var tag = ""
    @State private var lastAction: String?
    /// Which worlds this session has already liked, so the button can stop offering.
    @State private var liked: Set<String> = []

    @State private var isPublishing = false
    @State private var title = ""
    @State private var summary = ""
    @State private var tags = ""

    var body: some View {
        LabSheet(title: "Workshop", subtitle: subtitle, glass: glass) {
            if let problem = account.problem {
                CloudNotice(message: problem, tone: .warn) { account.dismissProblem() }
            }
            if let lastAction {
                CloudNotice(message: lastAction, tone: .ok) { self.lastAction = nil }
            }

            if account.hasServer {
                filters
                list
                publishSection
            } else {
                CloudNote("""
                The workshop needs a server. Set one up under "Your worlds" first — it is the web address \
                you would open Crucible at in a browser.
                """)
            }
        }
        .task {
            guard account.hasServer else { return }
            await reload()
        }
    }

    private var subtitle: String? {
        account.hasServer ? "Worlds people have published" : "No server set"
    }

    // MARK: Narrowing it down

    private var filters: some View {
        LabGroup("Show") {
            LabChoice(
                label: nil,
                selection: $sort,
                options: CloudMapSort.allCases.map { (value: $0, title: $0.title) }
            )
            LabDivider()
            HStack(spacing: 10) {
                TextField("Any tag", text: $tag)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await reload() } }
                if !tag.isEmpty {
                    Button {
                        tag = ""
                        Task { await reload() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.labBody(13))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the tag")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        // Reloaded when the ordering changes, because a list that keeps its old order after the choice
        // moves looks like the choice did nothing.
        .onChange(of: sort) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: The list

    @ViewBuilder
    private var list: some View {
        LabGroup(maps.isEmpty ? "Published worlds" : "Published worlds (\(maps.count))") {
            if isLoading {
                LabRow(label: "Loading…", value: "", tint: Palette.muted)
            } else if let failure {
                // Never an empty list for a request that failed.
                CloudFailureRow(failure: failure) {
                    Task { await reload() }
                }
            } else if maps.isEmpty {
                LabRow(
                    label: tag.isEmpty ? "Nothing published yet" : "Nothing with that tag",
                    value: "",
                    tint: Palette.muted
                )
            } else {
                ForEach(Array(maps.enumerated()), id: \.offset) { index, map in
                    if index > 0 { LabDivider() }
                    row(map)
                }
            }
        }
    }

    private func row(_ map: CloudMapSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(map.title)
                        .font(.labBody(13, .medium))
                        .foregroundStyle(Palette.foreground)
                    Text("by \(map.author)")
                        .font(.labBody(11))
                        .foregroundStyle(Palette.subtleForeground)
                    if !map.description.isEmpty {
                        Text(map.description)
                            .font(.labBody(11))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(map.likes) ♥")
                        .font(.labNumeric(11))
                        .foregroundStyle(Palette.muted)
                    Text("\(map.downloads) opened")
                        .font(.labNumeric(11))
                        .foregroundStyle(Palette.subtleForeground)
                }
            }

            if !map.tagList.isEmpty {
                LabFlow(spacing: 5) {
                    ForEach(Array(map.tagList.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.labBody(10))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await open(map) }
                } label: {
                    Text("Open in the lab")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    Task { await like(map) }
                } label: {
                    Text(liked.contains(map.id) ? "Liked" : "Like")
                        .font(.labBody(12))
                        .foregroundStyle(liked.contains(map.id) ? Palette.subtleForeground : Palette.foreground)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                // Once per world per session. The server counts every request, so leaving the button live
                // would let one person hold it down and make the count meaningless.
                .disabled(isWorking || liked.contains(map.id))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Publishing

    @ViewBuilder
    private var publishSection: some View {
        if !account.isSignedIn {
            CloudNote("""
            Sign in under "Your worlds" to publish something. Browsing, opening and liking need no \
            account.
            """)
        } else if isPublishing {
            LabGroup(
                "Publish the powder chamber",
                footnote: "It goes out exactly as it is now. Only the powder chamber can be published."
            ) {
                field("Title", text: $title, limit: CloudLimits.nameLength)
                LabDivider()
                field("What it is", text: $summary, limit: CloudLimits.descriptionLength)
                LabDivider()
                field("Tags, separated by commas", text: $tags, limit: CloudLimits.tagsLength)
                LabDivider()
                LabAction(
                    label: isWorking ? "Publishing…" : "Publish it",
                    symbol: "arrow.up.circle"
                ) {
                    Task { await publish() }
                }
                LabDivider()
                LabAction(label: "Never mind", symbol: "xmark") {
                    isPublishing = false
                }
            }
        } else {
            LabGroup("Publishing") {
                LabAction(
                    label: "Publish this world",
                    detail: "Shares the powder chamber as it is now.",
                    symbol: "arrow.up.circle"
                ) {
                    isPublishing = true
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
                Spacer(minLength: 8)
                // Shown only when it is nearly a problem, so it is a warning rather than clutter.
                if text.wrappedValue.count > limit - 20 {
                    Text("\(text.wrappedValue.count)/\(limit)")
                        .font(.labNumeric(10))
                        .foregroundStyle(text.wrappedValue.count > limit ? Palette.danger : Palette.warn)
                }
            }
            TextField(label, text: text)
                .font(.labBody(13))
                .foregroundStyle(Palette.foreground)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Doing things

    private func reload() async {
        guard let client = account.client else { return }
        isLoading = true
        defer { isLoading = false }
        switch await client.maps(sort: sort, tag: tag) {
        case let .success(list):
            maps = list
            failure = nil
        case let .failure(problem):
            // The list is left as it was. A failed refresh must not make worlds appear to vanish.
            failure = problem
        }
    }

    private func open(_ map: CloudMapSummary) async {
        guard let client = account.client else { return }
        isWorking = true
        defer { isWorking = false }

        // Through `download` rather than a plain read, because opening one is what the count is counting.
        switch await client.download(id: map.id) {
        case let .success(full):
            let bytes = Data(full.gridData.utf8)
            guard let state = try? JSONDecoder().decode(PowderState.self, from: bytes),
                  powder.apply(state)
            else {
                account.reportProblem(
                    "That world could not be opened. It may have been published by a different version."
                )
                return
            }
            lastAction = "Opened \"\(full.title)\" in the powder chamber."
            // The count has changed, so the row showing it is now wrong.
            await reload()
        case let .failure(problem):
            account.reportProblem(problem.explanation)
        }
    }

    private func like(_ map: CloudMapSummary) async {
        guard let client = account.client else { return }
        isWorking = true
        defer { isWorking = false }

        switch await client.like(id: map.id) {
        case let .success(likes):
            liked.insert(map.id)
            // Updated from what the server returned rather than by adding one locally, so the number
            // shown is the real one even if somebody else liked it a moment ago.
            if let index = maps.firstIndex(where: { $0.id == map.id }) {
                maps[index].likes = likes
            }
        case let .failure(problem):
            account.reportProblem(problem.explanation)
        }
    }

    private func publish() async {
        guard let client = account.client else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        isWorking = true
        defer { isWorking = false }

        guard let data = try? String(decoding: JSONEncoder().encode(powder.captureState()), as: UTF8.self)
        else {
            account.reportProblem("That world could not be packed up to send.")
            return
        }
        // A small picture, so the workshop is a set of worlds rather than a list of names. Dropped if it
        // comes out too large for the server's limit — a world without a picture still publishes, and
        // being refused outright over a thumbnail would be a poor trade.
        var thumbnail = powder.thumbnailDataURL() ?? ""
        if thumbnail.count > CloudLimits.thumbnailLength { thumbnail = "" }

        guard CloudLimits.acceptsPublication(
            title: cleanTitle,
            description: summary,
            tags: tags,
            thumbnail: thumbnail,
            gridData: data
        ) else {
            account.reportProblem("Check the title and the lengths — something is too long or missing.")
            return
        }

        let request = CloudPublishRequest(
            title: cleanTitle,
            description: summary,
            tags: tags,
            thumbnail: thumbnail,
            gridData: data
        )
        switch await client.publish(request) {
        case .success:
            lastAction = "Published \"\(cleanTitle)\"."
            isPublishing = false
            title = ""
            summary = ""
            tags = ""
            await reload()
        case let .failure(problem):
            account.reportProblem(problem.explanation)
        }
    }
}
