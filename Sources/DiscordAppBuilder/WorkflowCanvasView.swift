import AppKit
import SwiftUI

private struct ConnectionDrag {
    let source: WorkflowPortKey
    var location: CGPoint
}

private struct ConnectionPreview {
    let start: CGPoint
    let end: CGPoint
    let color: Color
}

struct WorkflowCanvasView: View {
    @EnvironmentObject private var state: AppState
    @State private var blockPickerPosition: CGPoint?
    @State private var workspaceOffsets: [String: CGSize] = [:]
    @State private var workspaceScales: [String: CGFloat] = [:]
    @State private var panOrigin: CGSize?
    @State private var portPositions: [WorkflowPortKey: CGPoint] = [:]
    @State private var connectionDrag: ConnectionDrag?

    private var workspaceOffset: CGSize {
        guard let workspaceID = state.currentWorkspaceID else { return .zero }
        return workspaceOffsets[workspaceID] ?? .zero
    }

    private var workspaceScale: CGFloat {
        guard let workspaceID = state.currentWorkspaceID else { return 1 }
        return workspaceScales[workspaceID] ?? 1
    }

    var body: some View {
        GeometryReader { proxy in
            let graphIndex = state.graphIndex
            ZStack(alignment: .topLeading) {
                CanvasGrid(offset: workspaceOffset, scale: workspaceScale)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.clearSelection()
                    }
                    .gesture(canvasPanGesture)

                ConnectionLayer(
                    portPositions: portPositions,
                    preview: connectionPreview(using: graphIndex),
                    graphIndex: graphIndex
                )

                ForEach(state.document.blocks) { block in
                    WorkflowBlockView(
                        block: block,
                        canvasScale: workspaceScale,
                        graphIndex: graphIndex,
                        onConnectionDragChanged: { source, location in
                            updateConnectionDrag(
                                source,
                                location: location,
                                graphIndex: graphIndex
                            )
                        },
                        onConnectionDragEnded: { source, location in
                            finishConnectionDrag(
                                source,
                                location: location,
                                graphIndex: graphIndex
                            )
                        }
                    )
                        .scaleEffect(workspaceScale)
                        .position(
                            x: block.position.x * workspaceScale + workspaceOffset.width,
                            y: block.position.y * workspaceScale + workspaceOffset.height
                        )
                }

                if state.projectStore == nil {
                    VStack(spacing: 14) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Open a bot project")
                            .font(.title2.weight(.semibold))
                        Text("Create a bot project or open an existing compatible project folder.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("New Project") {
                                state.createProject()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Open Project") {
                                state.openProject()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else if state.currentWorkspaceID == nil {
                    ContentUnavailableView(
                        "No workspace open",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Choose a workspace from the channel list.")
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else if state.document.blocks.isEmpty {
                    ContentUnavailableView(
                        "Empty workspace",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Right-click anywhere to add a block.")
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                }

                CanvasEventCaptureView(
                    onRightClick: { position in
                        guard state.projectStore != nil,
                              state.currentWorkspaceID != nil
                        else { return }
                        blockPickerPosition = position
                    },
                    onScroll: zoom,
                    onDelete: {
                        guard state.hasSelection else { return false }
                        state.deleteSelection()
                        return true
                    }
                )

                if let position = blockPickerPosition {
                    let workspacePosition = CGPoint(
                        x: (position.x - workspaceOffset.width) / workspaceScale,
                        y: (position.y - workspaceOffset.height) / workspaceScale
                    )
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            blockPickerPosition = nil
                        }

                    BlockContextPicker(
                        placementPosition: workspacePosition,
                        onSelect: { definition in
                            state.addBlock(definition, at: workspacePosition)
                            blockPickerPosition = nil
                        },
                        onDismiss: {
                            blockPickerPosition = nil
                        }
                    )
                    .frame(
                        width: min(340, max(240, proxy.size.width - 24)),
                        height: min(430, max(260, proxy.size.height - 24))
                    )
                    .position(pickerPosition(for: position, in: proxy.size))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }

                if workspaceOffset != .zero || workspaceScale != 1 {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                resetWorkspaceOffset()
                            } label: {
                                Image(systemName: "scope")
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.borderless)
                            .background(.regularMaterial, in: Circle())
                            .help("Reset Canvas View")
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .coordinateSpace(name: "workflowCanvas")
            .onPreferenceChange(WorkflowPortPositionPreferenceKey.self) {
                portPositions = $0
            }
            .animation(.easeOut(duration: 0.12), value: blockPickerPosition)
        }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("workflowCanvas"))
            .onChanged { value in
                guard let workspaceID = state.currentWorkspaceID else { return }
                let origin = panOrigin ?? workspaceOffset
                if panOrigin == nil {
                    panOrigin = origin
                    state.clearSelection()
                }
                workspaceOffsets[workspaceID] = CGSize(
                    width: origin.width + value.translation.width,
                    height: origin.height + value.translation.height
                )
            }
            .onEnded { _ in
                panOrigin = nil
            }
    }

    private func resetWorkspaceOffset() {
        guard let workspaceID = state.currentWorkspaceID else { return }
        workspaceOffsets[workspaceID] = .zero
        workspaceScales[workspaceID] = 1
        panOrigin = nil
    }

    private func zoom(at position: CGPoint, delta: CGFloat, isPrecise: Bool) {
        guard let workspaceID = state.currentWorkspaceID,
              state.projectStore != nil,
              delta != 0
        else { return }

        let oldScale = workspaceScale
        let sensitivity: CGFloat = isPrecise ? 0.008 : 0.06
        let newScale = min(2.5, max(0.35, oldScale * exp(delta * sensitivity)))
        guard newScale != oldScale else { return }

        let oldOffset = workspaceOffset
        let workspacePoint = CGPoint(
            x: (position.x - oldOffset.width) / oldScale,
            y: (position.y - oldOffset.height) / oldScale
        )
        workspaceScales[workspaceID] = newScale
        workspaceOffsets[workspaceID] = CGSize(
            width: position.x - workspacePoint.x * newScale,
            height: position.y - workspacePoint.y * newScale
        )
        blockPickerPosition = nil
    }

    private func connectionPreview(using graphIndex: WorkflowGraphIndex) -> ConnectionPreview? {
        guard let connectionDrag,
              let sourcePosition = portPositions[connectionDrag.source],
              let sourcePort = port(for: connectionDrag.source, graphIndex: graphIndex)
        else { return nil }

        let target = compatibleTarget(
            for: connectionDrag.source,
            near: connectionDrag.location,
            graphIndex: graphIndex
        )
        let targetPosition = target.flatMap { portPositions[$0] } ?? connectionDrag.location
        let previewType = target
            .flatMap { port(for: $0, graphIndex: graphIndex) }
            .map { sourcePort.resolvedValueType(connectedTo: $0) }
            ?? sourcePort.resolvedValueType()
        if connectionDrag.source.direction == .output {
            return ConnectionPreview(
                start: sourcePosition,
                end: targetPosition,
                color: previewType.color
            )
        }
        return ConnectionPreview(
            start: targetPosition,
            end: sourcePosition,
            color: previewType.color
        )
    }

    private func updateConnectionDrag(
        _ source: WorkflowPortKey,
        location: CGPoint,
        graphIndex: WorkflowGraphIndex
    ) {
        guard let sourcePort = port(for: source, graphIndex: graphIndex),
              isAvailableConnectionTarget(
                  source,
                  port: sourcePort,
                  graphIndex: graphIndex
              )
        else { return }
        connectionDrag = ConnectionDrag(source: source, location: location)
    }

    private func finishConnectionDrag(
        _ source: WorkflowPortKey,
        location: CGPoint,
        graphIndex: WorkflowGraphIndex
    ) {
        defer { connectionDrag = nil }
        guard let sourcePort = port(for: source, graphIndex: graphIndex),
              isAvailableConnectionTarget(
                  source,
                  port: sourcePort,
                  graphIndex: graphIndex
              ),
              let target = compatibleTarget(
                  for: source,
                  near: location,
                  graphIndex: graphIndex
              )
        else { return }

        let output = source.direction == .output ? source : target
        let input = source.direction == .input ? source : target
        state.beginConnection(from: output.blockID, portID: output.portID)
        state.completeConnection(to: input.blockID, portID: input.portID)
    }

    private func compatibleTarget(
        for source: WorkflowPortKey,
        near location: CGPoint,
        graphIndex: WorkflowGraphIndex
    ) -> WorkflowPortKey? {
        guard let sourcePort = port(for: source, graphIndex: graphIndex) else { return nil }
        let snapDistance: CGFloat = 28

        return portPositions
            .filter { key, position in
                guard key.direction != source.direction,
                      key.blockID != source.blockID,
                      hypot(position.x - location.x, position.y - location.y) <= snapDistance,
                      let targetPort = port(for: key, graphIndex: graphIndex),
                      isAvailableConnectionTarget(
                          key,
                          port: targetPort,
                          graphIndex: graphIndex
                      )
                else { return false }
                return targetPort.accepts(sourcePort)
            }
            .min {
                hypot($0.value.x - location.x, $0.value.y - location.y) <
                hypot($1.value.x - location.x, $1.value.y - location.y)
            }?
            .key
    }

    private func isAvailableConnectionTarget(
        _ key: WorkflowPortKey,
        port: BlockPort,
        graphIndex: WorkflowGraphIndex
    ) -> Bool {
        guard port.allowsMultipleConnections else { return true }
        let endpoint = WorkflowPortEndpoint(
            blockID: key.blockID,
            portID: key.portID,
            direction: key.direction
        )
        var occupiedCount = graphIndex.connectionCount(for: endpoint)
        if key.direction == .input {
            occupiedCount = max(
                occupiedCount,
                graphIndex.storedInputCount(for: endpoint)
            )
        }
        return key.occurrence >= occupiedCount
    }

    private func port(
        for key: WorkflowPortKey,
        graphIndex: WorkflowGraphIndex
    ) -> BlockPort? {
        graphIndex.port(
            for: WorkflowPortEndpoint(
                blockID: key.blockID,
                portID: key.portID,
                direction: key.direction
            )
        )
    }

    private func pickerPosition(for click: CGPoint, in size: CGSize) -> CGPoint {
        let pickerWidth = min(340, max(240, size.width - 24))
        let pickerHeight = min(430, max(260, size.height - 24))
        let halfWidth = pickerWidth / 2
        let halfHeight = pickerHeight / 2
        return CGPoint(
            x: min(max(click.x + halfWidth, halfWidth + 12), size.width - halfWidth - 12),
            y: min(max(click.y + halfHeight, halfHeight + 12), size.height - halfHeight - 12)
        )
    }
}

private struct BlockContextPicker: View {
    @EnvironmentObject private var state: AppState
    let placementPosition: CGPoint
    let onSelect: (BlockDefinition) -> Void
    let onDismiss: () -> Void
    @State private var query = ""
    @FocusState private var searchIsFocused: Bool

    private var matchingBlocks: [BlockDefinition] {
        guard !query.isEmpty else { return state.library }
        return state.library.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var categories: [String] {
        Array(Set(matchingBlocks.map(\.category))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search blocks", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if state.library.isEmpty {
                ContentUnavailableView(
                    "No project blocks",
                    systemImage: "shippingbox",
                    description: Text("Add compatible block files to this project's blocks folder.")
                )
            } else if matchingBlocks.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)

                                ForEach(matchingBlocks.filter { $0.category == category }) { definition in
                                    Button {
                                        onSelect(definition)
                                    } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: definition.autoExecute ? "bolt.fill" : "cube")
                                                .foregroundStyle(definition.autoExecute ? .orange : .accentColor)
                                                .frame(width: 18)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(definition.name)
                                                    .font(.callout.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if !definition.description.isEmpty {
                                                    Text(definition.description)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3))
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .onAppear {
            searchIsFocused = true
        }
        .onExitCommand {
            onDismiss()
        }
        .accessibilityLabel("Add block at \(Int(placementPosition.x)), \(Int(placementPosition.y))")
    }
}

private struct CanvasEventCaptureView: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void
    let onScroll: (CGPoint, CGFloat, Bool) -> Void
    let onDelete: () -> Bool

    func makeNSView(context: Context) -> CanvasEventView {
        let view = CanvasEventView()
        view.onRightClick = onRightClick
        view.onScroll = onScroll
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: CanvasEventView, context: Context) {
        nsView.onRightClick = onRightClick
        nsView.onScroll = onScroll
        nsView.onDelete = onDelete
    }

    static func dismantleNSView(
        _ nsView: CanvasEventView,
        coordinator: ()
    ) {
        nsView.stopMonitoringKeys()
    }

    final class CanvasEventView: NSView {
        var onRightClick: ((CGPoint) -> Void)?
        var onScroll: ((CGPoint, CGFloat, Bool) -> Void)?
        var onDelete: (() -> Bool)?
        private var keyMonitor: Any?

        override var isFlipped: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoringKeys()
            guard window != nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                self?.handleKeyDown(event) ?? event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let eventType = NSApp.currentEvent?.type,
                  eventType == .rightMouseDown || eventType == .scrollWheel
            else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            let position = convert(event.locationInWindow, from: nil)
            onRightClick?(position)
        }

        override func scrollWheel(with event: NSEvent) {
            let position = convert(event.locationInWindow, from: nil)
            onScroll?(position, event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
        }

        func stopMonitoringKeys() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard event.window === window,
                  event.keyCode == 51 || event.keyCode == 117,
                  event.modifierFlags.intersection([
                      .command,
                      .control,
                      .option,
                      .shift
                  ]).isEmpty,
                  !(window?.firstResponder is NSTextView),
                  onDelete?() == true
            else {
                return event
            }
            return nil
        }

    }
}

private struct CanvasGrid: View {
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = 24 * scale
            let xOffset = offset.width.truncatingRemainder(dividingBy: spacing)
            let yOffset = offset.height.truncatingRemainder(dividingBy: spacing)
            var path = Path()
            stride(from: xOffset - spacing, through: size.width + spacing, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: yOffset - spacing, through: size.height + spacing, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.13)), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

private struct ConnectionLayer: View {
    @EnvironmentObject private var state: AppState
    let portPositions: [WorkflowPortKey: CGPoint]
    let preview: ConnectionPreview?
    let graphIndex: WorkflowGraphIndex

