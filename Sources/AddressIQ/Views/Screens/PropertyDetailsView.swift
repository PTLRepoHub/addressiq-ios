import SwiftUI

private struct ColorOption: Identifiable {
    let label: String
    let color: Color
    var needsBorder: Bool = false
    var id: String { label }
}

private let COLOR_OPTIONS: [ColorOption] = [
    ColorOption(label: "White", color: Color(red: 0.96, green: 0.96, blue: 0.96), needsBorder: true),
    ColorOption(label: "Brown", color: Color(red: 0.55, green: 0.27, blue: 0.07)),
    ColorOption(label: "Blue", color: Color(red: 0.15, green: 0.39, blue: 0.92)),
    ColorOption(label: "Red", color: Color(red: 0.86, green: 0.15, blue: 0.15)),
    ColorOption(label: "Grey", color: Color(red: 0.42, green: 0.45, blue: 0.50)),
    ColorOption(label: "Yellow", color: Color(red: 0.92, green: 0.69, blue: 0.03), needsBorder: true),
    ColorOption(label: "Green", color: Color(red: 0.09, green: 0.64, blue: 0.29)),
    ColorOption(label: "Cream", color: Color(red: 1.0, green: 0.99, blue: 0.82), needsBorder: true),
]

@available(iOS 15.0, *)
struct PropertyDetailsView: View {
    let initial: AddressDraft
    let onNext: (AddressDraft) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var propertyNumber: String
    @State private var streetName: String
    @State private var buildingColor: String
    @State private var directions: String

    init(initial: AddressDraft, onNext: @escaping (AddressDraft) -> Void, onBack: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onNext = onNext
        self.onBack = onBack
        self.onCancel = onCancel
        _propertyNumber = State(initialValue: initial.propertyNumber ?? "")
        _streetName = State(initialValue: initial.streetName ?? "")
        _buildingColor = State(initialValue: initial.buildingColor ?? "")
        _directions = State(initialValue: initial.directions ?? "")
    }

    var canContinue: Bool {
        !propertyNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
        !streetName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !buildingColor.isEmpty
    }

    var body: some View {
        ScreenScaffold(
            title: "Property Details",
            subtitle: "Help us identify your building",
            onBack: onBack,
            onClose: onCancel,
            content: {
                VStack(alignment: .leading, spacing: 16) {
                    labeledField("Property / House Number", $propertyNumber, placeholder: "e.g. 12, Block A")
                    labeledField("Street Name", $streetName, placeholder: "e.g. Broad Street")

                    Text("Building Color")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.text)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(COLOR_OPTIONS) { option in
                            colorChip(option)
                        }
                    }

                    labeledField(
                        "Landmark / Directions (optional)",
                        $directions,
                        placeholder: "e.g. Opposite yellow church",
                        multiline: true
                    )
                }
            },
            footer: {
                AddressIQButton(
                    title: "Continue",
                    action: {
                        var draft = initial
                        draft.propertyNumber = propertyNumber.trimmingCharacters(in: .whitespaces)
                        draft.streetName = streetName.trimmingCharacters(in: .whitespaces)
                        draft.buildingColor = buildingColor
                        let dir = directions.trimmingCharacters(in: .whitespaces)
                        draft.directions = dir.isEmpty ? nil : dir
                        onNext(draft)
                    },
                    enabled: canContinue
                )
            }
        )
    }

    @ViewBuilder
    private func labeledField(_ label: String, _ value: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(theme.text)
            if multiline {
                TextEditor(text: value)
                    .font(.system(size: 15))
                    .foregroundColor(theme.inputText)
                    .hiddenScrollBackground()
                    .background(theme.inputBg)
                    .frame(minHeight: 70)
                    .padding(.horizontal, 8)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inputBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                TextField(placeholder, text: value)
                    .font(.system(size: 15))
                    .foregroundColor(theme.inputText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(theme.inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inputBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func colorChip(_ option: ColorOption) -> some View {
        let selected = buildingColor == option.label
        return Button(action: { buildingColor = option.label }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(option.color).frame(width: 28, height: 28)
                    if option.needsBorder {
                        Circle().stroke(theme.inputBorder, lineWidth: 1).frame(width: 28, height: 28)
                    }
                }
                Text(option.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selected ? theme.primary : theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? theme.primary : theme.border, lineWidth: selected ? 2 : 1)
            )
        }
    }
}
