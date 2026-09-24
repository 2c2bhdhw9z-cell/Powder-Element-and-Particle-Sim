import CrucibleCore
import SwiftUI

/// The account, the server, and the worlds kept on it.
///
/// ## What this panel is careful about
///
/// One thing above all: never showing an empty list when a request failed. "You have no saved worlds" and
/// "nobody managed to ask" look identical and mean opposite things, and getting that wrong is how somebody
/// concludes their work has been lost. So the list has three states, not two — worlds, nothing yet, and
/// something went wrong — and the third says what went wrong and whether trying again could help.
///
/// The second thing is the two facts about a server nobody would otherwise discover until too late:
/// whether accounts work at all, and whether the database is real or the throwaway one the website ships
/// with. On the throwaway one a saved world appears to save and is simply gone.
struct CloudSheet: View {
    let account: CloudAccount
    let powder: SimulationModel
    let field: ParticleFieldModel
    let chamber: Chamber
    let glass: GlassLevel
    let onOpenWorkshop: () -> Void

    @State private var addressDraft = ""
    @State private var saves: [CloudSaveSummary] = []
    @State private var listFailure: CloudFailure?
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var saveName = ""
    @State private var lastAction: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        LabSheet(title: "Your worlds", subtitle: subtitle, glass: glass) {
            if let problem = account.problem {
                CloudNotice(message: problem, tone: .warn) { account.dismissProblem() }
            }
            if let lastAction {
                CloudNotice(message: lastAction, tone: .ok) { self.lastAction = nil }
            }

            if account.hasServer {
                accountSection
                if account.isSignedIn {
                    keepSection
                    listSection
                }
                workshopSection
                serverSection
            } else {
                setUpSection
            }
        }
        .task {
            addressDraft = account.address
            guard account.hasServer else { return }
            await account.check()
            await reload()
        }
    }

    private var subtitle: String? {
        guard account.hasServer else { return "Keep worlds on a server, and share them" }
        if !account.isSignedIn { return "Sign in to keep worlds on the server" }
        return account.status?.persistent == false ? "This server does not keep anything" : nil
    }

    // MARK: Setting a server up

    private var setUpSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudNote("""
            Crucible can keep your worlds on a server and share them with other people. It needs to be \
            told where that server is — this app has no way of knowing on its own.

            It is the same web address you would open Crucible at in a browser.
            """)

            LabGroup("Server address", footnote: "Something like crucible.vercel.app.") {
                addressField
            }
        }
    }

    private var serverSection: some View {
        LabGroup("Server", footnote: account.address) {
            LabRow(label: "Storage", value: storageText, tint: storageTint)
            LabDivider()
            LabRow(
                label: "Accounts",
                value: (account.status?.accounts ?? false) ? "Available" : "Switched off",
                tint: (account.status?.accounts ?? false) ? Palette.ok : Palette.warn
            )
            LabDivider()
            LabAction(
                label: account.isChecking ? "Checking…" : "Check this server again",
                symbol: "arrow.clockwise"
            ) {
                Task {
                    await account.check()
                    await reload()
                }
            }
            LabDivider()
            LabAction(label: "Use a different server", symbol: "pencil", isDestructive: true) {
                account.clearAddress()
                addressDraft = ""
                saves = []
                listFailure = nil
            }
        }
    }

    private var storageText: String {
        guard let status = account.status else { return "Not checked" }
        return status.persistent ? "Kept permanently" : "Temporary — nothing is kept"
    }

    private var storageTint: Color {
        guard let status = account.status else { return Palette.muted }
        return status.persistent ? Palette.ok : Palette.danger
    }

    private var addressField: some View {
        HStack(spacing: 10) {
            TextField("crucible.vercel.app", text: $addressDraft)
                .font(.labBody(13))
                .foregroundStyle(Palette.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .focused($addressFocused)
                .onSubmit(useAddress)
            Button(action: useAddress) {
                Text("Use")
                    .font(.labBody(12, .semiBold))
                    .foregroundStyle(Palette.primaryForeground)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Palette.primary))
            }
            .buttonStyle(.plain)
            .disabled(addressDraft.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private func useAddress() {
        addressFocused = false
        guard account.setAddress(addressDraft) else { return }
        addressDraft = account.address
        Task {
            await account.check()
            await reload()
        }
    }

    // MARK: The account

    @ViewBuilder
    private var accountSection: some View {
        if account.isSignedIn {
            LabGroup("Account") {
                LabRow(label: "Signed in", value: "Yes", tint: Palette.ok)
                LabDivider()
                LabAction(
                    label: "Sign out on this phone",
                    detail: "Your worlds stay on the server.",
                    symbol: "person.crop.circle.badge.xmark",
                    isDestructive: true
                ) {
                    account.signOut()
                    saves = []
                    listFailure = nil
                }
            }
        } else if account.canSignIn {
            LabGroup(
                "Sign in",
                footnote: "Opens your phone's own sign-in window. Crucible never sees your password."
            ) {
                ForEach(Array(account.providers.enumerated()), id: \.offset) { index, provider in
                    if index > 0 { LabDivider() }
                    LabAction(
                        label: account.isSigningIn ? "Signing in…" : "Continue with \(provider.label)",
                        symbol: "person.crop.circle"
                    ) {
                        Task {
                            await account.signIn(provider: provider)
                            await reload()
                        }
                    }
                }
            }
        } else if account.status == nil {
            LabGroup {
                LabAction(
                    label: account.isChecking ? "Checking the server…" : "Check the server",
                    symbol: "arrow.clockwise"
                ) {
                    Task { await account.check() }
                }
            }
        } else {
            CloudNote("""
            This server does not have accounts switched on, so there is nothing to sign in to and \
            nothing can be kept on it. Whoever set it up would need to turn accounts on.
            """)
        }
    }

    // MARK: Keeping this world

    private var keepSection: some View {
        LabGroup(
            "Keep this world",
            footnote: keepFootnote
        ) {
            HStack(spacing: 10) {
                TextField("Name", text: $saveName)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button(action: keep) {
                    Text(isWorking ? "…" : "Keep")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(canKeep ? Palette.primaryForeground : Palette.subtleForeground)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(canKeep ? Palette.primary : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(!canKeep)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
        }
    }

    private var keepFootnote: String {
        let which = chamber == .powder ? "powder" : "field"
        if account.status?.persistent == false {
            return "This server keeps nothing permanently, so this will disappear. Keeping the \(which) "
                + "chamber as it is now."
        }
        return "Keeps the \(which) chamber exactly as it is now."
    }

    /// Checked against the engine's own limits, so the button agrees with what the server will accept.
    private var canKeep: Bool {
        !isWorking && !saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && saveName.trimmingCharacters(in: .whitespacesAndNewlines).count <= CloudLimits.nameLength
    }

    // MARK: The list

    @ViewBuilder
    private var listSection: some View {
        LabGroup(saves.isEmpty ? "Kept on the server" : "Kept on the server (\(saves.count))") {
            if isLoading {
                LabRow(label: "Loading…", value: "", tint: Palette.muted)
            } else if let listFailure {
                // The distinction that matters. Never an empty list for a request that failed.
                CloudFailureRow(failure: listFailure) {
                    Task { await reload() }
                }
            } else if saves.isEmpty {
                LabRow(label: "Nothing kept yet", value: "", tint: Palette.muted)
            } else {
                ForEach(Array(saves.enumerated()), id: \.offset) { index, save in
                    if index > 0 { LabDivider() }
                    savedRow(save)
                }
            }
        }
    }

    private func savedRow(_ save: CloudSaveSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(save.name)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
                Text(save.chamber == .particle ? "Field" : "Powder")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            Spacer(minLength: 8)
            Button {
                Task { await open(save) }
            } label: {
                Text("Open")
                    .font(.labBody(12, .semiBold))
                    .foregroundStyle(Palette.primaryForeground)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Palette.primary))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            Button {
                Task { await remove(save) }
            } label: {
                Image(systemName: "trash")
                    .font(.labBody(12, .medium))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Delete \(save.name)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    // MARK: The workshop

    private var workshopSection: some View {
        LabGroup(
            "Workshop",
            footnote: "Worlds other people have published. Browsing needs no account."
        ) {
            LabAction(label: "Open the workshop", symbol: "square.grid.2x2", action: onOpenWorkshop)
        }
    }

    // MARK: Doing things

    private func reload() async {
        guard let client = account.client, account.isSignedIn else {
            saves = []
            listFailure = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        switch await client.saves() {
        case let .success(list):
            saves = list
            listFailure = nil
        case let .failure(failure):
            // The list is left exactly as it was rather than emptied. A failed refresh must not make
            // worlds appear to vanish.
            listFailure = failure
        }
    }

    private func keep() {
        guard let client = account.client else { return }
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            isWorking = true
            defer { isWorking = false }

            let payload: String?
            let mode: CloudChamber
            switch chamber {
            case .powder:
                mode = .powder
                payload = try? String(
                    decoding: JSONEncoder().encode(powder.captureState()), as: UTF8.self
                )
            case .field:
                mode = .particle
                payload = try? String(
                    decoding: JSONEncoder().encode(field.captureState()), as: UTF8.self
                )
            }
            guard let data = payload, CloudLimits.acceptsSave(name: name, data: data) else {
                lastAction = nil
                account.reportProblem("That world could not be packed up to send.")
                return
            }

            switch await client.createSave(CloudSaveRequest(name: name, mode: mode, data: data)) {
            case .success:
                saveName = ""
                lastAction = "Kept \"\(name)\" on the server."
                await reload()
            case let .failure(failure):
                account.reportProblem(failure.explanation)
            }
        }
    }

    private func open(_ summary: CloudSaveSummary) async {
        guard let client = account.client else { return }
        isWorking = true
        defer { isWorking = false }

        switch await client.save(id: summary.id) {
        case let .success(save):
            let bytes = Data(save.data.utf8)
            switch save.chamber {
            case .powder:
                guard let state = try? JSONDecoder().decode(PowderState.self, from: bytes),
                      powder.apply(state)
                else {
                    account.reportProblem("That world could not be opened. It may have been saved by a "
                        + "different version.")
                    return
                }
            case .particle:
                guard let state = try? JSONDecoder().decode(ParticleState.self, from: bytes),
                      field.apply(state)
                else {
                    account.reportProblem("That world could not be opened. It may have been saved by a "
                        + "different version.")
                    return
                }
            case nil:
                // A kind this build does not know. Refused rather than guessed at — opening a field of
                // orbiting bodies as a grid of sand would not be a recoverable mistake.
                account.reportProblem("That world is a kind this version of Crucible does not know about.")
                return
            }
            lastAction = "Opened \"\(save.name)\"."
        case let .failure(failure):
            account.reportProblem(failure.explanation)
        }
    }

    private func remove(_ save: CloudSaveSummary) async {
        guard let client = account.client else { return }
        isWorking = true
        defer { isWorking = false }

        switch await client.deleteSave(id: save.id) {
        case .success:
            // Removed here as well as on the server, rather than waiting for a refresh, so the list does
            // not sit there showing something that has gone.
            saves.removeAll { $0.id == save.id }
            lastAction = "Removed \"\(save.name)\"."
        case let .failure(failure):
            account.reportProblem(failure.explanation)
        }
    }
}

// MARK: - Shared pieces

/// A line of explanation.
struct CloudNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.labBody(11))
            .foregroundStyle(Palette.subtleForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Something worth saying, with a way to dismiss it.
struct CloudNotice: View {
    enum Tone {
        case warn
        case ok

        var colour: Color {
            switch self {
            case .warn: Palette.warn
            case .ok: Palette.ok
            }
        }

        var symbol: String {
            switch self {
            case .warn: "exclamationmark.triangle"
            case .ok: "checkmark.circle"
            }
        }
    }

    let message: String
    let tone: Tone
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.symbol)
                .font(.labBody(13, .medium))
                .foregroundStyle(tone.colour)
            Text(message)
                .font(.labBody(12))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.subtleForeground)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(tone.colour.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(tone.colour.opacity(0.3), lineWidth: 1)
        )
    }
}

/// A failed request, in place of the list it would have filled.
///
/// The whole point of the type. An empty list here would say "you have nothing", which is a completely
/// different statement from "nobody managed to ask" — and the second one, shown as the first, is how
/// somebody concludes their work has been lost.
struct CloudFailureRow: View {
    let failure: CloudFailure
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failure.explanation)
                .font(.labBody(12))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if failure.isWorthRetrying {
                Button(action: onRetry) {
                    Text("Try again")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
