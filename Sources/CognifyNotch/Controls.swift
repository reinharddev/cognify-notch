import SwiftUI

// Kontrol bersama (dropdown, kolom isian, kartu, saklar, segmen, slider) dengan gaya yang sama di Pengaturan dan di notch.
// Pasangannya di Windows: notch-windows/src/lib/ui (Select.svelte, Input.svelte).

struct DropdownOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
    init(_ value: Value, _ label: String) { self.value = value; self.label = label }
}

/// Pengganti `Picker` gaya menu: judul di kiri, tombol kapsul di kanan, daftarnya di popover.
/// Panah atas dan bawah memindahkan sorotan, Enter memilih, Esc menutup.
struct NotchDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DropdownOption<Value>]
    var listWidth: CGFloat = 240

    @State private var open = false
    @State private var active = 0
    @State private var hovering = false

    init(_ title: String, selection: Binding<Value>, options: [DropdownOption<Value>], listWidth: CGFloat = 240) {
        self.listWidth = listWidth
        self.title = title
        self._selection = selection
        self.options = options
    }

    private var current: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        LabeledContent(title) {
            Button {
                active = options.firstIndex { $0.value == selection } ?? 0
                open.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(current).lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.leading, 12).padding(.trailing, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.15 : 0.09)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
            .accessibilityValue(current)
            .popover(isPresented: $open, arrowEdge: .bottom) { list }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        row(index, option).id(index)
                    }
                }
                .padding(5)
            }
            .frame(width: listWidth, height: min(CGFloat(options.count) * 27 + 10, 280))
            .onAppear { proxy.scrollTo(active, anchor: .center) }
            .onChange(of: active) { proxy.scrollTo($0) }
        }
        .background(keys)
    }

    private func row(_ index: Int, _ option: DropdownOption<Value>) -> some View {
        Button { pick(index) } label: {
            HStack(spacing: 8) {
                Text(option.label).lineLimit(1)
                Spacer(minLength: 0)
                if option.value == selection {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(index == active ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { active = index } }
    }

    private var keys: some View {
        Group {
            Button("") { active = max(0, active - 1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { active = min(options.count - 1, active + 1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { pick(active) }.keyboardShortcut(.return, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func pick(_ index: Int) {
        open = false
        guard options.indices.contains(index), options[index].value != selection else { return }
        selection = options[index].value
    }
}

/// Kotak kolom isian. Dipakai sendiri untuk kolom yang punya ikon atau tombol di dalamnya.
private struct NotchFieldBox: ViewModifier {
    let height: CGFloat?
    let radius: CGFloat
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(focused ? 0.11 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(focused ? Color.accent.opacity(0.7) : Color.white.opacity(0.08)))
    }
}

extension View {
    /// `height: nil` mengikuti isi (kolom yang bisa lebih dari satu baris).
    func notchFieldBox(height: CGFloat? = 28, radius: CGFloat = 9, focused: Bool = false) -> some View {
        modifier(NotchFieldBox(height: height, radius: radius, focused: focused))
    }
}

/// Kolom teks satu baris dengan teks petunjuk di dalam kotak.
struct NotchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.plain)
            .accessibilityLabel(placeholder)
            .focused($focused)
            .notchFieldBox(focused: focused)
    }
}

/// Kartu setinggi ruang yang ada; isinya digulir bila kepanjangan, jadi tidak pernah mendorong header panel.
private struct NotchScrollCard: ViewModifier {
    let padding: CGFloat
    @Environment(\.snapshot) private var snapshot

    func body(content: Content) -> some View {
        let filled = content.frame(maxWidth: .infinity, alignment: .topLeading)
        Group {
            // ScrollView tidak ikut terender di snapshot.
            if snapshot {
                filled.frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView(.vertical, showsIndicators: false) { filled }
            }
        }
        .notchCard(padding: padding)
    }
}

extension View {
    func notchScrollCard(padding: CGFloat = Theme.Space.s) -> some View { modifier(NotchScrollCard(padding: padding)) }

    /// Kelompok isi di panel: isian tembus pandang dengan garis cahaya tipis di tepi.
    func notchCard(padding: CGFloat = Theme.Space.m) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return self.padding(padding)
            .background(shape.fill(Theme.card))
            .overlay(shape.strokeBorder(Theme.edge))
    }
}

/// Saklar kecil bergaya notch (Toggle bawaan tidak ikut terender di snapshot).
struct MiniSwitch: ToggleStyle {
    /// Di Pengaturan: label di kiri, saklar di ujung kanan.
    var trailing = false

    private func knob(_ on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Color.accent : Color.white.opacity(0.18)).frame(width: trailing ? 32 : 26, height: trailing ? 19 : 15)
            Circle().fill(.white).frame(width: trailing ? 15 : 11, height: trailing ? 15 : 11).padding(.horizontal, 2)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.notch) { configuration.isOn.toggle() } } label: {
            HStack(spacing: 7) {
                if trailing {
                    configuration.label
                    Spacer(minLength: Theme.Space.s)
                    knob(configuration.isOn)
                } else {
                    knob(configuration.isOn)
                    configuration.label
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// Label kecil berwarna (waktu, status). Tulisannya putih supaya terbaca di warna apa pun.
struct NotchChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.32)))
    }
}

/// Pengganti `Picker` bergaya segmen: pilihan dalam satu kapsul, yang aktif berwarna aksen.
struct NotchSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DropdownOption<Value>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button { withAnimation(.tabSwitch) { selection = option.value } } label: {
                    Text(option.label).lineLimit(1)
                        .fontWeight(selected ? .semibold : .regular)
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
                        .background(Capsule().fill(selected ? Color.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.track))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Pengganti `Slider`: seret atau klik; panah kiri dan kanan saat terfokus; VoiceOver memakai slider bawaan.
/// Warnanya `.primary` supaya tetap terlihat di Dock berlatar terang.
struct NotchSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// Panah keyboard menggeser sejauh ini.
    var nudge: Double = 0.05
    /// Nilai dibulatkan ke kelipatan ini; 0 = bebas.
    var step: Double = 0
    var onEditing: (Bool) -> Void = { _ in }

    @State private var dragging = false
    private static let knob: CGFloat = 12

    private var span: Double { range.upperBound - range.lowerBound }
    private func set(_ next: Double) {
        let snapped = step > 0 ? range.lowerBound + ((next - range.lowerBound) / step).rounded() * step : next
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - Self.knob)
            let x = travel * min(1, max(0, (value - range.lowerBound) / span))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18)).frame(height: 4)
                Capsule().fill(Color.accent).frame(width: x + Self.knob / 2, height: 4)
                Circle().fill(Color.primary).frame(width: Self.knob, height: Self.knob).offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging { dragging = true; onEditing(true) }
                    set(range.lowerBound + span * (drag.location.x - Self.knob / 2) / travel)
                }
                .onEnded { _ in dragging = false; onEditing(false) })
        }
        .frame(height: 16)
        .focusable()
        .onMoveCommand { direction in
            if direction == .left { set(value - max(nudge, step)) }
            if direction == .right { set(value + max(nudge, step)) }
        }
        .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

