import AppKit
import SwiftUI

struct WorkflowPortKey: Hashable {
    let blockID: UUID
    let portID: String
    let direction: BlockPort.Direction
    let occurrence: Int

    init(
        blockID: UUID,
        portID: String,
        direction: BlockPort.Direction,
        occurrence: Int = 0
    ) {
        self.blockID = blockID
        self.portID = portID
        self.direction = direction
        self.occurrence = occurrence
    }
}

struct WorkflowPortPositionPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkflowPortKey: CGPoint] = [:]

    static func reduce(
        value: inout [WorkflowPortKey: CGPoint],
        nextValue: () -> [WorkflowPortKey: CGPoint]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct WorkflowBlockView: View {
    @EnvironmentObject private var state: AppState
    let block: WorkflowBlock
    let canvasScale: CGFloat
    let graphIndex: WorkflowGraphIndex
    let onConnectionDragChanged: (WorkflowPortKey, CGPoint) -> Void
    let onConnectionDragEnded: (WorkflowPortKey, CGPoint) -> Void
    @State private var dragOrigin: CGPoint?
    @State private var dragOffset = CGSize.zero

    private var isSelected: Bool {
        state.selectedBlockIDs.contains(block.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 12) {
                PortColumn(
                    blockID: block.id,
                    ports: block.definition.inputs,
                    graphIndex: graphIndex,
                    onConnectionDragChanged: onConnectionDragChanged,
                    onConnectionDragEnded: onConnectionDragEnded
                )
                Spacer(minLength: 8)
                PortColumn(
                    blockID: block.id,
                    ports: block.definition.outputs,
                    graphIndex: graphIndex,
                    onConnectionDragChanged: onConnectionDragChanged,
                    onConnectionDragEnded: onConnectionDragEnded
                )
            }
            .padding(10)

            if !block.definition.options.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(block.definition.options) { option in
                        InlineOptionEditor(blockID: block.id, option: option)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        )
        .overlay {
            MiddleClickCaptureView {
                state.deleteBlock(block.id)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 7 : 3, y: 2)
        .offset(dragOffset)
        .onTapGesture {
            state.selectBlock(
                block.id,
                extendingSelection: NSApp.currentEvent?.modifierFlags.contains(.command) == true
            )
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: block.definition.autoExecute ? "bolt.fill" : "cube")
                .foregroundStyle(block.definition.autoExecute ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.definition.name)
                    .font(.headline)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        state.renameBlockFile(for: block.id)
                    }
                    .help("Double-click to rename the block's .js file")
                Text("\(block.blockFileName).js - \(block.definition.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let displayedBlockID = block.displayedBlockID(
                workspaceID: state.currentWorkspaceID
            ) {
                Text(displayedBlockID)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Block ID")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .gesture(blockDragGesture)
    }

    private var blockDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("workflowCanvas"))
            .onChanged { value in
                guard !block.isLocked else { return }
                if dragOrigin == nil {
                    dragOrigin = block.position
                    if !state.selectedBlockIDs.contains(block.id) {
                        state.selectBlock(block.id)
                    }
                }
                dragOffset = CGSize(
                    width: value.translation.width / canvasScale,
                    height: value.translation.height / canvasScale
                )
            }
            .onEnded { value in
                guard let origin = dragOrigin, !block.isLocked else {
                    dragOrigin = nil
                    dragOffset = .zero
                    return
                }
                let finalPosition = CGPoint(
                    x: origin.x + value.translation.width / canvasScale,
                    y: origin.y + value.translation.height / canvasScale
                )
                dragOrigin = nil
                dragOffset = .zero
                state.setBlockPosition(block.id, to: finalPosition)
            }
    }
}

private struct MiddleClickCaptureView: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: MiddleClickView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }

    final class MiddleClickView: NSView {
        var onMiddleClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .otherMouseDown,
                  NSApp.currentEvent?.buttonNumber == 2
            else { return nil }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) {
            guard event.buttonNumber == 2 else {
                super.otherMouseDown(with: event)
                return
            }
            onMiddleClick?()
        }
    }
}

