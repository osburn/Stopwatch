import SwiftUI
import AppKit

// MARK: - Helpers

func formatTime(_ t: TimeInterval) -> String {
    let cs = Int(max(0, t) * 100)
    let h = cs / 360000
    let m = (cs / 6000) % 60
    let s = (cs / 100) % 60
    let c = cs % 100
    return h > 0
        ? String(format: "%d:%02d:%02d.%02d", h, m, s, c)
        : String(format: "%02d:%02d.%02d", m, s, c)
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}

let systemMonoName = "System Monospaced"
let defaultFontName = "Arial"

func timerFont(name: String, size: Double) -> Font {
    if name == systemMonoName {
        return .system(size: size, weight: .medium, design: .monospaced)
    }
    return .custom(name, size: size)
}

let availableFontFamilies: [String] = {
    [systemMonoName] + NSFontManager.shared.availableFontFamilies.sorted()
}()

// MARK: - Colored button style

struct ColoredButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .opacity(isEnabled ? 1 : 0.35)
    }
}

let stopColor  = Color(hex: "#B5483F")   // muted red
let startColor = Color(hex: "#3F8F5A")   // muted green
let lapColor   = Color(hex: "#3F72B5")   // muted blue
let resetColor = Color(hex: "#B8922F")   // muted yellow/amber

// MARK: - File logging (~/.StopwatchTimes.csv)

enum TimeLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".StopwatchTimes.csv")

    static func write(timer: String, event: String, lapNumber: Int?, lapTime: TimeInterval?, total: TimeInterval) {
        let iso = ISO8601DateFormatter().string(from: Date())
        let name = "\"" + timer.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let line = [iso, name, event,
                    lapNumber.map(String.init) ?? "",
                    lapTime.map(formatTime) ?? "",
                    formatTime(total)].joined(separator: ",") + "\n"

        if !FileManager.default.fileExists(atPath: url.path) {
            let header = "timestamp,timer,event,lap_number,lap_time,total_time\n"
            try? header.data(using: .utf8)?.write(to: url)
        }
        if let handle = try? FileHandle(forWritingTo: url), let data = line.data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }
}

// MARK: - Model

struct Lap: Identifiable {
    let id = UUID()
    let number: Int
    let lapTime: TimeInterval
    let total: TimeInterval
}

final class StopTimer: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var accumulated: TimeInterval = 0
    @Published var startedAt: Date? = nil
    @Published var laps: [Lap] = []

    init(name: String) { self.name = name }

    var isRunning: Bool { startedAt != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    func start() {
        guard !isRunning else { return }
        startedAt = Date()
        TimeLog.write(timer: name, event: "start", lapNumber: nil, lapTime: nil, total: accumulated)
    }

    func stop() {
        guard let s = startedAt else { return }
        accumulated += Date().timeIntervalSince(s)
        startedAt = nil
        TimeLog.write(timer: name, event: "stop", lapNumber: nil, lapTime: nil, total: accumulated)
    }

    func toggle() { isRunning ? stop() : start() }

    func lap() {
        guard isRunning else { return }
        let total = elapsed()
        let prev = laps.last?.total ?? 0
        let l = Lap(number: laps.count + 1, lapTime: total - prev, total: total)
        laps.append(l)
        TimeLog.write(timer: name, event: "lap", lapNumber: l.number, lapTime: l.lapTime, total: total)
    }

    func reset() {
        if isRunning { stop() }
        if accumulated > 0 {
            TimeLog.write(timer: name, event: "reset", lapNumber: nil, lapTime: nil, total: accumulated)
        }
        accumulated = 0
        laps = []
    }
}

final class TimerStore: ObservableObject {
    @Published var timers: [StopTimer] = [StopTimer(name: "Timer 1")]
    /// The timer that Space / Return act on. Falls back to the first timer.
    @Published var activeID: UUID? = nil

    var active: StopTimer? {
        timers.first(where: { $0.id == activeID }) ?? timers.first
    }

    func add() {
        let t = StopTimer(name: "Timer \(timers.count + 1)")
        timers.append(t)
    }

    func remove(_ t: StopTimer) {
        t.stop()
        timers.removeAll { $0.id == t.id }
    }
}

// MARK: - Views

struct TimerCard: View {
    @ObservedObject var timer: StopTimer
    let fontSize: Double
    let fontName: String
    let fontColor: Color
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    @FocusState private var nameFocused: Bool