    var body: some View {
        ZStack {
            ForEach(state.document.connections) { connection in
                if let path = path(for: connection) {
                    let isSelected = state.selectedConnectionID == connection.id
                    let hitPath = path.strokedPath(
                        StrokeStyle(
                            lineWidth: 18,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    if isSelected {
                        path
                            .stroke(
                                Color.primary.opacity(0.9),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                    }

                    path
                        .stroke(
                            color(for: connection).opacity(isSelected ? 1 : 0.82),
                            style: StrokeStyle(
                                lineWidth: isSelected ? 4 : 3,
                                lineCap: .round
                            )
                        )

                    hitPath
                        .fill(Color.primary.opacity(0.001))
                        .contentShape(hitPath)
                        .onTapGesture {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            state.selectConnection(connection.id)
                        }
                        .help("Click to select this link, then press Delete")
                }
            }

            if let preview {
                connectionPath(from: preview.start, to: preview.end)
                    .stroke(
                        preview.color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5])
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func path(for connection: WorkflowConnection) -> Path? {
        let occurrences = graphIndex.occurrences(for: connection)
        let outputKey = WorkflowPortKey(
            blockID: connection.fromBlockID,
            portID: connection.fromPortID,
            direction: .output,
            occurrence: occurrences.output
        )
        let inputKey = WorkflowPortKey(
            blockID: connection.toBlockID,
            portID: connection.toPortID,
            direction: .input,
            occurrence: occurrences.input
        )
        guard let start = portPositions[outputKey],
              let end = portPositions[inputKey]
        else { return nil }

        return connectionPath(from: start, to: end)
    }

    private func color(for connection: WorkflowConnection) -> Color {
        graphIndex.resolvedValueType(for: connection).color
    }

    private func connectionPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let delta = max(50, abs(end.x - start.x) / 2)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + delta, y: start.y),
            control2: CGPoint(x: end.x - delta, y: end.y)
        )
        return path
    }
}
