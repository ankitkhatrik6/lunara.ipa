import SwiftUI

struct LyricsSettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var prefs = LyricsPrefs.shared
    @ObservedObject private var look = LookFeel.shared

    @State private var showProviders = false
    @State private var showPriority = false
    @State private var showAnimation = false
    @State private var showTextSize = false
    @State private var showLineSpacing = false
    @State private var showPosition = false
    @State private var showBetaConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                group("Sources") {
                    link("text.book.closed", "Lyrics providers",
                         "Choose which services are searched") { showProviders = true }
                    divider
                    link("list.number", "Provider priority",
                         "Which source wins when several have the song") { showPriority = true }
                    divider
                    NavigationLink { RomanizationView() } label: {
                        HStack(spacing: 14) {
                            icon("character")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Romanization")
                                    .font(.lunara(15, .medium))
                                    .foregroundStyle(palette.onSurface)
                                Text(RomanizePrefs.shared.enabled ? "On" : "Off")
                                    .font(.lunara(12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.lunara(12, .semibold))
                                .foregroundStyle(palette.onSurfaceVariant.opacity(0.7))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    divider
                    NavigationLink { AISettingsView() } label: {
                        HStack(spacing: 14) {
                            icon("character.book.closed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI translation")
                                    .font(.lunara(15, .medium))
                                    .foregroundStyle(palette.onSurface)
                                Text(AIPrefs.shared.enabled ? "On" : "Off")
                                    .font(.lunara(12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.lunara(12, .semibold))
                                .foregroundStyle(palette.onSurfaceVariant.opacity(0.7))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                group("Display") {
                    toggle("sparkles", "Lunara lyrics style",
                           "Our word-by-word renderer, with per-line focus and instrumental breaks",
                           badge: "BETA",
                           isOn: Binding(
                               get: { prefs.lunaraStyle },
                               set: { on in
                                   if on { showBetaConfirm = true } else { prefs.lunaraStyle = false }
                               }))

                    if !prefs.lunaraStyle {
                        divider
                        toggle("light.max", "Glow effect",
                               "Adds a glowing animation and bounce to the active line",
                               isOn: $prefs.glowEffect)
                        divider
                        link("wand.and.stars", "Animation style",
                             prefs.animation.title) { showAnimation = true }
                        divider
                        link("textformat.size", "Text size",
                             "\(Int(prefs.textSize.rounded())) pt") { showTextSize = true }
                        divider
                        link("arrow.up.and.down.text.horizontal", "Line spacing",
                             String(format: "%.1f", prefs.lineSpacing)) { showLineSpacing = true }
                    }

                    divider
                    link("text.alignleft", "Text position",
                         look.lyricsPosition.title) { showPosition = true }
                    divider
                    toggle("person.wave.2", "Respect agent positioning",
                           "Align lines by their role, so background vocals sit apart",
                           isOn: $prefs.respectAgentPositioning)
                    divider
                    toggle("hand.tap", "Tap to seek",
                           "Tap a line to jump to that moment",
                           isOn: $prefs.clickToSeek)
                    divider
                    toggle("arrow.down.doc", "Auto scroll",
                           "Follow the song as it plays",
                           isOn: $prefs.autoScroll)
                    divider
                    toggle("rectangle.topthird.inset.filled", "Hide the status bar",
                           "While lyrics are full screen",
                           isOn: $prefs.hideStatusBarFullscreen)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Lyrics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProviders) {
            LyricsProviderSheet().environment(\.palette, palette)
        }
        .sheet(isPresented: $showPriority) {
            LyricsPrioritySheet().environment(\.palette, palette)
        }
        .sheet(isPresented: $showAnimation) {
            EnumPickerSheet(title: "Animation style",
                            options: LyricsAnimation.allCases,
                            label: { $0.title },
                            selection: $prefs.animation)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showPosition) {
            EnumPickerSheet(title: "Text position",
                            options: LyricsPosition.allCases,
                            label: { $0.title },
                            selection: $look.lyricsPosition)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showTextSize) {
            SliderSheet(title: "Text size", value: $prefs.textSize,
                        range: LyricsPrefs.textSizeRange,
                        reset: LyricsPrefs.defaultTextSize,
                        readout: { "\(Int($0.rounded())) pt" })
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showLineSpacing) {
            SliderSheet(title: "Line spacing", value: $prefs.lineSpacing,
                        range: LyricsPrefs.lineSpacingRange,
                        reset: LyricsPrefs.defaultLineSpacing,
                        readout: { String(format: "%.1f", $0) })
                .environment(\.palette, palette)
        }
        .alert("Lunara lyrics style", isPresented: $showBetaConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") { prefs.lunaraStyle = true }
        } message: {
            Text("This renderer is still in beta. It highlights each word as it's "
                 + "sung, marks instrumental breaks, and sets its own text size, "
                 + "so those options are hidden while it's on.")
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.lunara(12, .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var divider: some View {
        Divider().overlay(palette.onSurface.opacity(0.06)).padding(.leading, 56)
    }

    private func link(_ symbol: String, _ title: String, _ subtitle: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.lunara(15, .medium))
                        .foregroundStyle(palette.onSurface)
                    Text(subtitle).font(.lunara(12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.lunara(12, .semibold))
                    .foregroundStyle(palette.onSurfaceVariant.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ symbol: String, _ title: String, _ subtitle: String,
                        badge: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.lunara(15, .medium))
                        .foregroundStyle(palette.onSurface)
                    if let badge {
                        Text(badge)
                            .font(.lunara(9, .bold))
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(palette.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle).font(.lunara(12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(palette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.lunara(15))
            .foregroundStyle(palette.accent)
            .frame(width: 26)
    }
}

// MARK: - Provider on/off

private struct LyricsProviderSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefs = LyricsPrefs.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(LyricsProvider.allCases.enumerated()), id: \.element.id) { i, provider in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.title)
                                    .font(.lunara(15, .medium))
                                    .foregroundStyle(palette.onSurface)
                                Text(provider.blurb)
                                    .font(.lunara(12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            Spacer(minLength: 8)
                            Toggle("", isOn: Binding(
                                get: { prefs.isEnabled(provider) },
                                set: { prefs.enabled[provider.rawValue] = $0 }))
                                .labelsHidden().tint(palette.accent)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < LyricsProvider.allCases.count - 1 {
                            Divider().overlay(palette.onSurface.opacity(0.06))
                        }
                    }
                }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)

                Text("At least one source stays on. If every provider misses a "
                     + "song, its lyrics simply aren't available.")
                    .font(.lunara(12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.horizontal, 22).padding(.top, 12)
            }
            .padding(.top, 8)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Lyrics providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
        }
    }
}

// MARK: - Provider priority

private struct LyricsPrioritySheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefs = LyricsPrefs.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(prefs.order, id: \.self) { name in
                    let provider = LyricsProvider(rawValue: name)
                    let on = provider.map(prefs.isEnabled) ?? false
                    HStack(spacing: 12) {
                        Text(provider?.title ?? name)
                            .font(.lunara(15, .medium))
                            .foregroundStyle(on ? palette.onSurface
                                                : palette.onSurfaceVariant.opacity(0.6))
                        Spacer()
                        if !on {
                            Text("Off").font(.lunara(12))
                                .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
                        }
                    }
                    .listRowBackground(palette.surface)
                }
                .onMove { from, to in prefs.order.move(fromOffsets: from, toOffset: to) }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Provider priority")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
        }
    }
}

// MARK: - Shared pickers

struct EnumPickerSheet<Option: Identifiable & Equatable>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                        Button {
                            selection = option
                            dismiss()
                        } label: {
                            HStack {
                                Text(label(option))
                                    .font(.lunara(15))
                                    .foregroundStyle(palette.onSurface)
                                Spacer()
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.lunara(13, .bold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < options.count - 1 {
                            Divider().overlay(palette.onSurface.opacity(0.06))
                        }
                    }
                }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(16)
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct SliderSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let reset: Double
    let readout: (Double) -> String

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.lunara(18, .bold))
                .foregroundStyle(palette.onSurface)
            Text(readout(value))
                .font(.lunara(30, .bold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
            Slider(value: $value, in: range).tint(palette.accent)
            HStack {
                Button("Reset") { value = reset }
                    .font(.lunara(15, .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.lunara(15, .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.surface)
        .presentationBackground(palette.surface)
        .presentationDetents([.height(280)])
    }
}
