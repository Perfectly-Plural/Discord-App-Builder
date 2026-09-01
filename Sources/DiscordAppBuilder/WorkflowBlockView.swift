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

private enum BlockResizeCorner {
    case bottomLeading
    case bottomTrailing
}

struct WorkflowBlockView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    let block: WorkflowBlock
    let canvasScale: CGFloat
    let graphIndex: WorkflowGraphIndex
    let onConnectionDragChanged: (WorkflowPortKey, CGPoint) -> Void
    let onConnectionDragEnded: (WorkflowPortKey, CGPoint) -> Void
    @State private var dragOrigin: CGPoint?
    @State private var dragOffset = CGSize.zero
    @State private var resizeOriginSize: CGSize?
    @State private var resizeOriginPosition: CGPoint?
    @State private var resizeSize: CGSize?
    @State private var resizeCorner: BlockResizeCorner?

    private var isSelected: Bool {
        state.selectedBlockIDs.contains(block.id)
    }

    private var displayedWidth: CGFloat {
        resizeSize?.width
            ?? max(minimumContentWidth, block.width)
    }

    private var displayedHeight: CGFloat {
        resizeSize?.height
            ?? max(minimumContentHeight, block.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 12) {
                if !block.definition.inputs.isEmpty {
                    PortColumn(
                        blockID: block.id,
                        ports: block.definition.inputs,
                        graphIndex: graphIndex,
                        onConnectionDragChanged: onConnectionDragChanged,
                        onConnectionDragEnded: onConnectionDragEnded
                    )
                    .frame(width: portColumnWidth, alignment: .leading)
                }

                if !block.definition.options.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(block.definition.options) { option in
                            InlineOptionEditor(
                                blockID: block.id,
                                option: option,
                                textEditorHeight: textEditorHeight
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Spacer(minLength: 8)
                }

                if !block.definition.outputs.isEmpty {
                    PortColumn(
                        blockID: block.id,
                        ports: block.definition.outputs,
                        graphIndex: graphIndex,
                        onConnectionDragChanged: onConnectionDragChanged,
                        onConnectionDragEnded: onConnectionDragEnded
                    )
                    .frame(width: portColumnWidth, alignment: .trailing)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 28)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(
            width: displayedWidth,
            height: displayedHeight,
            alignment: .top
        )
        .background(blockBackgroundColor)
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
        .overlay(alignment: .bottomLeading) {
            if isSelected, !block.isLocked {
                resizeHandle(for: .bottomLeading)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected, !block.isLocked {
                resizeHandle(for: .bottomTrailing)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 7 : 3, y: 2)
        .offset(CGSize(
            width: dragOffset.width + resizeOffset.width,
            height: dragOffset.height + resizeOffset.height
        ))
        .onTapGesture {
            state.selectBlock(
                block.id,
                extendingSelection: NSApp.currentEvent?.modifierFlags.contains(.command) == true
            )
        }
    }

    private var minimumContentWidth: CGFloat {
        guard !block.definition.options.isEmpty else {
            return WorkflowBlock.minimumEditorWidth
        }
        let connectorColumnCount = [
            block.definition.inputs.isEmpty,
            block.definition.outputs.isEmpty
        ].filter { !$0 }.count
        return 300 + CGFloat(connectorColumnCount * 90)
    }

    private var blockBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 95 / 255, green: 95 / 255, blue: 95 / 255)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var headerBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 50 / 255, green: 50 / 255, blue: 50 / 255)
            : Color(nsColor: .underPageBackgroundColor)
    }

    private var portColumnWidth: CGFloat {
        min(130, max(90, displayedWidth * 0.22))
    }

    private var textEditorHeight: CGFloat {
        let textOptionCount = block.definition.options.filter {
            $0.type == .text || $0.type == .unknown
        }.count
        guard textOptionCount > 0 else { return 30 }

        let fixedEditorsHeight = block.definition.options.reduce(CGFloat.zero) {
            partial, option in
            guard option.type != .text, option.type != .unknown else {
                return partial
            }
            return partial + 26
        }
        let labelsHeight = CGFloat(block.definition.options.count * 20)
        let spacingHeight = CGFloat(max(0, block.definition.options.count - 1) * 9)
        let availableHeight = displayedHeight
            - 40
            - 38
            - fixedEditorsHeight
            - labelsHeight
            - spacingHeight
        return max(48, availableHeight / CGFloat(textOptionCount))
    }

    private var minimumContentHeight: CGFloat {
        let inputRows = block.definition.inputs.reduce(0) {
            $0 + renderedInstanceCount(for: $1)
        }
        let outputRows = block.definition.outputs.reduce(0) {
            $0 + renderedInstanceCount(for: $1)
        }
        let portHeight = CGFloat(max(inputRows, outputRows, 1) * 32)

        let optionHeight = block.definition.options.reduce(CGFloat.zero) {
            partial, option in
            partial + 20
                + (option.type == .text || option.type == .unknown ? 48 : 26)
        } + CGFloat(max(0, block.definition.options.count - 1) * 9)

        return max(
            WorkflowBlock.minimumEditorHeight,
            40 + 38 + max(portHeight, optionHeight)
        )
    }

    private func renderedInstanceCount(for port: BlockPort) -> Int {
        guard port.allowsMultipleConnections else { return 1 }
        let endpoint = WorkflowPortEndpoint(
            blockID: block.id,
            portID: port.id,
            direction: port.direction
        )
        let connectionCount = graphIndex.connectionCount(for: endpoint)
        let storedCount = port.direction == .input
            ? graphIndex.storedInputCount(for: endpoint)
            : 0
        return max(connectionCount, storedCount) + 1
    }

    private var resizeOffset: CGSize {
        guard let origin = resizeOriginSize,
              let resizeSize,
              let resizeCorner
        else { return .zero }
        let horizontalDirection: CGFloat = resizeCorner == .bottomTrailing
            ? 1
            : -1
        return CGSize(
            width: horizontalDirection * (resizeSize.width - origin.width) / 2,
            height: (resizeSize.height - origin.height) / 2
        )
    }

    private func resizeHandle(for corner: BlockResizeCorner) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .rotationEffect(corner == .bottomLeading ? .degrees(90) : .zero)
            .frame(width: 26, height: 26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .gesture(blockResizeGesture(from: corner))
            .padding(4)
            .help(
                corner == .bottomLeading
                    ? "Drag the bottom-left corner to resize"
                    : "Drag the bottom-right corner to resize"
            )
    }

    private func blockResizeGesture(
        from corner: BlockResizeCorner
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named("workflowCanvas")
        )
        .onChanged { value in
            guard !block.isLocked else { return }
            if resizeOriginSize == nil {
                resizeOriginSize = CGSize(
                    width: displayedWidth,
                    height: displayedHeight
                )
                resizeOriginPosition = block.position
                resizeCorner = corner
            }
            guard let origin = resizeOriginSize else { return }
            resizeSize = resizedBlockSize(
                from: origin,
                translation: value.translation,
                corner: corner
            )
        }
        .onEnded { value in
            guard !block.isLocked,
                  let originSize = resizeOriginSize,
                  let originPosition = resizeOriginPosition
            else {
                resizeOriginSize = nil
                resizeOriginPosition = nil
                resizeSize = nil
                resizeCorner = nil
                return
            }
            let finalSize = resizedBlockSize(
                from: originSize,
                translation: value.translation,
                corner: corner
            )
            let horizontalDirection: CGFloat = corner == .bottomTrailing
                ? 1
                : -1
            let finalPosition = CGPoint(
                x: originPosition.x
                    + horizontalDirection
                    * (finalSize.width - originSize.width) / 2,
                y: originPosition.y + (finalSize.height - originSize.height) / 2
            )
            state.resizeBlock(
                block.id,
                to: finalSize,
                position: finalPosition
            )
            resizeOriginSize = nil
            resizeOriginPosition = nil
            resizeSize = nil
            resizeCorner = nil
        }
    }

    private func resizedBlockSize(
        from origin: CGSize,
        translation: CGSize,
        corner: BlockResizeCorner
    ) -> CGSize {
        let horizontalTranslation = corner == .bottomTrailing
            ? translation.width
            : -translation.width
        return CGSize(
            width: max(
                minimumContentWidth,
                origin.width + horizontalTranslation / canvasScale
            ),
            height: max(
                minimumContentHeight,
                origin.height + translation.height / canvasScale
            )
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: block.definition.autoExecute ? "bolt.fill" : "cube")
                .font(.caption.weight(.semibold))
                .foregroundStyle(block.definition.autoExecute ? .orange : .accentColor)
            Text(block.definition.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    state.renameBlockFile(for: block.id)
                }
                .help("Double-click to rename \(block.blockFileName).js")
            Text("[\(block.definition.category)]")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        .padding(.horizontal, 9)
        .frame(height: 40)
        .background(headerBackgroundColor)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
    @Environment(\.colorScheme) private var colorScheme
    let blockID: WorkflowBlock.ID
    let option: BlockOption
    let textEditorHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            switch option.type {
            case .select:
                if usesReferencePalette {
                    ZStack {
                        referenceMenuLabel(
                            option.choices[value.wrappedValue]
                                ?? value.wrappedValue
                        )

                        ReferencePopUpHitTarget(
                            entries: referenceMenuEntries,
                            selectedIDs: [value.wrappedValue],
                            allowsMultipleSelection: false,
                            accessibilityLabel: option.name
                        ) { key in
                            value.wrappedValue = key
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .modifier(ReferenceMenuSurface())
                } else {
                    Picker(option.name, selection: value) {
                        ForEach(choiceKeys, id: \.self) { key in
                            Text(option.choices[key] ?? key)
                                .tag(key)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .color:
                HStack(spacing: 7) {
                    Circle()
                        .fill(parsedColor)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.45)))
                    TextField("#5865F2", text: value)
                        .modifier(
                            InlineOptionTextFieldStyle(
                                usesReferencePalette: usesReferencePalette
                            )
                        )
                }
            case .number:
                TextField("0", text: value)
                    .modifier(
                        InlineOptionTextFieldStyle(
                            usesReferencePalette: usesReferencePalette
                        )
                    )
            case .checkbox:
                Toggle("", isOn: booleanValue)
                    .labelsHidden()
                    .toggleStyle(.switch)
            case .multiselect:
                if usesReferencePalette {
                    ZStack {
                        referenceMenuLabel(multiSelectSummary)

                        ReferencePopUpHitTarget(
                            entries: referenceMenuEntries,
                            selectedIDs: Set(multiSelectedIDs),
                            allowsMultipleSelection: true,
                            accessibilityLabel: option.name
                        ) { key in
                            let selection = multiSelectBinding(for: key)
                            selection.wrappedValue.toggle()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .modifier(ReferenceMenuSurface())
                } else {
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
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity)
                }
            case .text, .unknown:
                TextEditor(text: value)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(fieldForegroundColor)
                    .padding(4)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: textEditorHeight,
                        maxHeight: textEditorHeight
                    )
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(fieldBorderColor)
                    }
                    .environment(\.colorScheme, controlColorScheme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(option.description)
    }

    private var referenceMenuEntries: [ReferenceMenuEntry] {
        choiceKeys.map {
            ReferenceMenuEntry(id: $0, title: option.choices[$0] ?? $0)
        }
    }

    private var multiSelectedIDs: [String] {
        state.document.blocks
            .first(where: { $0.id == blockID })?
            .optionValues[option.id]?
            .wireIDs ?? []
    }

    private var usesReferencePalette: Bool {
        colorScheme == .dark
    }

    private var controlColorScheme: ColorScheme {
        usesReferencePalette ? .light : colorScheme
    }

    private var fieldBackgroundColor: Color {
        usesReferencePalette
            ? Color(red: 243 / 255, green: 243 / 255, blue: 243 / 255)
            : Color(nsColor: .textBackgroundColor)
    }

    private var fieldForegroundColor: Color {
        usesReferencePalette ? .black : .primary
    }

    private var fieldBorderColor: Color {
        usesReferencePalette
            ? Color.black.opacity(0.45)
            : Color.secondary.opacity(0.35)
    }

    private func referenceMenuLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.isEmpty ? "None" : title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
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

private struct ReferenceMenuEntry: Equatable {
    let id: String
    let title: String
}

private struct ReferencePopUpHitTarget: NSViewRepresentable {
    let entries: [ReferenceMenuEntry]
    let selectedIDs: Set<String>
    let allowsMultipleSelection: Bool
    let accessibilityLabel: String
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.focusRingType = .none
        button.alphaValue = 0.01
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.target = context.coordinator
        button.action = #selector(Coordinator.didSelect(_:))
        return button
    }

    func updateNSView(
        _ button: NSPopUpButton,
        context: Context
    ) {
        context.coordinator.onSelect = onSelect
        button.removeAllItems()
        for entry in entries {
            button.addItem(withTitle: entry.title)
            button.lastItem?.representedObject = entry.id
        }
        button.menu?.appearance = NSAppearance(named: .aqua)
        for item in button.itemArray {
            guard let id = item.representedObject as? String else { continue }
            item.state = selectedIDs.contains(id) ? .on : .off
        }
        if !allowsMultipleSelection,
           let selectedIndex = entries.firstIndex(where: {
               selectedIDs.contains($0.id)
           }) {
            button.selectItem(at: selectedIndex)
        }
        button.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var onSelect: (String) -> Void

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        @MainActor @objc func didSelect(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else {
                return
            }
            onSelect(id)
        }
    }
}

private struct ReferenceMenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                Color(red: 243 / 255, green: 243 / 255, blue: 243 / 255),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.black.opacity(0.45))
            }
            .contentShape(Rectangle())
    }
}

private struct InlineOptionTextFieldStyle: ViewModifier {
    let usesReferencePalette: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesReferencePalette {
            content
                .textFieldStyle(.plain)
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .frame(minHeight: 24)
                .background(
                    Color(red: 243 / 255, green: 243 / 255, blue: 243 / 255),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.black.opacity(0.45))
                }
                .environment(\.colorScheme, .light)
        } else {
            content
                .textFieldStyle(.roundedBorder)
        }
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
                .lineLimit(2)
                .multilineTextAlignment(
                    port.direction == .input ? .leading : .trailing
                )
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