    private func endEditing() {
        nameFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)   // clears the "selected" look
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $timer.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(fontColor.opacity(0.8))
                    .focused($nameFocused)
                    .onSubmit { endEditing() }     // Return commits the name only
                Spacer()
                Button(action: onDelete) { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .foregroundColor(fontColor.opacity(0.6))
                    .help("Remove timer")
            }

            TimelineView(.animation(minimumInterval: 0.01, paused: !timer.isRunning)) { ctx in
                Text(formatTime(timer.elapsed(at: ctx.date)))
                    .font(timerFont(name: fontName, size: fontSize))
                    .foregroundColor(fontColor)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Stop" : "Start") {
                    onActivate()
                    timer.toggle()
                }
                .buttonStyle(ColoredButtonStyle(color: timer.isRunning ? stopColor : startColor))

                Button("Lap") { onActivate(); timer.lap() }
                    .buttonStyle(ColoredButtonStyle(color: lapColor))
                    .disabled(!timer.isRunning)

                Button("Reset") { onActivate(); timer.reset() }
                    .buttonStyle(ColoredButtonStyle(color: resetColor))
                    .disabled(timer.accumulated == 0 && !timer.isRunning)
            }

            if !timer.laps.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(timer.laps.reversed()) { l in
                            HStack {
                                Text("Lap \(l.number)")
                                Spacer()
                                Text(formatTime(l.lapTime))
                                Spacer()
                                Text(formatTime(l.total)).opacity(0.7)
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(fontColor)
                        }
                    }
                }
                .frame(height: min(CGFloat(timer.laps.count) * 20 + 4, 100))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(fontColor.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(fontColor.opacity(isActive ? 0.35 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            endEditing()
            onActivate()
        }
        // Keyboard shortcuts for the active timer only. They are disabled while the
        // name field is being edited, so typing a space or pressing Return there
        // never touches the timer.
        .background(
            Group {
                if isActive {
                    Button("") { timer.toggle() }
                        .keyboardShortcut(.space, modifiers: [])
                    Button("") { timer.lap() }
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
            .disabled(nameFocused)
        )
    }
}

struct SettingsView: View {
    @Binding var fontSize: Double
    @Binding var fontName: String
    @Binding var fontHex: String
    @Binding var bgHex: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance").font(.headline)

            Picker("Font", selection: $fontName) {
                ForEach(availableFontFamilies, id: \.self) { fam in
                    Text(fam).tag(fam)
                }
            }

            HStack {
                Text("Font size: \(Int(fontSize)) px")
                Slider(value: $fontSize, in: 20...250, step: 1)
            }

            Text("01:23.45")
                .font(timerFont(name: fontName, size: 36))
                .foregroundColor(Color(hex: fontHex))
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: bgHex)))

            ColorPicker("Font color", selection: Binding(
                get: { Color(hex: fontHex) }, set: { fontHex = $0.hexString }))
            ColorPicker("Background color", selection: Binding(
                get: { Color(hex: bgHex) }, set: { bgHex = $0.hexString }))
            Divider()
            Text("Times are logged to:\n\(TimeLog.url.path)")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button("Reveal Log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([TimeLog.url])
                }
                Button("Open Log") { NSWorkspace.shared.open(TimeLog.url) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct ContentView: View {
    @StateObject private var store = TimerStore()
    @AppStorage("fontSize") private var fontSize: Double = 140
    @AppStorage("fontName") private var fontName: String = defaultFontName
    @AppStorage("fontHex") private var fontHex: String = "#FFFFFF"
    @AppStorage("bgHex") private var bgHex: String = "#1C1C1E"
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.add() } label: { Label("Add Timer", systemImage: "plus") }
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Settings")
            }
            .padding(10)

            VStack(spacing: 12) {
                ForEach(store.timers) { t in
                    TimerCard(timer: t,
                              fontSize: fontSize,
                              fontName: fontName,
                              fontColor: Color(hex: fontHex),
                              isActive: store.active?.id == t.id,
                              onActivate: { store.activeID = t.id },
                              onDelete: { store.remove(t) })
                }
            }
            .padding([.horizontal, .bottom], 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 700, maxWidth: .infinity)
        .background(Color(hex: bgHex).ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView(fontSize: $fontSize, fontName: $fontName,
                         fontHex: $fontHex, bgHex: $bgHex)
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct StopwatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("Stopwatch") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
