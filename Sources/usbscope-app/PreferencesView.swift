import SwiftUI
import UsbScopeUI

/// The `⌘,` preferences window: default view, refresh cadence, notifications,
/// appearance, language and the default grouping. Every change is persisted
/// immediately through `AppState`.
struct PreferencesView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        Form {
            Section(L(.prefGeneral, lang)) {
                Picker(L(.prefDefaultView, lang), selection: $state.view) {
                    ForEach(AppView.allCases) { view in
                        Text(L(.of(view), lang)).tag(view)
                    }
                }
                Picker(L(.prefLanguage, lang), selection: $state.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Picker(L(.prefAppearance, lang), selection: $state.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(L(.of(appearance), lang)).tag(appearance)
                    }
                }
            }

            Section(L(.prefAutoRefresh, lang)) {
                Toggle(
                    L(.prefAutoRefresh, lang),
                    isOn: Binding(get: { state.autoRefresh }, set: { state.setAutoRefresh($0) })
                )
                Picker(
                    L(.prefInterval, lang),
                    selection: Binding(get: { state.interval }, set: { state.setInterval($0) })
                ) {
                    ForEach(PREFERENCE_INTERVALS, id: \.self) { value in
                        Text("\(Int(value)) s").tag(value)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(L(.prefNotifications, lang)) {
                Toggle(
                    L(.prefNotifications, lang),
                    isOn: Binding(get: { state.notificationsEnabled }, set: { state.setNotifications($0) })
                )
                Text(notificationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L(.prefGrouping, lang)) {
                Picker(L(.prefGrouping, lang), selection: $state.groupField) {
                    ForEach([GroupField.none, .bus, .deviceClass, .speed]) { field in
                        Text(L(.of(field), lang)).tag(field)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// A short honest note about where banners are actually delivered.
    private var notificationNote: String {
        Bundle.main.bundleURL.pathExtension == "app"
            ? "Banners are posted for connecting and disconnecting devices."
            : "Silent in a checkout run: macOS only delivers notifications from an app bundle."
    }
}
