import SwiftUI

/// SCREEN-5 Settings — presented as `AppRouter`'s trailing overlay (NM-8),
/// not a `.sheet`. T13 built the FUNCTIONAL subset (palette/units/gender/
/// planet rows wired to `PATCH /profile`, Sign out + Delete Account); T15
/// (this pass) adds the profile card, the Mission section (budget/macro
/// editor sheets), the version footer, and swaps in the real `Components/`
/// (`SegmentedToggle`/`SettingsRow`) now that they exist (T14) — the design-
/// spec traceability table's full "SettingsSheet + PATCH /profile + Sign out
/// + Delete (T13, T15)" row.
struct SettingsSheet: View {
    let store: AppStore
    let authService: AuthServiceProtocol
    let onDismiss: () -> Void
    let onSignedOut: () -> Void
    let onAccountDeleted: () -> Void

    @State private var isPerformingSystemAction = false
    @State private var systemActionError: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingReauthPrompt = false
    @State private var reauthEmail = ""
    @State private var reauthPassword = ""
    /// T15's Mission-section pass: the budget/macro editors are presented
    /// from here (plan.md Open Question 4's confirmed default: "numeric
    /// stepper sheets off the Settings rows").
    @State private var isShowingBudgetEditor = false
    @State private var isShowingMacroEditor = false

    /// Recolors this screen with the CALLER's own saved palette (once
    /// fetched) rather than the pre-auth default — Settings is only ever
    /// reached signed-in, so `store.profile` is populated by the time a user
    /// can open it in practice.
    /// T17: delegates to `AppStore.currentTheme` (the same expression this
    /// property used to compute independently) now that it's centralized —
    /// one fewer duplicate of the "recolor from `profile.palettePreset`"
    /// logic in the codebase.
    private var theme: Theme { store.currentTheme }

