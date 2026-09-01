import {
  useCallback, useEffect, useMemo, useRef, useState, type DragEvent, type ReactNode
} from "react";
import {
  Background, BackgroundVariant, Controls, MiniMap, ReactFlow, ReactFlowProvider,
  applyNodeChanges, type Connection, type EdgeChange, type NodeChange
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import {
  ChevronDown, ChevronRight, Copy, Download, FilePlus2, FolderOpen,
  Hash, PackageOpen, Plus, RefreshCw, Save, Search, SunMoon, Trash2, X
} from "lucide-react";
import type {
  AppSettings, Appearance, BlockDefinition, ProjectData, StoredWorkspace,
  WorkflowBlock, WorkflowConnection, WorkflowDocument, WorkspaceGroup
} from "./types";
import {
  accepts, connectBlocks, createBlock, makeID, portFor, removeConnections,
  resolvedType, valueColors
} from "./editor-model";
import { WorkflowBlockNode, type WorkflowNode } from "./WorkflowBlockNode";
import { WorkflowEdge, type WorkflowEdgeType } from "./WorkflowEdge";

type PromptRequest = {
  title: string;
  message: string;
  value: string;
  confirmText?: string;
  destructive?: boolean;
  resolve: (value: string | null) => void;
};

type MenuState = {
  x: number;
  y: number;
  items: Array<{ label: string; icon?: ReactNode; danger?: boolean; disabled?: boolean; action: () => void }>;
};

function PromptDialog({ request, close }: { request: PromptRequest; close: (value: string | null) => void }) {
  const [value, setValue] = useState(request.value);
  return (
    <div className="modal-shade" role="presentation" onMouseDown={() => close(null)}>
      <form
        className="modal"
        onMouseDown={(event) => event.stopPropagation()}
        onSubmit={(event) => { event.preventDefault(); close(value.trim() || null); }}
      >
        <h2>{request.title}</h2>
        <p>{request.message}</p>
        <input autoFocus value={value} onChange={(event) => setValue(event.target.value)} />
        <footer>
          <button type="button" onClick={() => close(null)}>Cancel</button>
          <button className={request.destructive ? "danger" : "primary"} type="submit">
            {request.confirmText || "Confirm"}
          </button>
        </footer>
      </form>
    </div>
  );
}

function ContextMenu({ menu, dismiss }: { menu: MenuState; dismiss: () => void }) {
  return (
    <div className="context-shade" onMouseDown={dismiss} onContextMenu={(event) => event.preventDefault()}>
      <div className="context-menu" style={{ left: menu.x, top: menu.y }} onMouseDown={(event) => event.stopPropagation()}>
        {menu.items.map((item, index) => (
          <button
            key={`${item.label}-${index}`}
            disabled={item.disabled}
            className={item.danger ? "danger" : ""}
            onClick={() => { dismiss(); item.action(); }}
          >
            {item.icon}<span>{item.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function initials(name: string): string {
  const parts = name.split(/[\s_-]+/).filter(Boolean);
  return (parts.length > 1 ? `${parts[0][0]}${parts[1][0]}` : name.slice(0, 2)).toUpperCase();
}

function Toolbar({
  hasProject, dirty, appearance, action
}: {
  hasProject: boolean;
  dirty: boolean;
  appearance: Appearance;
  action: (command: string) => void;
}) {
  return (
    <div className="toolbar">
      <button title="New Project" onClick={() => action("new-project")}><FilePlus2 /></button>
      <button title="Open Project" onClick={() => action("open-project")}><FolderOpen /></button>
      <span className="toolbar-divider" />
      <button disabled={!hasProject || !dirty} title="Save Project" onClick={() => action("save")}><Save /></button>
      <button disabled={!hasProject} title="Import Blocks" onClick={() => action("import-blocks")}><PackageOpen /></button>
      <button disabled={!hasProject} title="Import Workspaces" onClick={() => action("import-workspaces")}><Download /></button>
      <button disabled={!hasProject} title="Update bot.js" onClick={() => action("update-runtime")}><RefreshCw /></button>
      <span className="toolbar-spacer" />
      <button title={`Appearance: ${appearance}`} onClick={() => action("appearance")}><SunMoon /></button>
    </div>
  );
}

function ProjectRail({
  settings, project, openRecent, newProject, openProject
}: {
  settings: AppSettings;
  project: ProjectData | null;
  openRecent: (path: string) => void;
  newProject: () => void;
  openProject: () => void;
}) {
  return (
    <aside className="project-rail">
      <div className="project-list">
        {settings.recentProjects.map((projectPath, index) => {
          const name = projectPath.split(/[\\/]/).filter(Boolean).at(-1) || "Project";
          const active = project?.projectPath === projectPath;
          return (
            <button
              key={projectPath}
              className={`project-orb color-${index % 7} ${active ? "active" : ""}`}
              title={name}
              onClick={() => openRecent(projectPath)}
            >
              <i />{initials(name)}
            </button>
          );
        })}
      </div>
      <div className="rail-actions">
        <button title="New Project" onClick={newProject}><Plus /></button>
        <button title="Open Project" onClick={openProject}><FolderOpen /></button>
      </div>
    </aside>
  );
}

function WorkspaceSidebar({
  project, activeWorkspaceID, selectWorkspace, mutateGroups, duplicateWorkspace,
  deleteWorkspace, copyWorkspace, pasteWorkspace, renameWorkspace, prompt, showMenu, status
}: {
  project: ProjectData | null;
  activeWorkspaceID: string | null;
  selectWorkspace: (id: string) => void;
  mutateGroups: (mutator: (groups: WorkspaceGroup[]) => void) => void;
  duplicateWorkspace: (workspaceID: string) => void;
  deleteWorkspace: (workspaceID: string) => void;
  copyWorkspace: (workspaceID: string) => void;
  pasteWorkspace: (groupID: string) => void;
  renameWorkspace: (workspaceID: string, title: string) => void;
  prompt: (title: string, message: string, value?: string) => Promise<string | null>;
  showMenu: (event: React.MouseEvent, items: MenuState["items"]) => void;
  status: string;
}) {
  if (!project) {
    return <aside className="workspace-sidebar empty"><strong>No project open</strong><span>Choose a project from the left.</span></aside>;
  }

  const addCategory = async () => {
    const title = await prompt("Create Category", "Categories organize related workspaces.", "New Category");
    if (!title) return;
    mutateGroups((groups) => groups.push({
      id: makeID(), info: { title, collapsed: false }, workspaces: []
    }));
  };

  const addWorkspace = async (groupID: string) => {
    const title = await prompt("Create Workspace", "Workspaces appear like channels in their category.", "new-workspace");
    if (!title) return;
    const workspace: StoredWorkspace = {
      id: makeID(), active: true,
      info: { title, description: "", thumbnail: "" }, blocks: [], notes: []
    };
    mutateGroups((groups) => groups.find((group) => group.id === groupID)?.workspaces.push(workspace));
    selectWorkspace(workspace.id);
  };

  return (
    <aside className="workspace-sidebar">
      <header>
        <div><strong>{project.projectName}</strong><span>{Object.keys(project.documents).length} workspaces</span></div>
        <button title="Add Category" onClick={addCategory}><Plus /></button>
      </header>
      <div className="workspace-groups">
        {project.groups.map((group) => (
          <section
            className="workspace-group"
            key={group.id}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => {
              const workspaceID = event.dataTransfer.getData("application/x-workspace-id");
              if (!workspaceID) return;
              mutateGroups((groups) => {
                let moved: StoredWorkspace | undefined;
                for (const source of groups) {
                  const index = source.workspaces.findIndex((workspace) => workspace.id === workspaceID);
                  if (index >= 0) moved = source.workspaces.splice(index, 1)[0];
                }
                if (moved) groups.find((item) => item.id === group.id)?.workspaces.push(moved);
              });
            }}
          >
            <div
              className="category-row"
              onContextMenu={(event) => showMenu(event, [
                { label: "Add Workspace", icon: <Plus />, action: () => addWorkspace(group.id) },
                { label: "Paste Workspace", icon: <Copy />, action: () => pasteWorkspace(group.id) },
                { label: "Rename Category", action: async () => {
                  const title = await prompt("Rename Category", "Choose a new category name.", group.info.title);
                  if (title) mutateGroups((groups) => { const item = groups.find((entry) => entry.id === group.id); if (item) item.info.title = title; });
                }}
              ])}
            >
              <button onClick={() => mutateGroups((groups) => {
                const item = groups.find((entry) => entry.id === group.id);
                if (item) item.info.collapsed = !item.info.collapsed;
              })}>
                {group.info.collapsed ? <ChevronRight /> : <ChevronDown />}
              </button>
              <strong>{group.info.title.toUpperCase()}</strong>
              <button title="Add Workspace" onClick={() => addWorkspace(group.id)}><Plus /></button>
            </div>
            {!group.info.collapsed && group.workspaces.map((workspace) => (
              <button
                draggable
                key={workspace.id}
                className={`workspace-row ${workspace.id === activeWorkspaceID ? "active" : ""} ${workspace.active ? "" : "disabled"}`}
                onDragStart={(event) => event.dataTransfer.setData("application/x-workspace-id", workspace.id)}
                onClick={() => selectWorkspace(workspace.id)}
                onContextMenu={(event) => showMenu(event, [
                  { label: "Open", action: () => selectWorkspace(workspace.id) },
                  { label: workspace.active ? "Disable Workspace" : "Enable Workspace", action: () => mutateGroups((groups) => {
                    for (const entry of groups) {
                      const item = entry.workspaces.find((candidate) => candidate.id === workspace.id);
                      if (item) item.active = !item.active;
                    }
                  }) },
                  { label: "Rename Workspace", action: async () => {
                    const title = await prompt("Rename Workspace", "Choose a new workspace name.", workspace.info.title);
                    if (title) renameWorkspace(workspace.id, title);
                  } },
                  { label: "Copy Workspace", icon: <Copy />, action: () => copyWorkspace(workspace.id) },
                  { label: "Duplicate Workspace", action: () => duplicateWorkspace(workspace.id) },
                  { label: "Delete Workspace", icon: <Trash2 />, danger: true, action: () => deleteWorkspace(workspace.id) }
                ])}
              >
                <Hash /><span>{workspace.info.title}</span>{!workspace.active && <i>Paused</i>}
              </button>
            ))}
          </section>
        ))}
      </div>
      <footer>{status}</footer>
    </aside>
  );
}

function TabBar({
  project, tabs, active, select, close
}: {
  project: ProjectData;
  tabs: string[];
  active: string | null;
  select: (id: string) => void;
  close: (id: string) => void;
}) {
  const workspaceName = (id: string) => project.groups.flatMap((group) => group.workspaces)
    .find((workspace) => workspace.id === id)?.info.title || "Workspace";
  return (
    <div className="tabbar">
      {tabs.map((id) => (
        <button key={id} className={id === active ? "active" : ""} onClick={() => select(id)}>
          <Hash /><span>{workspaceName(id)}</span>
          <X onClick={(event) => { event.stopPropagation(); close(id); }} />
        </button>
      ))}
    </div>
  );
}

function BlockPicker({
  library, x, y, choose, close
}: {
  library: BlockDefinition[];
  x: number;
  y: number;
  choose: (definition: BlockDefinition) => void;
  close: () => void;
}) {
  const [search, setSearch] = useState("");
  const filtered = library.filter((block) =>
    `${block.name} ${block.category} ${block.description}`.toLowerCase().includes(search.toLowerCase()));
  const groups = filtered.reduce<Record<string, BlockDefinition[]>>((result, block) => {
    (result[block.category] ||= []).push(block);
    return result;
  }, {});
  return (
    <div className="picker-shade" onMouseDown={close}>
      <div className="block-picker" style={{ left: x, top: y }} onMouseDown={(event) => event.stopPropagation()}>
        <label><Search /><input autoFocus placeholder="Search blocks" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
        <div>
          {Object.entries(groups).map(([category, blocks]) => (
            <section key={category}>
              <h3>{category}</h3>
              {blocks?.map((block) => (
                <button key={block.sourceFile} onClick={() => choose(block)}>
                  <strong>{block.name}</strong><span>{block.description}</span>
                </button>
              ))}
            </section>
          ))}
          {!filtered.length && <p className="no-results">No matching blocks</p>}
        </div>
      </div>
    </div>
  );
}

type ClipboardPayload = { blocks: WorkflowBlock[]; connections: WorkflowConnection[] };
type WorkspaceClipboard = { workspace: StoredWorkspace; document: WorkflowDocument };

function clonedWorkspaceDocument(
  source: WorkflowDocument,
  workspaceID: string,
  title: string
): WorkflowDocument {
  const blockIDs = new Map<string, string>();
  const blocks = source.blocks.map((block, index) => {
    const id = crypto.randomUUID();
    blockIDs.set(block.id, id);
    return {
      ...structuredClone(block),
      id,
      runtimeBlockID: `${workspaceID}:${index}`
    };
  });
  const connections = source.connections.map((connection) => ({
    ...structuredClone(connection),
    id: crypto.randomUUID(),
    fromBlockID: blockIDs.get(connection.fromBlockID)!,
    toBlockID: blockIDs.get(connection.toBlockID)!
  }));
  return { name: title, blocks, connections };
}

function WorkflowCanvas({
  project, workspaceID, updateDocument, replaceProject, prompt, showStatus
}: {
  project: ProjectData;
  workspaceID: string;
  updateDocument: (workspaceID: string, update: (document: WorkflowDocument) => WorkflowDocument) => void;
  replaceProject: (project: ProjectData) => void;
  prompt: (title: string, message: string, value?: string) => Promise<string | null>;
  showStatus: (message: string) => void;
}) {
  const document = project.documents[workspaceID];
  const [selectedBlocks, setSelectedBlocks] = useState<Set<string>>(new Set());
  const [selectedConnection, setSelectedConnection] = useState<string | null>(null);
  const [picker, setPicker] = useState<{ screenX: number; screenY: number; flowX: number; flowY: number } | null>(null);
  const [flow, setFlow] = useState<import("@xyflow/react").ReactFlowInstance<WorkflowNode, WorkflowEdgeType> | null>(null);
  const clipboard = useRef<ClipboardPayload | null>(null);

  useEffect(() => { setSelectedBlocks(new Set()); setSelectedConnection(null); }, [workspaceID]);

  const updateOption = useCallback(async (blockID: string, optionID: string, value: unknown) => {
    let sourceFile = "";
    let values: Record<string, unknown> = {};
    let dynamic = false;
    updateDocument(workspaceID, (current) => ({
      ...current,
      blocks: current.blocks.map((block) => {
        if (block.id !== blockID) return block;
        values = { ...block.optionValues, [optionID]: value };
        sourceFile = block.definition.sourceFile;
        dynamic = block.definition.usesDynamicMetadata;
        return { ...block, optionValues: values };
      })
    }));
    if (!dynamic) return;
    try {
      const definition = await window.builderAPI.configuredBlock(project.projectPath, sourceFile, values);
      updateDocument(workspaceID, (current) => ({
        ...current,
        blocks: current.blocks.map((block) => block.id === blockID ? { ...block, definition } : block)
      }));
    } catch (error) {
      showStatus(`Could not refresh block options: ${(error as Error).message}`);
    }
  }, [project.projectPath, showStatus, updateDocument, workspaceID]);

  const deleteSelection = useCallback(() => {
    updateDocument(workspaceID, (current) => {
      if (selectedConnection) {
        return removeConnections(current, (connection) => connection.id === selectedConnection);
      }
      if (!selectedBlocks.size) return current;
      const withoutLinks = removeConnections(current, (connection) =>
        selectedBlocks.has(connection.fromBlockID) || selectedBlocks.has(connection.toBlockID));
      return { ...withoutLinks, blocks: withoutLinks.blocks.filter((block) => !selectedBlocks.has(block.id)) };
    });
    setSelectedBlocks(new Set());
    setSelectedConnection(null);
  }, [selectedBlocks, selectedConnection, updateDocument, workspaceID]);

  const copySelection = useCallback(() => {
    const blocks = document.blocks.filter((block) => selectedBlocks.has(block.id));
    if (!blocks.length) return;
    const ids = new Set(blocks.map((block) => block.id));
    clipboard.current = {
      blocks: structuredClone(blocks),
      connections: structuredClone(document.connections.filter((connection) =>
        ids.has(connection.fromBlockID) && ids.has(connection.toBlockID)))
    };
  }, [document, selectedBlocks]);

  const pasteSelection = useCallback(() => {
    if (!clipboard.current) return;
    const idMap = new Map<string, string>();
    const blocks = clipboard.current.blocks.map((block, index) => {
      const id = crypto.randomUUID();
      idMap.set(block.id, id);
      const inputWireValues: Record<string, unknown> = Object.fromEntries(block.definition.inputs.map((port) => [
        port.id,
        port.allowsMultipleConnections ? [] : makeID()
      ]));
      return {
        ...structuredClone(block), id,
        runtimeBlockID: `${workspaceID}:${document.blocks.length + index}`,
        position: { x: block.position.x + 32, y: block.position.y + 32 },
        inputWireValues
      };
    });
    const connections = clipboard.current.connections.map((connection) => ({
      ...connection,
      id: crypto.randomUUID(),
      wireID: makeID(),
      fromBlockID: idMap.get(connection.fromBlockID)!,
      toBlockID: idMap.get(connection.toBlockID)!
    }));
    for (const connection of connections) {
      const target = blocks.find((block) => block.id === connection.toBlockID);
      if (!target) continue;
      const value = target.inputWireValues[connection.toPortID];
      if (Array.isArray(value)) target.inputWireValues[connection.toPortID] = [...value, connection.wireID];
      else target.inputWireValues[connection.toPortID] = connection.wireID;
    }
    updateDocument(workspaceID, (current) => ({
      ...current, blocks: [...current.blocks, ...blocks], connections: [...current.connections, ...connections]
    }));
    setSelectedBlocks(new Set(blocks.map((block) => block.id)));
  }, [document.blocks.length, updateDocument, workspaceID]);

  const renameBlock = useCallback(async (block: WorkflowBlock) => {
    const name = await prompt(
      "Rename Block File",
      "This renames the .js file and updates every workspace that uses it.",
      `${block.blockFileName}.js`
    );
    if (!name) return;
    try {
      const loaded = await window.builderAPI.renameBlockFile({
        projectPath: project.projectPath,
        oldName: block.blockFileName,
        newName: name,
        groups: project.groups,
        documents: project.documents
      });
      replaceProject(loaded);
      showStatus(`Renamed ${block.blockFileName}.js`);
    } catch (error) {
      showStatus((error as Error).message);
    }
  }, [project, prompt, replaceProject, showStatus]);

  useEffect(() => {
    const command = (event: Event) => {
      const value = (event as CustomEvent<string>).detail;
      if (value === "delete") deleteSelection();
      if (value === "copy") copySelection();
      if (value === "cut") { copySelection(); deleteSelection(); }
      if (value === "paste") pasteSelection();
      if (value === "select-all") setSelectedBlocks(new Set(document.blocks.map((block) => block.id)));
    };
    window.addEventListener("builder-command", command);
    return () => window.removeEventListener("builder-command", command);
  }, [copySelection, deleteSelection, document.blocks, pasteSelection]);

  const counts = useMemo(() => {
    const result: Record<string, Record<string, number>> = {};
    for (const connection of document.connections) {
      result[connection.fromBlockID] ||= {};
      result[connection.toBlockID] ||= {};
      result[connection.fromBlockID][`output:${connection.fromPortID}`] =
        (result[connection.fromBlockID][`output:${connection.fromPortID}`] || 0) + 1;
      result[connection.toBlockID][`input:${connection.toPortID}`] =
        (result[connection.toBlockID][`input:${connection.toPortID}`] || 0) + 1;
    }
    return result;
  }, [document.connections]);

  const generatedNodes: WorkflowNode[] = useMemo(() => document.blocks.map((block) => ({
    id: block.id,
    type: "workflowBlock",
    position: block.position,
    width: block.width,
    height: block.height,
    selected: selectedBlocks.has(block.id),
    dragHandle: ".block-header",
    zIndex: block.zIndex,
    data: {
      block,
      workspaceID,
      connectionCounts: counts[block.id] || {},
      onOptionChange: updateOption,
      onRename: renameBlock,
      onDelete: (blockID) => {
        const selected = selectedBlocks.has(blockID) ? selectedBlocks : new Set([blockID]);
        updateDocument(workspaceID, (current) => {
          const withoutLinks = removeConnections(current, (connection) =>
            selected.has(connection.fromBlockID) || selected.has(connection.toBlockID));
          return { ...withoutLinks, blocks: withoutLinks.blocks.filter((item) => !selected.has(item.id)) };
        });
      }
    }
  })), [counts, document.blocks, renameBlock, selectedBlocks, updateDocument, updateOption, workspaceID]);

  const [nodes, setNodes] = useState<WorkflowNode[]>(generatedNodes);
  useEffect(() => {
    setNodes((current) => {
      const existingByID = new Map(current.map((node) => [node.id, node]));
      return generatedNodes.map((node) => {
        const existing = existingByID.get(node.id);
        return existing?.measured
          ? { ...node, measured: existing.measured }
          : node;
      });
    });
  }, [generatedNodes]);

  const edges: WorkflowEdgeType[] = useMemo(() => {
    const occurrences = new Map<string, number>();
    return document.connections.map((connection) => {
      const sourcePort = portFor(document, connection.fromBlockID, connection.fromPortID, "output");
      const targetPort = portFor(document, connection.toBlockID, connection.toPortID, "input");
      const sourceKey = `${connection.fromBlockID}:output:${connection.fromPortID}`;
      const targetKey = `${connection.toBlockID}:input:${connection.toPortID}`;
      const sourceOccurrence = sourcePort?.allowsMultipleConnections ? occurrences.get(sourceKey) || 0 : 0;
      const targetOccurrence = targetPort?.allowsMultipleConnections ? occurrences.get(targetKey) || 0 : 0;
      occurrences.set(sourceKey, sourceOccurrence + 1);
      occurrences.set(targetKey, targetOccurrence + 1);
      return {
        id: connection.id,
        type: "workflowEdge",
        source: connection.fromBlockID,
        target: connection.toBlockID,
        sourceHandle: `output:${connection.fromPortID}:${sourceOccurrence}`,
        targetHandle: `input:${connection.toPortID}:${targetOccurrence}`,
        selected: selectedConnection === connection.id,
        interactionWidth: 24,
        data: { color: valueColors[resolvedType(sourcePort, targetPort)] }
      };
    });
  }, [document, selectedConnection]);

  const onNodesChange = useCallback((changes: NodeChange<WorkflowNode>[]) => {
    setNodes((current) => applyNodeChanges(changes, current));
    const selectionChanges = changes.filter((change) => change.type === "select");
    if (selectionChanges.length) setSelectedBlocks((current) => {
      const selected = new Set(current);
      for (const change of selectionChanges) {
        if (change.type !== "select") continue;
        if (change.selected) selected.add(change.id);
        else selected.delete(change.id);
      }
      return selected;
    });
    const geometryChanges = changes.filter((change) =>
      (change.type === "position" && change.position != null) ||
      (change.type === "dimensions" && change.resizing != null)
    );
    if (!geometryChanges.length) return;
    updateDocument(workspaceID, (current) => ({
      ...current,
      blocks: current.blocks.map((block) => {
        let next = block;
        for (const change of geometryChanges) {
          if (change.type !== "position" && change.type !== "dimensions") continue;
          if (change.id !== block.id) continue;
          if (change.type === "position" && change.position) {
            next = { ...next, position: change.position };
          }
          if (change.type === "dimensions" && change.dimensions) {
            next = {
              ...next,
              width: Math.max(220, change.dimensions.width),
              height: Math.max(140, change.dimensions.height)
            };
          }
        }
        return next;
      })
    }));
  }, [updateDocument, workspaceID]);

  const onEdgesChange = useCallback((changes: EdgeChange<WorkflowEdgeType>[]) => {
    for (const change of changes) {
      if (change.type === "select") setSelectedConnection(change.selected ? change.id : null);
      if (change.type === "remove") {
        updateDocument(workspaceID, (current) => removeConnections(current, (item) => item.id === change.id));
      }
    }
  }, [updateDocument, workspaceID]);

  const onConnect = useCallback((connection: Connection) => {
    const sourceParts = connection.sourceHandle?.split(":") || [];
    const targetParts = connection.targetHandle?.split(":") || [];
    if (!connection.source || !connection.target || sourceParts[0] !== "output" || targetParts[0] !== "input") return;
    updateDocument(workspaceID, (current) => connectBlocks(
      current, connection.source!, sourceParts[1], connection.target!, targetParts[1]
    ));
  }, [updateDocument, workspaceID]);

  const validConnection = useCallback((connection: Connection | WorkflowEdgeType) => {
    if (!("sourceHandle" in connection) || !connection.source || !connection.target) return false;
    const sourceID = connection.sourceHandle?.split(":")[1];
    const targetID = connection.targetHandle?.split(":")[1];
    if (!sourceID || !targetID) return false;
    const source = portFor(document, connection.source, sourceID, "output");
    const target = portFor(document, connection.target, targetID, "input");
    return Boolean(source && target && accepts(source, target));
  }, [document]);

  if (!document) return <div className="empty-canvas">Workspace could not be loaded.</div>;

  return (
    <div className="canvas-wrap">
      <ReactFlow<WorkflowNode, WorkflowEdgeType>
        nodes={nodes}
        edges={edges}
        nodeTypes={{ workflowBlock: WorkflowBlockNode }}
        edgeTypes={{ workflowEdge: WorkflowEdge }}
        onInit={setFlow}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        isValidConnection={validConnection}
        onEdgeClick={(_event, edge) => { setSelectedBlocks(new Set()); setSelectedConnection(edge.id); }}
        onPaneClick={() => { setSelectedBlocks(new Set()); setSelectedConnection(null); }}
        onPaneContextMenu={(event) => {
          event.preventDefault();
          const point = flow?.screenToFlowPosition({ x: event.clientX, y: event.clientY }) || { x: 100, y: 100 };
          setPicker({ screenX: Math.min(event.clientX, window.innerWidth - 350), screenY: Math.min(event.clientY, window.innerHeight - 470), flowX: point.x, flowY: point.y });
        }}
        panOnDrag={[0]}
        zoomOnScroll
        zoomOnPinch
        multiSelectionKeyCode={["Control", "Meta"]}
        deleteKeyCode={null}
        minZoom={0.15}
        maxZoom={2.5}
      >
        <Background variant={BackgroundVariant.Lines} gap={24} size={1} />
        <Controls showInteractive={false} />
        <MiniMap nodeStrokeWidth={2} pannable zoomable />
      </ReactFlow>
      {!document.blocks.length && <div className="canvas-empty"><PackageOpen /><strong>Empty workspace</strong></div>}
      {picker && (
        <BlockPicker
          library={project.library}
          x={picker.screenX}
          y={picker.screenY}
          close={() => setPicker(null)}
          choose={(definition) => {
            updateDocument(workspaceID, (current) => ({
              ...current,
              blocks: [...current.blocks, createBlock(definition, workspaceID, current, { x: picker.flowX, y: picker.flowY })]
            }));
            setPicker(null);
          }}
        />
      )}
    </div>
  );
}

export default function App() {
  const [settings, setSettings] = useState<AppSettings>({ appearance: "system", recentProjects: [] });
  const [project, setProject] = useState<ProjectData | null>(null);
  const [activeWorkspaceID, setActiveWorkspaceID] = useState<string | null>(null);
  const [tabs, setTabs] = useState<string[]>([]);
  const [dirty, setDirty] = useState(false);
  const [status, setStatus] = useState("Ready");
  const [promptRequest, setPromptRequest] = useState<PromptRequest | null>(null);
  const [menu, setMenu] = useState<MenuState | null>(null);
  const workspaceClipboard = useRef<WorkspaceClipboard | null>(null);
  const projectRef = useRef(project);
  projectRef.current = project;

  const prompt = useCallback((title: string, message: string, value = "") => new Promise<string | null>((resolve) => {
    setPromptRequest({ title, message, value, resolve });
  }), []);

  const closePrompt = (value: string | null) => {
    promptRequest?.resolve(value);
    setPromptRequest(null);
  };

  const saveSettings = useCallback(async (next: AppSettings) => {
    setSettings(next);
    document.documentElement.dataset.theme = next.appearance;
    await window.builderAPI.saveSettings(next);
  }, []);

  useEffect(() => {
    window.builderAPI.getSettings().then((loaded) => {
      const normalized = {
        appearance: loaded.appearance || "system",
        recentProjects: Array.isArray(loaded.recentProjects) ? loaded.recentProjects : []
      } as AppSettings;
      setSettings(normalized);
      document.documentElement.dataset.theme = normalized.appearance;
    });
  }, []);

  const rememberProject = useCallback((loaded: ProjectData) => {
    setProject(loaded);
    const first = loaded.groups.flatMap((group) => group.workspaces)[0]?.id || null;
    setActiveWorkspaceID(first);
    setTabs(first ? [first] : []);
    setDirty(false);
    setStatus(loaded.parserFailures.length
      ? `Opened with ${loaded.parserFailures.length} unreadable block file(s)`
      : `Opened ${loaded.projectName}`);
    const recentProjects = [loaded.projectPath, ...settings.recentProjects.filter((item) => item !== loaded.projectPath)].slice(0, 12);
    void saveSettings({ ...settings, recentProjects });
  }, [saveSettings, settings]);

  const openPath = useCallback(async (projectPath: string) => {
    try { rememberProject(await window.builderAPI.openProject(projectPath)); }
    catch (error) { setStatus(`Open failed: ${(error as Error).message}`); }
  }, [rememberProject]);

  useEffect(() => window.builderAPI.onSmokeProject((projectPath) => {
    void openPath(projectPath);
  }), [openPath]);

  const newProject = useCallback(async () => {
    const name = await prompt("New Project", "Choose a name for the bot project.", "My Discord Bot");
    if (!name) return;
    const parent = await window.builderAPI.chooseProjectParent();
    if (!parent) return;
    try { rememberProject(await window.builderAPI.createProject(parent, name)); }
    catch (error) { setStatus(`Creation failed: ${(error as Error).message}`); }
  }, [prompt, rememberProject]);

  const openProject = useCallback(async () => {
    const selected = await window.builderAPI.chooseProject();
    if (selected) await openPath(selected);
  }, [openPath]);

  const save = useCallback(async (silent = false) => {
    const current = projectRef.current;
    if (!current) return;
    try {
      const result = await window.builderAPI.saveProject(current);
      setProject((value) => value ? { ...value, groups: result.groups } : value);
      setDirty(false);
      if (!silent) setStatus(`Saved ${current.projectName}`);
    } catch (error) {
      setStatus(`Save failed: ${(error as Error).message}`);
    }
  }, []);

  useEffect(() => {
    if (!dirty) return;
    const timer = window.setTimeout(() => void save(true), 800);
    return () => window.clearTimeout(timer);
  }, [dirty, save, project]);

  const updateDocument = useCallback((workspaceID: string, update: (document: WorkflowDocument) => WorkflowDocument) => {
    setProject((current) => current ? {
      ...current,
      documents: { ...current.documents, [workspaceID]: update(current.documents[workspaceID]) }
    } : current);
    setDirty(true);
  }, []);

  const mutateGroups = useCallback((mutator: (groups: WorkspaceGroup[]) => void) => {
    setProject((current) => {
      if (!current) return current;
      const groups = structuredClone(current.groups);
      mutator(groups);
      const documents = { ...current.documents };
      for (const workspace of groups.flatMap((group) => group.workspaces)) {
        documents[workspace.id] ||= { name: workspace.info.title, blocks: [], connections: [] };
      }
      return { ...current, groups, documents };
    });
    setDirty(true);
  }, []);

  const selectWorkspace = useCallback((id: string) => {
    setActiveWorkspaceID(id);
    setTabs((current) => current.includes(id) ? current : [...current, id]);
  }, []);

  const renameWorkspace = useCallback((workspaceID: string, title: string) => {
    setProject((current) => {
      if (!current) return current;
      const groups = structuredClone(current.groups);
      for (const group of groups) {
        const workspace = group.workspaces.find((item) => item.id === workspaceID);
        if (workspace) workspace.info.title = title;
      }
      const document = current.documents[workspaceID];
      return {
        ...current,
        groups,
        documents: document
          ? { ...current.documents, [workspaceID]: { ...document, name: title } }
          : current.documents
      };
    });
    setDirty(true);
  }, []);

  const closeTab = (id: string) => {
    setTabs((current) => {
      const index = current.indexOf(id);
      const next = current.filter((item) => item !== id);
      if (activeWorkspaceID === id) setActiveWorkspaceID(next[Math.min(index, next.length - 1)] || null);
      return next;
    });
  };

  const deleteWorkspace = async (workspaceID: string) => {
    const workspace = project?.groups.flatMap((group) => group.workspaces).find((item) => item.id === workspaceID);
    if (!workspace) return;
    const confirmation = await prompt("Delete Workspace", `Type DELETE to permanently remove ${workspace.info.title}.`, "");
    if (confirmation !== "DELETE") return;
    mutateGroups((groups) => {
      for (const group of groups) group.workspaces = group.workspaces.filter((item) => item.id !== workspaceID);
    });
    setProject((current) => {
      if (!current) return current;
      const documents = { ...current.documents }; delete documents[workspaceID];
      return { ...current, documents };
    });
    closeTab(workspaceID);
  };

  const duplicateWorkspace = (workspaceID: string) => {
    if (!project) return;
    const source = project.groups.flatMap((group) => group.workspaces).find((item) => item.id === workspaceID);
    const sourceDocument = project.documents[workspaceID];
    if (!source || !sourceDocument) return;
    const copy = structuredClone(source);
    copy.id = makeID();
    copy.info.title = `${copy.info.title} Copy`;
    const documentCopy = clonedWorkspaceDocument(sourceDocument, copy.id, copy.info.title);
    setProject((current) => {
      if (!current) return current;
      const groups = structuredClone(current.groups);
      groups.find((group) => group.workspaces.some((item) => item.id === workspaceID))?.workspaces.push(copy);
      return { ...current, groups, documents: { ...current.documents, [copy.id]: documentCopy } };
    });
    setDirty(true);
    selectWorkspace(copy.id);
  };

  const copyWorkspace = (workspaceID: string) => {
    const workspace = project?.groups.flatMap((group) => group.workspaces).find((item) => item.id === workspaceID);
    const document = project?.documents[workspaceID];
    if (workspace && document) {
      workspaceClipboard.current = {
        workspace: structuredClone(workspace),
        document: structuredClone(document)
      };
    }
  };

  const pasteWorkspace = (groupID: string) => {
    if (!workspaceClipboard.current || !project) return;
    const copy = structuredClone(workspaceClipboard.current.workspace);
    copy.id = makeID();
    copy.info.title = `${copy.info.title} Copy`;
    const documentCopy = clonedWorkspaceDocument(
      workspaceClipboard.current.document,
      copy.id,
      copy.info.title
    );
    setProject((current) => {
      if (!current) return current;
      const groups = structuredClone(current.groups);
      groups.find((group) => group.id === groupID)?.workspaces.push(copy);
      return { ...current, groups, documents: { ...current.documents, [copy.id]: documentCopy } };
    });
    setDirty(true);
    selectWorkspace(copy.id);
  };

  const cycleAppearance = useCallback(() => {
    const order: Appearance[] = ["system", "light", "dark"];
    const appearance = order[(order.indexOf(settings.appearance) + 1) % order.length];
    void saveSettings({ ...settings, appearance });
  }, [saveSettings, settings]);

  const action = useCallback(async (command: string) => {
    if (["copy", "cut", "paste", "delete", "select-all", "undo", "redo"].includes(command)) {
      window.dispatchEvent(new CustomEvent("builder-command", { detail: command }));
      return;
    }
    if (command === "new-project") await newProject();
    if (command === "open-project") await openProject();
    if (command === "save") await save();
    if (command === "appearance") cycleAppearance();
    if (command === "import-workspaces" && project) {
      const file = await window.builderAPI.chooseWorkspaceFile();
      if (file) try { rememberProject(await window.builderAPI.importWorkspaces(project.projectPath, file)); }
      catch (error) { setStatus(`Import failed: ${(error as Error).message}`); }
    }
    if (command === "import-blocks" && project) {
      const folder = await window.builderAPI.chooseBlocksFolder();
      if (folder) try { rememberProject(await window.builderAPI.importBlocks(project.projectPath, folder)); }
      catch (error) { setStatus(`Import failed: ${(error as Error).message}`); }
    }
    if (command === "update-runtime" && project) {
      const answer = await prompt("Update bot.js", "Type UPDATE to replace bot.js. A backup will be created first.", "");
      if (answer === "UPDATE") try {
        const result = await window.builderAPI.updateRuntime(project.projectPath);
        setStatus(result.backupPath ? "Updated bot.js and created a backup" : "Installed the bundled bot.js");
      } catch (error) { setStatus(`Update failed: ${(error as Error).message}`); }
    }
  }, [cycleAppearance, newProject, openProject, project, prompt, rememberProject, save]);

  useEffect(() => window.builderAPI.onMenuCommand((command) => void action(command)), [action]);

  useEffect(() => {
    const keydown = (event: KeyboardEvent) => {
      const editing = event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement;
      if (editing) return;
      if ((event.ctrlKey || event.metaKey) && !event.altKey) {
        const commands: Record<string, string> = {
          c: "copy", x: "cut", v: "paste", a: "select-all"
        };
        const command = commands[event.key.toLowerCase()];
        if (command) {
          event.preventDefault();
          action(command);
          return;
        }
      }
      if ((event.key === "Delete" || event.key === "Backspace") && project) {
        event.preventDefault(); action("delete");
      }
    };
    window.addEventListener("keydown", keydown);
    return () => window.removeEventListener("keydown", keydown);
  }, [action, project]);

  const showMenu = (event: React.MouseEvent, items: MenuState["items"]) => {
    event.preventDefault();
    setMenu({ x: event.clientX, y: event.clientY, items });
  };

  const droppedWorkspace = async (event: DragEvent) => {
    event.preventDefault();
    if (!project) return;
    const file = Array.from(event.dataTransfer.files).find((item) => item.name.toLowerCase().endsWith(".json"));
    if (!file) return;
    try { rememberProject(await window.builderAPI.importWorkspaces(project.projectPath, window.builderAPI.pathForFile(file))); }
    catch (error) { setStatus(`Import failed: ${(error as Error).message}`); }
  };

  return (
    <div className="app" onDragOver={(event) => event.preventDefault()} onDrop={droppedWorkspace}>
      <Toolbar hasProject={Boolean(project)} dirty={dirty} appearance={settings.appearance} action={action} />
      <div className="app-body">
        <ProjectRail settings={settings} project={project} openRecent={openPath} newProject={newProject} openProject={openProject} />
        <WorkspaceSidebar
          project={project}
          activeWorkspaceID={activeWorkspaceID}
          selectWorkspace={selectWorkspace}
          mutateGroups={mutateGroups}
          duplicateWorkspace={duplicateWorkspace}
          deleteWorkspace={deleteWorkspace}
          copyWorkspace={copyWorkspace}
          pasteWorkspace={pasteWorkspace}
          renameWorkspace={renameWorkspace}
          prompt={prompt}
          showMenu={showMenu}
          status={status}
        />
        <main className="editor">
          {project && <TabBar project={project} tabs={tabs} active={activeWorkspaceID} select={selectWorkspace} close={closeTab} />}
          {project && activeWorkspaceID ? (
            <ReactFlowProvider>
              <WorkflowCanvas
                project={project}
                workspaceID={activeWorkspaceID}
                updateDocument={updateDocument}
                replaceProject={(loaded) => { setProject(loaded); setDirty(false); }}
                prompt={prompt}
                showStatus={setStatus}
              />
            </ReactFlowProvider>
          ) : (
            <div className="welcome">
              <PackageOpen />
              <h1>{project ? "No workspace open" : "Open a bot project"}</h1>
              <div>
                <button className="primary" onClick={newProject}>New Project</button>
                <button onClick={openProject}>Open Project</button>
              </div>
            </div>
          )}
        </main>
      </div>
      {promptRequest && <PromptDialog request={promptRequest} close={closePrompt} />}
      {menu && <ContextMenu menu={menu} dismiss={() => setMenu(null)} />}
    </div>
  );
}