/// Pengganti `ColorPicker`: warna cepat, rona, pekat, terang, dan kode hex dalam satu popover.
struct NotchColorPicker: View {
    @Binding var selection: Color
    var title = L("Pilih warna", "Pick a color")

    @State private var open = false
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 1.0
    @State private var hex = ""

    private static let swatches = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#64d2ff", "#0a84ff",
                                   "#5e5ce6", "#bf5af2", "#ff375f", "#ac8e68", "#8e8e93", "#ffffff"]

    var body: some View {
        Button { load(selection); open.toggle() } label: {
            Capsule().fill(selection).frame(width: 36, height: 22)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selection.hex)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: Theme.Space.s), count: 6), spacing: Theme.Space.s) {
                ForEach(Self.swatches, id: \.self) { code in
                    Button { pick(Color(hex: code) ?? .white) } label: { Circle().fill(Color(hex: code) ?? .white).frame(width: 22, height: 22) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(code)
                }
            }
            slider(L("Rona", "Hue"), $hue)
            slider(L("Pekat", "Saturation"), $saturation)
            slider(L("Terang", "Brightness"), $brightness)
            NotchField("#rrggbb", text: Binding(get: { hex }, set: { text in
                hex = text
                if text.count == 7, let color = Color(hex: text) { load(color); selection = color }
            }))
        }
        .padding(Theme.Space.m)
        .frame(width: 200)
    }

    private func slider(_ name: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            NotchSlider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; apply() }))
                .accessibilityLabel(name)
        }
    }

    private func load(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        hue = rgb.hueComponent; saturation = rgb.saturationComponent; brightness = rgb.brightnessComponent
        hex = color.hex
    }

    private func pick(_ color: Color) { load(color); selection = color }

    private func apply() {
        selection = Color(hue: hue, saturation: saturation, brightness: brightness)
        hex = selection.hex
    }
}