    var body: some View {
        ZStack {
            Theme.Neutral.screenBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
                    header
                    if let systemActionError {
                        Text(systemActionError)
                            .font(.orbit(.caption))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settings-error")
                    }
                    profileCard
                    missionSection
                    paletteSection
                    preferencesSection
                    systemSection
                    versionFooter
                }
                .padding(.top, Metrics.Spacing.contentTopPadding)
                .padding(.horizontal, Metrics.Spacing.contentSidePadding)
                .padding(.bottom, Metrics.Spacing.contentBottomPadding)
            }
        }
        .alert("Delete account?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("This permanently erases every Orbit record for your account. This can't be undone.")
        }
        .sheet(isPresented: $isShowingReauthPrompt) {
            ReauthenticationPromptView(
                email: $reauthEmail,
                password: $reauthPassword,
                isSubmitting: isPerformingSystemAction,
                onConfirm: {
                    Task { await performDelete(reauthenticatingWith: (email: reauthEmail, password: reauthPassword)) }
                },
                onCancel: { isShowingReauthPrompt = false }
            )
        }
        .sheet(isPresented: $isShowingBudgetEditor) { BudgetEditorSheet(store: store) }
        .sheet(isPresented: $isShowingMacroEditor) { MacroEditorSheet(store: store) }
    }

    // MARK: - Profile card (design-spec §4 SCREEN-5: "profile card (52pt
    // avatar, name, email, current-planet chip)") — T15's promised pass over
    // this T13 file.

    private static let planetNames = ["Ember", "Dune", "Titan", "Aurora", "Nova", "Zenith"]

    private var profileCard: some View {
        GlassCard {
            HStack(spacing: Metrics.Spacing.cardGap) {
                Avatar(
                    initials: AvatarInitials.initials(displayName: authService.currentUserDisplayName, email: authService.currentUserEmail),
                    size: .large,
                    theme: theme
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(authService.currentUserDisplayName?.isEmpty == false ? authService.currentUserDisplayName! : "Orbit Explorer")
                        .font(.orbit(.cardTitle))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                    if let email = authService.currentUserEmail {
                        Text(email)
                            .font(.orbit(.caption))
                            .foregroundStyle(Theme.Neutral.textMuted)
                    }
                    if let planetIndex = store.profile?.planetIndex, Self.planetNames.indices.contains(planetIndex) {
                        Text(Self.planetNames[planetIndex])
                            .font(.orbit(.micro))
                            .foregroundStyle(Theme.Neutral.textFaint)
                            .padding(.horizontal, Metrics.Spacing.cardPaddingMin / 2)
                            .background(Theme.Neutral.chipFill)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Mission (budget/macro-split editors off numeric-stepper sheets
    // — plan.md Open Question 4's confirmed default). The design's
    // "Adaptive-targets toggle" has no backing engine yet (docs/roadmap.md:
    // adaptive diet coach is a future run, same deferral `FuelView`'s static
    // coach message already documents) — omitted rather than wiring a toggle
    // with no real effect (code-standards: "no dead flexibility").

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
            SectionLabelText("Mission")
            SettingsRow(
                title: "Daily budget \u{00b7} \(store.profile.map { "\(NumberDisplay.formatted($0.kcalBudget)) kcal" } ?? "")",
                kind: .chevron(action: { isShowingBudgetEditor = true }),
                theme: theme
            )
            SettingsRow(
                title: "Macro split \u{00b7} \(store.profile.map { "\($0.proteinPct)P/\($0.carbPct)C/\($0.fatPct)F" } ?? "")",
                kind: .chevron(action: { isShowingMacroEditor = true }),
                theme: theme
            )
        }
    }

    // MARK: - Version footer

    private var versionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9"
        return Text("ORBIT v\(version)")
            .font(.orbit(.micro))
            .foregroundStyle(Theme.Neutral.textFaint)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.orbit(.cardTitle))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                    .frame(minWidth: Metrics.HitTarget.minimum, minHeight: Metrics.HitTarget.minimum)
            }
            .accessibilityIdentifier("settings-back")
            .accessibilityLabel("Close Settings")

            Text("Settings")
                .font(.orbit(.screenTitle))
                .foregroundStyle(Theme.Neutral.textPrimary)

            Spacer()
        }
    }

    // MARK: - Palette (SCREEN-5: 4-preset picker)

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
            SectionLabelText("Palette")
            HStack(spacing: Metrics.Spacing.cardGap) {
                ForEach(PalettePreset.allCases) { preset in
                    paletteSwatch(preset)
                }
            }
        }
    }

    private func paletteSwatch(_ preset: PalettePreset) -> some View {
        let isSelected = store.profile?.palettePreset == preset.apiValue
        return Button {
            Task { await updateProfile(ProfileUpdate(palettePreset: preset.apiValue)) }
        } label: {
            Circle()
                .fill(Theme(preset: preset).primary)
                .overlay(
                    Circle().stroke(Theme.Neutral.textPrimary, lineWidth: isSelected ? 2 : 0)
                )
                .frame(width: 32, height: 32)
                .frame(minWidth: Metrics.HitTarget.minimum, minHeight: Metrics.HitTarget.minimum)
        }
        .accessibilityIdentifier("settings-palette-\(preset.rawValue)")
        .accessibilityLabel(Text(preset.rawValue.capitalized))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Preferences: units only. design-spec §4 SCREEN-5 names
    // "Preferences (Units segmented, Reminders toggle, Haptics toggle)".
    // Reminders/Haptics are omitted here: neither has any backing capability
    // yet (no notification scheduling, no haptic-feedback wiring anywhere in
    // this run, and no schema field to persist them) — a toggle with no real
    // effect is dead flexibility (code-standards), not fidelity, so this is
    // a deliberate, documented gap rather than a fabricated control. The
    // gender/"Figure" toggle T13 placed here as a placeholder MOVED to
    // `BodyView`'s own M/W toggle instead — design-spec CMP-9's actual usage
    // list names M/W on Body, not Settings — both read/write the SAME
    // `profile.gender` field, so this is a fidelity correction, not a lost
    // capability. Likewise the planet PICKER moved to `HomeView`'s "Your
    // system" card (CMP-10's actual usage list names Home only); this screen
    // shows the current planet as a read-only chip on the profile card
    // instead, per design-spec §4.

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
            SectionLabelText("Preferences")
            unitsRow
        }
    }

    private var unitsRow: some View {
        SegmentedToggle(options: ["metric", "imperial"], selection: unitsBinding) {
            $0 == "metric" ? "Metric" : "Imperial"
        }
        .accessibilityIdentifier("settings-units")
    }

    private var unitsBinding: Binding<String> {
        Binding(
            get: { store.profile?.units ?? "imperial" },
            set: { newValue in Task { await updateProfile(ProfileUpdate(units: newValue)) } }
        )
    }

    // MARK: - System (Sign out / Delete account — AC5 / AC34)

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
            SectionLabelText("System")

            SettingsRow(title: "Sign out", kind: .action(action: { Task { await signOut() } }), theme: theme)
                .disabled(isPerformingSystemAction)
                .accessibilityIdentifier("settings-sign-out")

            SettingsRow(
                title: "Delete Account",
                kind: .action(isDestructive: true, action: { isShowingDeleteConfirmation = true }),
                theme: theme
            )
            .disabled(isPerformingSystemAction)
            .accessibilityIdentifier("settings-delete-account")
        }
    }

    // MARK: - Actions

    private func updateProfile(_ update: ProfileUpdate) async {
        do {
            try await store.updateProfile(update)
        } catch {
            systemActionError = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }

    /// AC34's exact ordering (`POST /me/signout` THEN Keychain clear THEN the
    /// Firebase SDK's own `signOut()`) is enforced inside
    /// `AuthService.signOut()` itself (T12's `FirebaseAuthService`) — this
    /// method just calls through and propagates the resulting
    /// session-ended state up to `RootView`.
    private func signOut() async {
        isPerformingSystemAction = true
        defer { isPerformingSystemAction = false }
        do {
            try await authService.signOut()
            onDismiss()
            onSignedOut()
        } catch {
            systemActionError = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }

    /// AC5: erases every domain row + the Firebase identity via `DELETE
    /// /me`. A stale `auth_time` (ASVS 7.5.1's `require_fresh_reauth` guard)
    /// surfaces as `.unauthorized` on the FIRST attempt
    /// (`reauthentication == nil`) — that's the signal to prompt for
    /// credentials and retry exactly once; `AppStore.deleteAccount` (T12)
    /// already implements the retry-once mechanics, this method just
    /// supplies the reauthentication prompt around it.
    private func performDelete(reauthenticatingWith reauthentication: (email: String, password: String)? = nil) async {
        isPerformingSystemAction = true
        systemActionError = nil
        defer { isPerformingSystemAction = false }
        do {
            try await store.deleteAccount(authService: authService, reauthenticatingWith: reauthentication)
            isShowingReauthPrompt = false
            onDismiss()
            onAccountDeleted()
        } catch AppError.unauthorized where reauthentication == nil {
            isShowingReauthPrompt = true
        } catch {
            isShowingReauthPrompt = false
            systemActionError = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}

/// A minimal section-header label matching design-spec §3 (10.5pt,
/// semibold, 0.18em tracking, uppercase, muted) — a placeholder for
/// `Components/SectionLabel` (T14), scoped the same way
/// `OrbitPrimaryButtonStyle` (`SignInView.swift`) is: built only from
/// already-existing DesignSystem tokens, not a new component-library entry.
private struct SectionLabelText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.orbit(.sectionLabel))
            .tracking(OrbitTextStyle.sectionLabel.trackingEm * OrbitTextStyle.sectionLabel.size)
            .foregroundStyle(Theme.Neutral.textMuted)
    }
}

/// The fresh-reauthentication prompt `AppStore.deleteAccount` needs when the
/// server rejects the first delete attempt for a stale `auth_time` (ASVS
/// 7.5.1) — a minimal password re-entry sheet, not a re-implementation of
/// `SignInView` (this is a narrow, single-purpose confirmation step, using
/// plain `Form`/`TextField` rather than the DesignSystem-styled
/// `OrbitTextFieldRow`, since it's a native-system confirmation sheet, not a
/// depicted or extended-design screen).
private struct ReauthenticationPromptView: View {
    @Binding var email: String
    @Binding var password: String
    let isSubmitting: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm your identity to delete your account") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("reauth-email")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("reauth-password")
                }
            }
            .navigationTitle("Re-authenticate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive, action: onConfirm)
                        .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                        .accessibilityIdentifier("reauth-confirm-delete")
                }
            }
        }
    }
}
