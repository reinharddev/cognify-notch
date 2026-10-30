import AppKit
import SwiftUI

// Antarmuka pembaruan kustom Cognify Notch, menggantikan jendela bawaan Sparkle.
//
// `UpdateDriver` adalah "user driver" Sparkle (protokol SPUUserDriver): Sparkle memanggilnya lewat runtime
// Objective-C, jadi tiap metode memakai nama selector yang persis sama dengan protokolnya (framework tidak
// di-link, lihat Updater.swift). Tampilannya SwiftUI dengan warna dan maskot Cognify Notch. Semua akses ke
// objek Sparkle (SUAppcastItem dll.) lewat KVC supaya tidak bergantung pada header.

// MARK: - Catatan rilis

struct NoteSection: Equatable {
    let version: String
    let lines: [String]
}

enum ReleaseNotes {
    /// Catatan rilis di appcast dua bahasa: `<div lang="id">…</div><div lang="en">…</div>`, tiap bahasa berisi
    /// `<h3>Versi X</h3><p>…</p>` (lihat scripts/release_notes.py). Bahasa dipilih sesuai pengaturan app;
    /// appcast lama tanpa `<div lang>` dibaca apa adanya.
    static func parse(html: String, english: Bool) -> [NoteSection] {
        let wanted = english ? "en" : "id"
        let langs = matches(#"<div[^>]*\blang="(\w+)"[^>]*>(.*?)</div>"#, in: html)
        if !langs.isEmpty {
            let pick = langs.first { $0.groups.first == wanted } ?? langs.first { $0.groups.first == "id" } ?? langs[0]
            return parse(section: pick.text)
        }
        return parse(section: html)
    }

    private static func parse(section html: String) -> [NoteSection] {
        let headings = matches(#"<h[1-4][^>]*>(.*?)</h[1-4]>"#, in: html)
        guard !headings.isEmpty else {
            let lines = paragraphs(in: html)
            return lines.isEmpty ? [] : [NoteSection(version: "", lines: lines)]
        }
        var sections: [NoteSection] = []
        for (i, h) in headings.enumerated() {
            let start = h.range.upperBound
            let end = i + 1 < headings.count ? headings[i + 1].range.lowerBound : html.endIndex
            sections.append(NoteSection(version: plain(h.text).replacingOccurrences(of: "Versi ", with: "").replacingOccurrences(of: "Version ", with: ""), lines: paragraphs(in: String(html[start..<end]))))
        }
        return sections
    }

    private static func paragraphs(in html: String) -> [String] {
        let ps = matches(#"<(?:p|li)[^>]*>(.*?)</(?:p|li)>"#, in: html).map { plain($0.text) }.filter { !$0.isEmpty }
        if !ps.isEmpty { return ps }
        let text = plain(html)
        return text.isEmpty ? [] : [text]
    }

    /// `text` = grup terakhir; `groups` = semua grup sebelumnya (mis. kode bahasa).
    private struct Match { let text: String; let groups: [String]; let range: Range<String.Index> }

    private static func matches(_ pattern: String, in s: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let whole = Range(m.range, in: s), m.numberOfRanges >= 2 else { return nil }
            let parts = (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
            guard let last = parts.last else { return nil }
            return Match(text: last, groups: Array(parts.dropLast()), range: whole)
        }
    }

    /// Buang tag HTML dan urai entitas umum.
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " ")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Model

@MainActor
final class UpdateModel: ObservableObject {
    enum Phase: Equatable {
        case checking, found, downloading, extracting, installing, upToDate, installed
        case failed(String)
    }

    @Published var phase: Phase = .checking
    @Published var currentVersion = ""
    @Published var newVersion = ""
    @Published var sections: [NoteSection] = []
    @Published var sizeText = ""
    /// Sudah terunduh (mis. oleh pembaruan otomatis): tombol utamanya langsung memasang.
    @Published var alreadyDownloaded = false
    @Published var progress: Double? = nil
    @Published var automatic = false

    var onInstall: () -> Void = {}
    var onLater: () -> Void = {}
    var onSkip: () -> Void = {}
    var onCancel: () -> Void = {}
    var onClose: () -> Void = {}
    var onToggleAutomatic: (Bool) -> Void = { _ in }
}

// MARK: - Warna dan maskot

private enum Brand {
    static let lavender = Color(red: 0.608, green: 0.549, blue: 1.0)
    static let lavenderDeep = Color(red: 0.494, green: 0.424, blue: 0.941)
    static let orange = Color(red: 1.0, green: 0.478, blue: 0.349)
    static let green = Color(red: 0.255, green: 0.690, blue: 0.498)
    static let yellow = Color(red: 1.0, green: 0.831, blue: 0.318)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.09)
}

/// Ikon Cognify Notch: kotak lavender, tiga lingkaran warna, dan tab hitam bermata yang berkedip.
struct NotchMascot: View {
    var size: CGFloat = 72
    var blink = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !blink)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Berkedip singkat tiap ±3,4 detik.
            let phase = t.truncatingRemainder(dividingBy: 3.4)
            let eye: CGFloat = phase > 3.2 ? max(0.12, abs(cos((phase - 3.2) / 0.2 * .pi / 2))) : 1
            let bob = CGFloat(sin(t * 1.6)) * size * 0.012
            canvas(eye: eye).offset(y: bob)
        }
        .frame(width: size, height: size)
    }

    private func canvas(eye: CGFloat) -> some View {
        let s = size
        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.25, style: .continuous).fill(Brand.lavender)
                .overlay(RoundedRectangle(cornerRadius: s * 0.25, style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: max(1, s * 0.03)))
            ZStack {
                Circle().fill(Brand.yellow).frame(width: s * 0.36, height: s * 0.36).offset(x: s * 0.28, y: s * 0.02)
                Circle().fill(Brand.orange).frame(width: s * 0.82, height: s * 0.82).offset(x: -s * 0.16, y: s * 0.26)
                Circle().fill(Brand.green).frame(width: s * 0.6, height: s * 0.6).offset(x: s * 0.26, y: s * 0.34)
            }
            .clipShape(RoundedRectangle(cornerRadius: s * 0.25, style: .continuous))
            VStack(spacing: 0) {
                ZStack {
                    UnevenRoundedRectangle(bottomLeadingRadius: s * 0.1, bottomTrailingRadius: s * 0.1, style: .continuous)
                        .fill(Brand.ink)
                    HStack(spacing: s * 0.12) {
                        Capsule().fill(.white).frame(width: s * 0.045, height: s * 0.085 * eye)
                        Capsule().fill(.white).frame(width: s * 0.045, height: s * 0.085 * eye)
                    }
                    .offset(y: -s * 0.01)
                }
                .frame(width: s * 0.4, height: s * 0.2)
                Spacer(minLength: 0)
            }
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Tampilan

