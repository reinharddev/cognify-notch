import AppKit
import NotchDock
import SwiftUI
import WebKit

// Playground skin Mimik di Pengaturan > Skin: pratinjau wajah langsung dan semua pilihannya (preset, warna, bentuk,
// opsi, suasana, efek, reaksi), seperti playground bbot. Pilihan disimpan di `SkinManager.mimik` dan dikirim ke skin
// (di desktop dan di pratinjau ini) sebagai `config`; lihat Skins/mimik/index.html.

struct MimikStyle: Codable, Equatable {
    var preset = "default"
    var skin = "#000000"
    var ink = "#e9ebec"
    var ring = "#34363a"
    var type = "round"
    var mouth = false
    var pupils = false
    var follow = true
    var blink = true
    var wander = true
    /// "auto" = mengikuti harimu (musik, jam, tugas); selain itu satu ekspresi tetap.
    var mood = "auto"
    var gloss = false
    var rim = false
    var glow = false
    var scan = false
    var hue = false
}

struct MimikPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var style: MimikStyle
}

enum MimikCatalog {
    struct Preset { let id: String; let name: String; let skin: String; let ink: String; let ring: String }
    static let presets: [Preset] = [
        Preset(id: "default", name: "Default", skin: "#000000", ink: "#e9ebec", ring: "#34363a"),
        Preset(id: "inverted", name: "Inverted", skin: "#f2f2f2", ink: "#111111", ring: "#cfcfcf"),
        Preset(id: "acid", name: "Acid", skin: "#0b0f00", ink: "#c6ff00", ring: "#4a5a00"),
        Preset(id: "sky", name: "Sky", skin: "#0b2a4a", ink: "#bfe6ff", ring: "#2f6fa8"),
        Preset(id: "paper", name: "Paper", skin: "#f5efe1", ink: "#2b2620", ring: "#cbbf9f"),
        Preset(id: "ember", name: "Ember", skin: "#1a0a05", ink: "#ff7a2f", ring: "#6b2a10"),
    ]
    static let shapes: [(id: String, id_: String, en: String)] = [
        ("round", "Bulat", "Round"), ("robot", "Robot", "Robot"), ("cat", "Kucing", "Cat"), ("ghost", "Hantu", "Ghost"),
        ("blob", "Gumpal", "Blob"), ("alien", "Alien", "Alien"), ("bear", "Beruang", "Bear"),
    ]
    static let moods = ["idle", "content", "relieved", "happy", "joy", "excited", "love", "pleading", "shy", "surprised", "scared", "curious",
                        "confused", "dizzy", "thinking", "focus", "suspicious", "unimpressed", "smug", "sly", "bored", "exasperated", "worried",
                        "guilty", "sad", "disgusted", "annoyed", "angry", "sleepy", "sleep", "laugh", "cry", "sob", "starstruck", "dead", "cool",
                        "nervous", "embarrassed", "blush", "proud", "hopeful", "determined", "mischievous", "skeptical", "tired", "hurt", "grumpy",
                        "dazed", "mindblown", "lonely", "bliss"]
    static let reactions = ["blink", "wink", "nod", "shake", "bounce", "pop", "boing", "spin", "jitter"]

    /// Warna acak yang serasi dan selalu terbaca (kontras kepala dan mata minimal 7:1); lihat `MimikPalette`.
    static func surprise() -> (skin: String, ink: String, ring: String) {
        let c = MimikPalette.random()
        return (c.skin, c.ink, c.ring)
    }
}

// MARK: - Pratinjau

/// Salinan skin Mimik di dalam Pengaturan. Memakai skema skin:// yang sama dengan jendela di desktop, jadi tampilannya identik.
struct SkinPreviewView: NSViewRepresentable {
    let info: SkinInfo
    @ObservedObject var skins: SkinManager

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = false
        var pending = ""
        weak var web: WKWebView?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if !pending.isEmpty { webView.evaluateJavaScript("window.cognify._cfg(\(pending))", completionHandler: nil) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "skin" ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SkinScheme(root: info.folder, entry: info.entry), forURLScheme: "skin")
        config.userContentController.addUserScript(WKUserScript(source: SkinWindow.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        context.coordinator.pending = skins.configJSON()
        web.load(URLRequest(url: URL(string: "skin://app/")!))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let json = skins.configJSON()
        context.coordinator.pending = json
        if context.coordinator.loaded { web.evaluateJavaScript("window.cognify._cfg(\(json))", completionHandler: nil) }
    }
}

// MARK: - Susunan chip

struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

private struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(on ? Color.primary : Color.primary.opacity(0.08)))
                .foregroundStyle(on ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct Caption: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary) }
}

private func hexColor(_ hex: Binding<String>, _ onChange: @escaping () -> Void) -> Binding<Color> {
    Binding(
        get: {
            var h = hex.wrappedValue; if h.hasPrefix("#") { h.removeFirst() }
            let v = UInt32(h, radix: 16) ?? 0
            return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
        },
        set: { color in
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
            hex.wrappedValue = String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            onChange()
        })
}

// MARK: - Playground

struct MimikPlayground: View {
    @ObservedObject var skins: SkinManager
    let info: SkinInfo
    @State private var presetName = ""

