import AppKit
import MCGACore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var preferences: AppPreferences
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tabButton(.general, title: preferences.text(.general), symbol: "gearshape")
                tabButton(.parsers, title: preferences.text(.parsers), symbol: "curlybraces")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))
            Divider()
            switch tab {
            case .general:
                GeneralSettingsView(preferences: preferences)
            case .parsers:
                ParserSettingsView(model: model, preferences: preferences)
            }
        }
        .frame(width: 560, height: 620)
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private func tabButton(_ value: SettingsTab, title: String, symbol: String) -> some View {
        let isSelected = tab == value
        return Button {
            tab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentText : Color.mutedText)
            .frame(width: 76, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum SettingsTab {
    case general
    case parsers
}

struct GeneralSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section(preferences.text(.general)) {
                Picker(preferences.text(.language), selection: $preferences.language) {
                    Text(preferences.text(.chinese)).tag(AppLanguage.zh)
                    Text(preferences.text(.english)).tag(AppLanguage.en)
                }

                Picker(preferences.text(.theme), selection: $preferences.theme) {
                    Text(preferences.text(.system)).tag(AppTheme.system)
                    Text(preferences.text(.light)).tag(AppTheme.light)
                    Text(preferences.text(.dark)).tag(AppTheme.dark)
                }

                Toggle(isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                )) {
                    Text(preferences.text(.launchAtLogin))
                }

                if preferences.launchAtLoginNeedsApproval {
                    Text(preferences.text(.launchAtLoginNeedsApproval))
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Stepper(value: $preferences.historyRetentionDays, in: 0...3650) {
                    HStack {
                        Text(preferences.text(.historyRetentionDays))
                        Spacer()
                        Text(preferences.historyRetentionDays == 0
                            ? preferences.text(.historyRetentionUnlimited)
                            : String(format: preferences.text(.historyRetentionDaysValue), preferences.historyRetentionDays)
                        )
                        .foregroundStyle(Color.mutedText)
                    }
                }
            }

            Section(preferences.text(.shortcut)) {
                Toggle(preferences.text(.historyShortcutEnabled), isOn: $preferences.historyShortcutEnabled)

                if preferences.historyShortcutEnabled {
                    LabeledContent(preferences.text(.historyShortcut)) {
                        ShortcutRecorderView(
                            shortcut: $preferences.historyShortcut,
                            placeholder: preferences.text(.recordShortcut),
                            recordingText: preferences.text(.recordingShortcut)
                        )
                        .frame(width: 180, height: 24)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

struct ParserSettingsView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var preferences: AppPreferences
    @State private var query = ""

    var body: some View {
        let infos = model.parserInfos
        let groups = parserGroups(infos)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.mutedText)
                    TextField(preferences.text(.searchParsers), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

                Text(String(
                    format: preferences.text(.enabledParsersCount),
                    infos.filter { preferences.isParserEnabled($0.name) }.count,
                    infos.count
                ))
                .font(.system(size: 12))
                .foregroundStyle(Color.mutedText)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            if groups.isEmpty {
                ContentUnavailableView(preferences.text(.noMatchingParsers), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups, id: \.category) { group in
                            groupView(group)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    private struct ParserGroup {
        let category: ParserCategory
        let infos: [ParserInfo]
    }

    private func parserGroups(_ infos: [ParserInfo]) -> [ParserGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? infos : infos.filter { matches($0, query) }
        return ParserCategory.allCases.compactMap { category in
            let items = matching.filter { $0.category == category }
            return items.isEmpty ? nil : ParserGroup(category: category, infos: items)
        }
    }

    private func matches(_ info: ParserInfo, _ query: String) -> Bool {
        var fields = [info.name, description(for: info)]
        for example in info.examples {
            fields.append(example.input)
            fields.append(expected(for: example))
        }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func groupView(_ group: ParserGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(preferences.text(group.category.title))
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
                Text(String(format: preferences.text(.parserGroupCount), group.infos.count))
                    .font(.system(size: 12))
                    .fixedSize()
                Spacer(minLength: 8)
                if group.category == .custom {
                    Text((ParserEngine.customParserConfigURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([ParserEngine.customParserConfigURL])
                    } label: {
                        Label(preferences.text(.showInFinder), systemImage: "folder")
                    }
                    .controlSize(.small)
                }
            }
            .foregroundStyle(Color.mutedText)
            .padding(.horizontal, 4)
            .frame(minHeight: 24)

            VStack(spacing: 0) {
                ForEach(Array(group.infos.enumerated()), id: \.element.id) { index, info in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    parserRow(info)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    private func parserRow(_ info: ParserInfo) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(description(for: info))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(info.examples) { example in
                    HStack(spacing: 6) {
                        Text(example.input.replacingOccurrences(of: "\n", with: " · "))
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.mutedText)
                        Text(expected(for: example))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.mutedText)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(
                get: { preferences.isParserEnabled(info.name) },
                set: { preferences.setParser(info.name, enabled: $0) }
            )) {
                Text(info.name)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func description(for info: ParserInfo) -> String {
        preferences.language == .zh ? info.zhDescription : info.enDescription
    }

    private func expected(for example: ParserExample) -> String {
        preferences.language == .zh ? example.zhExpected : example.enExpected
    }
}