private struct InlineOptionEditor: View {
    @EnvironmentObject private var state: AppState
    let blockID: WorkflowBlock.ID
    let option: BlockOption

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            switch option.type {
            case .select:
                Picker(option.name, selection: value) {
                    ForEach(choiceKeys, id: \.self) { key in
                        Text(option.choices[key] ?? key)
                            .tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .color:
                HStack(spacing: 7) {
                    Circle()
                        .fill(parsedColor)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.45)))
                    TextField("#5865F2", text: value)
                        .textFieldStyle(.roundedBorder)
                }
            case .number:
                TextField("0", text: value)
                    .textFieldStyle(.roundedBorder)
            case .checkbox:
                Toggle("", isOn: booleanValue)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .text, .unknown:
                TextField("", text: value)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .help(option.description)
    }

    private var value: Binding<String> {
        Binding(
            get: {
                state.document.blocks
                    .first(where: { $0.id == blockID })?
                    .optionValues[option.id]?
                    .displayString ?? ""
            },
            set: {
                state.setOption(blockID: blockID, optionID: option.id, value: $0)
            }
        )
    }

    private var booleanValue: Binding<Bool> {
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

    private var parsedColor: Color {
        let hex = value.wrappedValue.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = Int(hex, radix: 16) else {
            return .clear
        }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

private struct PortColumn: View {
    let blockID: WorkflowBlock.ID
    let ports: [BlockPort]
    let graphIndex: WorkflowGraphIndex
    let onConnectionDragChanged: (WorkflowPortKey, CGPoint) -> Void
    let onConnectionDragEnded: (WorkflowPortKey, CGPoint) -> Void

    var body: some View {
        VStack(alignment: ports.first?.direction == .input ? .leading : .trailing, spacing: 8) {
            ForEach(ports) { port in
                let count = instanceCount(for: port)
                ForEach(0..<count, id: \.self) { occurrence in
                    PortButton(
                        blockID: blockID,
                        port: port,
                        occurrence: occurrence,
                        showsOccurrence: count > 1,
                        resolvedValueType: graphIndex.resolvedValueType(
                            for: endpoint(for: port),
                            occurrence: occurrence
                        ),
                        onConnectionDragChanged: onConnectionDragChanged,
                        onConnectionDragEnded: onConnectionDragEnded
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: ports.first?.direction == .input ? .leading : .trailing)
    }

    private func instanceCount(for port: BlockPort) -> Int {
        guard port.allowsMultipleConnections else { return 1 }
        let endpoint = endpoint(for: port)
        let connectionCount = graphIndex.connectionCount(for: endpoint)
        let storedCount = port.direction == .input
            ? graphIndex.storedInputCount(for: endpoint)
            : 0
        return max(connectionCount, storedCount) + 1
    }

    private func endpoint(for port: BlockPort) -> WorkflowPortEndpoint {
        WorkflowPortEndpoint(
            blockID: blockID,
            portID: port.id,
            direction: port.direction
        )
    }
}

private struct PortButton: View {
    @EnvironmentObject private var state: AppState
    let blockID: WorkflowBlock.ID
    let port: BlockPort
    let occurrence: Int
    let showsOccurrence: Bool
    let resolvedValueType: BlockValueType
    let onConnectionDragChanged: (WorkflowPortKey, CGPoint) -> Void
    let onConnectionDragEnded: (WorkflowPortKey, CGPoint) -> Void

    var body: some View {
        HStack(spacing: 5) {
            if port.direction == .input { dot }
            Text(port.name)
                .font(.caption)
                .lineLimit(1)
            if showsOccurrence {
                Text("\(occurrence + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if port.required {
                Image(systemName: "asterisk")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.red)
            }
            if port.direction == .output { dot }
        }
        .contentShape(Rectangle())
        .gesture(connectionGesture)
        .help(port.description)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(port.name) \(port.direction.rawValue) connector")
    }

    private var key: WorkflowPortKey {
        WorkflowPortKey(
            blockID: blockID,
            portID: port.id,
            direction: port.direction,
            occurrence: occurrence
        )
    }

    private var connectionGesture: some Gesture {
        TapGesture()
            .onEnded {
                switch port.direction {
                case .output:
                    state.beginConnection(from: blockID, portID: port.id)
                case .input:
                    state.completeConnection(to: blockID, portID: port.id)
                }
            }
            .exclusively(
                before: DragGesture(
                    minimumDistance: 3,
                    coordinateSpace: .named("workflowCanvas")
                )
                .onChanged { value in
                    onConnectionDragChanged(key, value.location)
                }
                .onEnded { value in
                    onConnectionDragEnded(key, value.location)
                }
            )
    }

    private var dot: some View {
        Circle()
            .fill(resolvedValueType.color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("workflowCanvas"))
                    Color.clear.preference(
                        key: WorkflowPortPositionPreferenceKey.self,
                        value: [
                            WorkflowPortKey(
                                blockID: blockID,
                                portID: port.id,
                                direction: port.direction,
                                occurrence: occurrence
                            ): CGPoint(x: frame.midX, y: frame.midY)
                        ]
                    )
                }
            }
    }
}