    private func savePreset() {
        skins.savePreset(named: presetName)
        presetName = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                SkinPreviewView(info: info, skins: skins)
                    .frame(width: 190, height: 190)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 16) {
                    group(L("Preset", "Preset")) {
                        ChipFlow {
                            ForEach(MimikCatalog.presets, id: \.id) { preset in
                                Chip(title: preset.name, on: skins.mimik.preset == preset.id) {
                                    skins.mimik.preset = preset.id
                                    skins.mimik.skin = preset.skin; skins.mimik.ink = preset.ink; skins.mimik.ring = preset.ring
                                }
                            }
                            Chip(title: L("Acak", "Surprise me"), on: skins.mimik.preset == "surprise") {
                                let c = MimikCatalog.surprise()
                                skins.mimik.preset = "surprise"
                                skins.mimik.skin = c.skin; skins.mimik.ink = c.ink; skins.mimik.ring = c.ring
                            }
                            ForEach(skins.mimikPresets) { saved in
                                Chip(title: saved.name, on: skins.mimik.preset == "saved:" + saved.id.uuidString) { skins.apply(saved) }
                                    .contextMenu { Button(L("Hapus gaya ini", "Delete this style"), role: .destructive) { skins.deletePreset(saved.id) } }
                            }
                        }
                        // Label di atas, bukan di kiri kolom: di jendela Pengaturan yang sempit label di kiri terpotong ("Simpan gay…").
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Simpan gaya ini", "Save this style")).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField("", text: $presetName, prompt: Text(L("Nama gaya", "Style name")))
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 110, maxWidth: 220)
                                    .onSubmit(savePreset)
                                Button(L("Simpan", "Save"), action: savePreset)
                                    .fixedSize()
                                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        if !skins.mimikPresets.isEmpty {
                            Text(L("Klik kanan gaya buatanmu untuk menghapusnya.", "Right-click one of your styles to delete it."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    group(L("Warna", "Colour")) {
                        HStack(spacing: 18) {
                            swatch(L("Kepala", "Head"), $skins.mimik.skin)
                            swatch(L("Mata", "Eyes"), $skins.mimik.ink)
                            swatch(L("Cincin", "Ring"), $skins.mimik.ring)
                        }
                    }
                    group(L("Bentuk", "Shape")) {
                        ChipFlow {
                            ForEach(MimikCatalog.shapes, id: \.id) { shape in
                                Chip(title: L(shape.id_, shape.en), on: skins.mimik.type == shape.id) { skins.mimik.type = shape.id }
                            }
                        }
                    }
                }
            }
            group(L("Opsi", "Options")) {
                ChipFlow {
                    Chip(title: L("Gambar mulut", "Draw a mouth"), on: skins.mimik.mouth) { skins.mimik.mouth.toggle() }
                    Chip(title: L("Pupil dalam", "Inner pupils"), on: skins.mimik.pupils) { skins.mimik.pupils.toggle() }
                    Chip(title: L("Ikuti kursor", "Follow cursor"), on: skins.mimik.follow) { skins.mimik.follow.toggle() }
                    Chip(title: L("Berkedip", "Blink"), on: skins.mimik.blink) { skins.mimik.blink.toggle() }
                    Chip(title: L("Melirik sendiri", "Idle wander"), on: skins.mimik.wander) { skins.mimik.wander.toggle() }
                }
            }
            group(L("Suasana", "Mood")) {
                ChipFlow {
                    Chip(title: L("Otomatis", "Auto"), on: skins.mimik.mood == "auto") { skins.mimik.mood = "auto" }
                    ForEach(MimikCatalog.moods, id: \.self) { mood in
                        Chip(title: mood, on: skins.mimik.mood == mood) { skins.mimik.mood = mood }
                    }
                }
                Text(L("Otomatis: wajah mengikuti harimu (musik, jam, tugas). Pilih satu untuk menetapkannya.", "Auto: the face follows your day (music, time, tasks). Pick one to lock it."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            group(L("Efek", "Effects")) {
                ChipFlow {
                    Chip(title: L("Kilap", "Gloss"), on: skins.mimik.gloss) { skins.mimik.gloss.toggle() }
                    Chip(title: L("Tepi terang", "Rim light"), on: skins.mimik.rim) { skins.mimik.rim.toggle() }
                    Chip(title: L("Pendar", "Glow"), on: skins.mimik.glow) { skins.mimik.glow.toggle() }
                    Chip(title: L("Garis scan", "Scanlines"), on: skins.mimik.scan) { skins.mimik.scan.toggle() }
                    Chip(title: L("Pelangi", "Rainbow"), on: skins.mimik.hue) { skins.mimik.hue.toggle() }
                }
            }
            group(L("Coba reaksi", "Try a reaction")) {
                ChipFlow {
                    ForEach(MimikCatalog.reactions, id: \.self) { name in
                        Chip(title: name, on: false) { skins.react(name) }
                    }
                }
            }
            HStack {
                Spacer()
                Button(L("Kembalikan ke bawaan", "Reset to default")) { skins.mimik = MimikStyle() }
                    .disabled(skins.mimik == MimikStyle())
            }
        }
        .padding(.vertical, 6)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Caption(text: title); content() }
    }

    private func swatch(_ title: String, _ hex: Binding<String>) -> some View {
        VStack(spacing: 4) {
            ColorPicker("", selection: hexColor(hex) { skins.mimik.preset = "custom" }, supportsOpacity: false).labelsHidden()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
