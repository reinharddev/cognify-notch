import SwiftUI

// Susunan jendela Pengaturan: kartu berisi baris, tanpa garis pemisah. Acuan: docs/desain/mockup-penyegaran-pengaturan-notch.html.

/// Judul kelompok di atas kartu; tiap anak langsungnya menjadi satu baris.
struct SettingsCard<Content: View>: View {
    var title: String?
    var note: String?
    let content: Content

    init(_ title: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.s)
            }
            // Satu-satunya cara membungkus tiap anak di macOS 13 (`Group(subviews:)` baru ada di macOS 15).
            _VariadicView.Tree(SettingsRows()) { content }
                .padding(6)
                .notchCard(padding: 0)
            if let note { SettingsNote(note).padding(.horizontal, Theme.Space.s) }
        }
    }
}

private struct SettingsRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 2) {
            ForEach(children) { SettingsRow(content: $0) }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let content: Content
    @State private var hover = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hover ? 0.05 : 0)))
            .onHover { hover = $0 }
    }
}

struct SettingsNote: View {
    let text: String
    var warning = false
    init(_ text: String, warning: Bool = false) { self.text = text; self.warning = warning }

    var body: some View {
        Text(text).font(.system(size: 11))
            .foregroundStyle(warning ? Color.orange : Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Label di kiri, kontrol di ujung kanan.
struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.s) {
            configuration.label
            Spacer(minLength: Theme.Space.s)
            configuration.content
        }
    }
}

/// Label dua baris: nama, lalu keterangan kecil.
struct SettingsLabel: View {
    let title: String
    let hint: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(hint).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Baris slider: nama, slider, nilai, dan tombol atur ulang.
struct SliderRow: View {
    let title: String
    var hint: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let text: (Double) -> String
    var standard: Double?

    var body: some View {
        LabeledContent {
            NotchSlider(value: $value, range: range, nudge: step > 0 ? step : (range.upperBound - range.lowerBound) / 40, step: step)
                .frame(width: 130)
                .accessibilityLabel(title)
            Text(text(value)).monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 52, alignment: .trailing)
            if let standard {
                Button { value = standard } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain)
                    .background(Circle().fill(Theme.track))
                    .disabled(abs(value - standard) < 0.001)
                    .accessibilityLabel("Reset " + title)
            }
        } label: {
            if let hint { SettingsLabel(title: title, hint: hint) } else { Text(title) }
        }
    }
}
