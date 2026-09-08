export type Appearance = "system" | "light" | "dark";
export type PortDirection = "input" | "output";
export type ValueType =
  | "unspecified" | "undefined" | "null" | "object" | "boolean"
  | "number" | "text" | "list" | "date" | "action";

export interface BlockPort {
  id: string;
  name: string;
  description: string;
  types: ValueType[];
  required: boolean;
  direction: PortDirection;
  allowsMultipleConnections: boolean;
}

export interface BlockOption {
  id: string;
  name: string;
  description: string;
  type: "SELECT" | "TEXT" | "COLOR" | "NUMBER" | "CHECKBOX" | "MULTISELECT" | "UNKNOWN";
  choices: Record<string, string>;
  choiceOrder: string[];
  defaultValue: unknown;
}

export interface BlockDefinition {
  id: string;
  name: string;
  description: string;
  category: string;
  autoExecute: boolean;
  inputs: BlockPort[];
  options: BlockOption[];
  outputs: BlockPort[];
  sourceFile: string;
  usesDynamicMetadata: boolean;
}

export interface WorkflowBlock {
  id: string;
  runtimeBlockID: string;
  definition: BlockDefinition;
  position: { x: number; y: number };
  optionValues: Record<string, unknown>;
  inputWireValues: Record<string, unknown>;
  blockFileName: string;
  color: string;
  zIndex: number;
  width: number;
  height: number;
  isLocked: boolean;
  isActive: boolean;
}

export interface WorkflowConnection {
  id: string;
  wireID: string;
  fromBlockID: string;
  fromPortID: string;
  toBlockID: string;
  toPortID: string;
}

export interface WorkflowDocument {
  name: string;
  blocks: WorkflowBlock[];
  connections: WorkflowConnection[];
}

export interface WorkspaceInfo {
  title: string;
  description: string;
  thumbnail: string;
}

export interface StoredWorkspace {
  id: string;
  active: boolean;
  info: WorkspaceInfo;
  blocks: unknown[];
  notes: unknown[];
}

export interface WorkspaceGroup {
  id: string;
  info: { title: string; collapsed: boolean };
  workspaces: StoredWorkspace[];
}

export interface ProjectData {
  projectPath: string;
  projectName: string;
  groups: WorkspaceGroup[];
  documents: Record<string, WorkflowDocument>;
  library: BlockDefinition[];
  parserFailures: Array<{ file: string; message: string }>;
}

export interface AppSettings {
  appearance: Appearance;
  recentProjects: string[];
}

export interface BuilderAPI {
  chooseProjectParent(): Promise<string | null>;
  chooseProject(): Promise<string | null>;
  chooseWorkspaceFile(): Promise<string | null>;
  chooseBlocksFolder(): Promise<string | null>;
  createProject(parent: string, name: string): Promise<ProjectData>;
  openProject(projectPath: string): Promise<ProjectData>;
  saveProject(payload: ProjectData): Promise<{ groups: WorkspaceGroup[] }>;
  importWorkspaces(projectPath: string, filePath: string): Promise<ProjectData>;
  importBlocks(projectPath: string, folderPath: string): Promise<ProjectData>;
  renameBlockFile(payload: {
    projectPath: string;
    oldName: string;
    newName: string;
    groups: WorkspaceGroup[];
    documents: Record<string, WorkflowDocument>;
  }): Promise<ProjectData>;
  configuredBlock(
    projectPath: string,
    sourceFile: string,
    optionValues: Record<string, unknown>
  ): Promise<BlockDefinition>;
  updateRuntime(projectPath: string): Promise<{ backupPath: string | null }>;
  revealProject(projectPath: string): Promise<void>;
  getSettings(): Promise<AppSettings>;
  saveSettings(settings: AppSettings): Promise<AppSettings>;
  pathForFile(file: File): string;
  onMenuCommand(callback: (command: string) => void): () => void;
  onSmokeProject(callback: (projectPath: string) => void): () => void;
}

declare global {
  interface Window {
    builderAPI: BuilderAPI;
  }
}