struct UpdateView: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: model.phase)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        // Jendela memakai fullSizeContentView: header menempati area judul (tombol jendela di atasnya).
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 16) {
            NotchMascot(size: 68)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cognify Notch").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(headline).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            // Dekorasi di latar saja, supaya tidak mengubah ukuran susunan.
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Brand.lavender, Brand.lavenderDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Brand.orange.opacity(0.9)).frame(width: 170, height: 170).offset(x: -70, y: 70)
                Circle().fill(Brand.yellow.opacity(0.95)).frame(width: 58, height: 58).offset(x: 388, y: 52)
                Circle().fill(Brand.green.opacity(0.95)).frame(width: 104, height: 104).offset(x: 344, y: 88)
            }
        }
        .frame(height: 124)
        .clipped()
    }

    private var headline: String {
        switch model.phase {
        case .checking: return L("Memeriksa pembaruan…", "Checking for updates…")
        case .found: return model.alreadyDownloaded ? L("Pembaruan siap dipasang", "Update ready to install") : L("Ada versi baru!", "A new version is available!")
        case .downloading: return L("Mengunduh pembaruan…", "Downloading update…")
        case .extracting: return L("Menyiapkan pembaruan…", "Preparing update…")
        case .installing: return L("Memasang…", "Installing…")
        case .upToDate: return L("Sudah yang terbaru", "You're up to date")
        case .installed: return L("Pembaruan terpasang", "Update installed")
        case .failed: return L("Pembaruan gagal", "Update failed")
        }
    }

    // MARK: isi per tahap

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking:
            ProgressTrack(value: nil)
            HStack { Spacer(); GhostButton(L("Batal", "Cancel")) { model.onCancel() } }
        case .found:
            versionRow
            notes
            automaticToggle
            HStack(spacing: 10) {
                LinkButton(L("Lewati versi ini", "Skip this version")) { model.onSkip() }
                Spacer()
                GhostButton(L("Nanti", "Later")) { model.onLater() }
                PrimaryButton(model.alreadyDownloaded ? L("Pasang & mulai ulang", "Install & relaunch") : L("Pasang pembaruan", "Install update")) { model.onInstall() }
            }
        case .downloading:
            versionRow
            ProgressTrack(value: model.progress)
            HStack {
                Text(progressLabel).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                GhostButton(L("Batal", "Cancel")) { model.onCancel() }
            }
        case .extracting:
            versionRow
            ProgressTrack(value: model.progress)
        case .installing:
            Text(L("Cognify Notch akan mulai ulang sebentar lagi.", "Cognify Notch will relaunch in a moment."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ProgressTrack(value: nil)
        case .upToDate:
            Text(L("Kamu memakai versi terbaru \(model.currentVersion).", "You're running the latest version \(model.currentVersion)."))
                .font(.system(size: 14))
            HStack { Spacer(); PrimaryButton(L("Oke", "OK")) { model.onClose() } }
        case .installed:
            Text(L("Cognify Notch sudah diperbarui ke versi \(model.currentVersion).", "Cognify Notch was updated to version \(model.currentVersion)."))
                .font(.system(size: 14))
            HStack { Spacer(); PrimaryButton(L("Oke", "OK")) { model.onClose() } }
        case .failed(let message):
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); PrimaryButton(L("Tutup", "Close")) { model.onClose() } }
        }
    }

    private var versionRow: some View {
        HStack(spacing: 8) {
            Pill(text: model.currentVersion.isEmpty ? "—" : model.currentVersion, tint: .secondary)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Pill(text: model.newVersion, tint: Brand.green, strong: true)
            if !model.sizeText.isEmpty {
                Text(model.sizeText).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        if !section.version.isEmpty {
                            Text(L("Versi", "Version") + " " + section.version)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.lavenderDeep)
                        }
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if model.sections.isEmpty {
                    Text(L("Perbaikan dan peningkatan.", "Fixes and improvements.")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(maxHeight: 180)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
    }

    private var automaticToggle: some View {
        Toggle(isOn: Binding(get: { model.automatic }, set: { model.automatic = $0; model.onToggleAutomatic($0) })) {
            Text(L("Pasang pembaruan berikutnya secara otomatis", "Install future updates automatically")).font(.system(size: 12.5))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var progressLabel: String {
        guard let p = model.progress else { return "" }
        return "\(Int((p * 100).rounded()))%" + (model.sizeText.isEmpty ? "" : " · \(model.sizeText)")
    }
}

// MARK: - Komponen

private struct Pill: View {
    let text: String
    var tint: Color
    var strong = false
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(strong ? Color.white : tint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(strong ? tint : tint.opacity(0.14)))
    }
}

/// Bilah kemajuan: nilai nil = tak tentu (potongan berwarna bergeser terus).
private struct ProgressTrack: View {
    let value: Double?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                if let v = value {
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.orange, Brand.lavenderDeep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * min(1, max(0, v))))
                        .animation(.easeOut(duration: 0.25), value: v)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                        let w = geo.size.width * 0.32
                        Capsule()
                            .fill(LinearGradient(colors: [Brand.orange, Brand.lavenderDeep], startPoint: .leading, endPoint: .trailing))
                            .frame(width: w)
                            .offset(x: (geo.size.width + w) * t - w)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 8)
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).frame(height: 36)
                .background(Capsule().fill(LinearGradient(colors: [Brand.lavender, Brand.lavenderDeep], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Brand.lavenderDeep.opacity(hover ? 0.45 : 0.25), radius: hover ? 9 : 5, y: 3)
                .scaleEffect(hover ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
    }
}

private struct GhostButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.primary)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(Color.primary.opacity(hover ? 0.12 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

private struct LinkButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(hover ? Color.primary : Color.secondary).underline(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Jendela

@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let host: NSHostingView<UpdateView>
    private var closing = false
    var onUserClose: () -> Void = {}

    init(model: UpdateModel) {
        host = NSHostingView(rootView: UpdateView(model: model))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.contentView = host
        window.delegate = self
        refit(animated: false)
    }

    func show() {
        refit(animated: false)
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Sesuaikan tinggi jendela dengan isinya (tinggi berubah tiap tahap), tepi atas tetap.
    func refit(animated: Bool = true) {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.height > 0 else { return }
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: 460, height: size.height)))
        frame.origin = NSPoint(x: window.frame.minX, y: window.isVisible ? top - frame.height : window.frame.minY)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    func close() {
        closing = true
        window.orderOut(nil)
        closing = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !closing { onUserClose() }
        return true
    }
}

// MARK: - User driver Sparkle

/// Metode memakai selector persis seperti SPUUserDriver (Sparkle 2). Dipanggil Sparkle di thread utama.
final class UpdateDriver: NSObject {
    private let model: UpdateModel
    private let window: UpdateWindow
    private let automaticGet: () -> Bool
    private let automaticSet: (Bool) -> Void

    private var expected: UInt64 = 0
    private var received: UInt64 = 0
    private var pendingAck: (() -> Void)?
    private var pendingReply: ((Int) -> Void)?
    private var pendingCancel: (() -> Void)?

    init(automaticGet: @escaping () -> Bool, automaticSet: @escaping (Bool) -> Void) {
        let model = MainActor.assumeIsolated { UpdateModel() }
        self.model = model
        window = MainActor.assumeIsolated { UpdateWindow(model: model) }
        self.automaticGet = automaticGet
        self.automaticSet = automaticSet
        super.init()
        MainActor.assumeIsolated { wire() }
    }

    @MainActor private func wire() {
        model.currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        model.onToggleAutomatic = { [weak self] on in self?.automaticSet(on) }
        model.onInstall = { [weak self] in self?.answer(1) }
        model.onLater = { [weak self] in self?.answer(2) }
        model.onSkip = { [weak self] in self?.answer(0) }
        model.onCancel = { [weak self] in
            self?.pendingCancel?()
            self?.pendingCancel = nil
            self?.window.close()
        }
        model.onClose = { [weak self] in self?.finish() }
        window.onUserClose = { [weak self] in
            // Menutup jendela = "nanti" / batal, sesuai tahap yang sedang tampil.
            guard let self else { return }
            if self.pendingReply != nil { self.answer(2) } else { self.pendingCancel?(); self.pendingCancel = nil; self.finish() }
        }
    }

    @MainActor private func answer(_ choice: Int) {
        let reply = pendingReply
        pendingReply = nil
        if choice != 1 { window.close() }
        reply?(choice)
    }

    @MainActor private func finish() {
        let ack = pendingAck
        pendingAck = nil
        window.close()
        ack?()
    }

    @MainActor private func present(_ phase: UpdateModel.Phase) {
        model.phase = phase
        model.automatic = automaticGet()
        window.show()
        DispatchQueue.main.async { [weak self] in self?.window.refit() }
    }

    // MARK: SPUUserDriver

    @objc(showUpdatePermissionRequest:reply:)
    func showUpdatePermissionRequest(_ request: NSObject, reply: @escaping (NSObject) -> Void) {
        // Pemeriksaan otomatis menyala; profil sistem tidak pernah dikirim (SUEnableSystemProfiling = NO).
        guard let type = NSClassFromString("SUUpdatePermissionResponse") as? NSObject.Type else { return }
        let sel = NSSelectorFromString("initWithAutomaticUpdateChecks:sendSystemProfile:")
        guard let alloc = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let imp = class_getMethodImplementation(type, sel) as IMP? else { return }
        typealias Init = @convention(c) (AnyObject, Selector, Bool, Bool) -> AnyObject
        let response = unsafeBitCast(imp, to: Init.self)(alloc, sel, true, false)
        if let object = response as? NSObject { reply(object) }
    }

    @objc(showUserInitiatedUpdateCheckWithCancellation:)
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated {
            pendingCancel = cancellation
            present(.checking)
        }
    }

    @objc(showUpdateFoundWithAppcastItem:state:reply:)
    func showUpdateFound(item: NSObject, state: NSObject, reply: @escaping (Int) -> Void) {
        MainActor.assumeIsolated {
            pendingCancel = nil
            pendingReply = reply
            model.newVersion = (item.value(forKey: "displayVersionString") as? String) ?? ""
            let length = (item.value(forKey: "contentLength") as? NSNumber)?.uint64Value ?? 0
            model.sizeText = length > 0 ? ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .file) : ""
            model.alreadyDownloaded = ((state.value(forKey: "stage") as? NSNumber)?.intValue ?? 0) != 0
            if let html = item.value(forKey: "itemDescription") as? String { model.sections = ReleaseNotes.parse(html: html, english: Lang.english) } else { model.sections = [] }
            present(.found)
        }
    }

    @objc(showUpdateReleaseNotesWithDownloadData:)
    func showUpdateReleaseNotes(data: NSObject) {
        MainActor.assumeIsolated {
            // Catatan yang diunduh dari releaseNotesURL (bila appcast tidak memuatnya langsung).
            guard model.sections.isEmpty, let bytes = data.value(forKey: "data") as? Data, let html = String(data: bytes, encoding: .utf8) else { return }
            model.sections = ReleaseNotes.parse(html: html, english: Lang.english)
            window.refit()
        }
    }

    @objc(showUpdateReleaseNotesFailedToDownloadWithError:)
    func showUpdateReleaseNotesFailed(error: NSError) {}

    @objc(showUpdateNotFoundWithError:acknowledgement:)
    func showUpdateNotFound(error: NSError, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            pendingCancel = nil
            pendingAck = acknowledgement
            present(.upToDate)
        }
    }

    @objc(showUpdaterError:acknowledgement:)
    func showUpdaterError(error: NSError, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            pendingCancel = nil
            pendingAck = acknowledgement
            present(.failed(error.localizedDescription))
        }
    }

    @objc(showDownloadInitiatedWithCancellation:)
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated {
            pendingCancel = cancellation
            expected = 0
            received = 0
            model.progress = 0
            present(.downloading)
        }
    }

    @objc(showDownloadDidReceiveExpectedContentLength:)
    func showDownloadExpected(length: UInt64) {
        MainActor.assumeIsolated {
            expected = length
            if length > 0 { model.sizeText = ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .file) }
        }
    }

    @objc(showDownloadDidReceiveDataOfLength:)
    func showDownloadReceived(length: UInt64) {
        MainActor.assumeIsolated {
            received += length
            model.progress = expected > 0 ? min(1, Double(received) / Double(expected)) : nil
        }
    }

    @objc(showDownloadDidStartExtractingUpdate)
    func showDownloadStartExtracting() {
        MainActor.assumeIsolated {
            pendingCancel = nil
            model.progress = 0
            present(.extracting)
        }
    }

    @objc(showExtractionReceivedProgress:)
    func showExtractionProgress(_ progress: Double) {
        MainActor.assumeIsolated { model.progress = progress }
    }

    @objc(showReadyToInstallAndRelaunch:)
    func showReadyToInstall(reply: @escaping (Int) -> Void) {
        // Pengguna sudah memilih memasang: langsung lanjut, tanpa tombol kedua.
        MainActor.assumeIsolated { present(.installing) }
        reply(1)
    }

    @objc(showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:)
    func showInstalling(terminated: Bool, retry: @escaping () -> Void) {
        MainActor.assumeIsolated { present(.installing) }
    }

    @objc(showUpdateInstalledAndRelaunched:acknowledgement:)
    func showUpdateInstalled(relaunched: Bool, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            pendingAck = acknowledgement
            present(.installed)
        }
    }

    @objc(showUpdateInFocus)
    func showUpdateInFocus() {
        MainActor.assumeIsolated { window.show() }
    }

    @objc(dismissUpdateInstallation)
    func dismissUpdateInstallation() {
        MainActor.assumeIsolated {
            pendingReply = nil
            pendingCancel = nil
            window.close()
        }
    }
}
