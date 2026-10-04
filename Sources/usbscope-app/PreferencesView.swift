import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// The `⌘,` preferences window: default view, refresh cadence, notifications,
/// appearance, language and the default grouping. Every change is persisted
/// immediately through `AppState`.
///
/// Deliberately not a `Form`: the grouped macOS form style packs its rows
/// tightly. A hand-laid card gives every row a full-width control, a fixed
/// label column and room to breathe.
struct PreferencesView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section(L(.prefGeneral, lang)) {
                    row(L(.prefDefaultView, lang)) {
                        Picker("", selection: $state.view) {
                            ForEach(AppView.allCases) { view in
                                Text(L(.of(view), lang)).tag(view)
                            }
                        }
                        .labelsHidden()
                    }
                    row(L(.prefLanguage, lang)) {
                        Picker("", selection: $state.language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                    }
                    row(L(.prefAppearance, lang)) {
                        Picker("", selection: $state.appearance) {
                            ForEach(Appearance.allCases) { appearance in
                                Text(L(.of(appearance), lang)).tag(appearance)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                section(L(.prefAutoRefresh, lang)) {
                    row(L(.prefAutoRefresh, lang)) {
                        Toggle("", isOn: Binding(
                            get: { state.autoRefresh },
                            set: { state.setAutoRefresh($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    row(L(.prefInterval, lang)) {
                        Picker("", selection: Binding(
                            get: { state.interval },
                            set: { state.setInterval($0) }
                        )) {
                            ForEach(PREFERENCE_INTERVALS, id: \.self) { value in
                                Text(verbatim: Strings.seconds(Int(value), lang)).tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    row(L(.monitoringProfile, lang)) {
                        Picker("", selection: Binding(
                            get: { state.monitoringProfile },
                            set: { state.setMonitoringProfile($0) }
                        )) {
                            Text(L(.profileBalanced, lang)).tag(MonitoringProfile.balanced)
                            Text(L(.profileLowPower, lang)).tag(MonitoringProfile.lowPower)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Text(L(.lowPowerNote, lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                section(L(.prefNotifications, lang)) {
                    row(L(.prefNotifications, lang)) {
                        Toggle("", isOn: Binding(
                            get: { state.notificationsEnabled },
                            set: { state.setNotifications($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    Text(notificationNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    row(L(.notificationDetail, lang)) {
                        Picker("", selection: Binding(
                            get: { state.notificationDetail },
                            set: { state.setNotificationDetail($0) }
                        )) {
                            Text(L(.fullDeviceDetails, state.language)).tag(NotificationDetail.full)
                            Text(L(.genericSummary, state.language)).tag(NotificationDetail.generic)
                            Text(L(.disabled, state.language)).tag(NotificationDetail.disabled)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                section(L(.prefGrouping, lang)) {
                    row(L(.prefGrouping, lang)) {
                        Picker("", selection: $state.groupField) {
                            ForEach([GroupField.none, .bus, .deviceClass, .speed]) { field in
                                Text(L(.of(field), lang)).tag(field)
                            }
                        }
                        .labelsHidden()
                    }
                }
                section(L(.securitySeverity, lang)) {
                    ForEach(Security.ruleIDs, id: \.self) { rule in
                        row(Strings.securityRuleLabel(rule, lang)) {
                            Picker("", selection: Binding(
                                get: { state.securitySeverity(for: rule)?.rawValue ?? "default" },
                                set: { value in
                                    state.setSecuritySeverity(
                                        value == "default" ? nil : FindingSeverity(rawValue: value),
                                        for: rule
                                    )
                                }
                            )) {
                                Text(L(.severityDefault, lang)).tag("default")
                                ForEach(FindingSeverity.allCases, id: \.rawValue) { severity in
                                    Text(Strings.securitySeverity(severity, lang)).tag(severity.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(width: 560)
        .frame(minHeight: 460)
    }

    // MARK: - Pieces

    /// Icon, name and version, so the window is recognisable at a glance.
    private var header: some View {
        HStack(spacing: 14) {
            if let icon = AboutIcon.image {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AboutInfo.name).font(.title3.weight(.semibold))
                Text(Strings.versionLabel(AboutIcon.version, state.language))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// A titled card with generous internal spacing.
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 14) { content() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
    }

    /// One setting: a fixed label column, then the control, full width.
    private func row<Content: View>(
        _ label: String, @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .frame(width: 170, alignment: .leading)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A short honest note about where banners are actually delivered.
    private var notificationNote: String {
        Bundle.main.bundleURL.pathExtension == "app"
            ? L(.notificationBundleNote, lang)
            : L(.notificationCheckoutNote, lang)
    }
}
