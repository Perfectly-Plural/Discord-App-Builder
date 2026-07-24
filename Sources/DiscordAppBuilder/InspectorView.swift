import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let block = state.selectedBlock {
                Text(block.definition.name)
                    .font(.title3.weight(.semibold))
                Text(block.definition.description.isEmpty ? "No description supplied." : block.definition.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                if block.definition.options.isEmpty {
                    Label("No options", systemImage: "slider.horizontal.2.square")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Options")
                        .font(.headline)
                    ForEach(block.definition.options) { option in
                        OptionEditor(
                            blockID: block.id,
                            option: option,
                            value: block.optionValues[option.id]?.displayString ?? ""
                        )
                    }
                }

                Divider()
                PortSummary(title: "Inputs", ports: block.definition.inputs)
                PortSummary(title: "Outputs", ports: block.definition.outputs)

                Spacer()
                Button(role: .destructive) {
                    state.deleteSelectedBlock()
                } label: {
                    Label("Delete Block", systemImage: "trash")
                }
            } else {
                ContentUnavailableView(
                    "No block selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a block on the canvas to edit its options.")
                )
            }
            if state.selectedBlock == nil {
                Spacer()
            }
        }
        .padding()
    }
}

private struct OptionEditor: View {
    @EnvironmentObject private var state: AppState
    let blockID: WorkflowBlock.ID
    let option: BlockOption
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(option.name)
                .font(.subheadline.weight(.medium))

            switch option.type {
            case .select:
                Picker(option.name, selection: binding) {
                    ForEach(choiceKeys, id: \.self) { key in
                        Text(option.choices[key] ?? key).tag(key)
                    }
                }
                .labelsHidden()
            case .number:
                TextField("0", text: binding)
                    .textFieldStyle(.roundedBorder)
            case .color:
                TextField("#5865F2", text: binding)
                    .textFieldStyle(.roundedBorder)
            case .checkbox:
                Toggle("", isOn: booleanBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            case .multiselect:
                Menu {
                    ForEach(choiceKeys, id: \.self) { key in
                        Toggle(
                            option.choices[key] ?? key,
                            isOn: multiSelectBinding(for: key)
                        )
                    }
                } label: {
                    Text(multiSelectSummary)
                }
            case .text, .unknown:
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .help(option.description)
    }

    private var binding: Binding<String> {
        Binding(
            get: { value },
            set: { state.setOption(blockID: blockID, optionID: option.id, value: $0) }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: {
                guard let value = state.document.blocks
                    .first(where: { $0.id == blockID })?
                    .optionValues[option.id]
                else { return false }
                if case .boolean(let enabled) = value {
                    return enabled
                }
                return value.displayString == "true"
            },
            set: {
                state.setBooleanOption(
                    blockID: blockID,
                    optionID: option.id,
                    value: $0
                )
            }
        )
    }

    private var choiceKeys: [String] {
        option.choiceOrder ?? option.choices.keys.sorted()
    }

    private func multiSelectBinding(for choice: String) -> Binding<Bool> {
        Binding(
            get: {
                state.document.blocks
                    .first(where: { $0.id == blockID })?
                    .optionValues[option.id]?
                    .wireIDs
                    .contains(choice) ?? false
            },
            set: {
                state.setMultiSelectOption(
                    blockID: blockID,
                    optionID: option.id,
                    choice: choice,
                    selected: $0
                )
            }
        )
    }

    private var multiSelectSummary: String {
        let selected = state.document.blocks
            .first(where: { $0.id == blockID })?
            .optionValues[option.id]?
            .wireIDs ?? []
        if selected.isEmpty {
            return "None"
        }
        return selected.compactMap { option.choices[$0] }.joined(separator: ", ")
    }
}

private struct PortSummary: View {
    let title: String
    let ports: [BlockPort]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(ports) { port in
                HStack {
                    Circle()
                        .fill(port.color)
                        .frame(width: 8, height: 8)
                    Text(port.name)
                    Spacer()
                    Text(port.types.map(\.rawValue).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
    }
}
