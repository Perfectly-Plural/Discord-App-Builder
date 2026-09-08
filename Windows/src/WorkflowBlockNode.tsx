import { memo, type ChangeEvent } from "react";
import { Handle, NodeResizer, Position, type Node, type NodeProps } from "@xyflow/react";
import { Box, Bolt, Grip, LockKeyhole } from "lucide-react";
import type { BlockOption, BlockPort, WorkflowBlock } from "./types";
import { minimumBlockHeight, resolvedType, valueColors } from "./editor-model";

export interface WorkflowBlockNodeData extends Record<string, unknown> {
  block: WorkflowBlock;
  workspaceID: string;
  connectionCounts: Record<string, number>;
  onOptionChange: (blockID: string, optionID: string, value: unknown) => void;
  onRename: (block: WorkflowBlock) => void;
  onDelete: (blockID: string) => void;
}

export type WorkflowNode = Node<WorkflowBlockNodeData, "workflowBlock">;

function optionEditor(
  block: WorkflowBlock,
  option: BlockOption,
  onChange: (blockID: string, optionID: string, value: unknown) => void
) {
  const value = block.optionValues[option.id];
  const common = {
    id: `${block.id}-${option.id}`,
    className: "nodrag option-control",
    title: option.description,
    onPointerDown: (event: React.PointerEvent) => event.stopPropagation()
  };
  if (option.type === "CHECKBOX") {
    return (
      <label className="toggle-row nodrag">
        <input
          {...common}
          type="checkbox"
          checked={Boolean(value)}
          onChange={(event) => onChange(block.id, option.id, event.target.checked)}
        />
        <span className="toggle-track"><span /></span>
      </label>
    );
  }
  if (option.type === "SELECT") {
    return (
      <select
        {...common}
        value={String(value ?? "")}
        onChange={(event) => onChange(block.id, option.id, event.target.value)}
      >
        {(option.choiceOrder.length ? option.choiceOrder : Object.keys(option.choices)).map((id) => (
          <option value={id} key={id}>{option.choices[id] ?? id}</option>
        ))}
      </select>
    );
  }
  if (option.type === "MULTISELECT") {
    const selected = Array.isArray(value) ? value.map(String) : [];
    return (
      <select
        {...common}
        multiple
        value={selected}
        onChange={(event: ChangeEvent<HTMLSelectElement>) => onChange(
          block.id,
          option.id,
          Array.from(event.target.selectedOptions, (entry) => entry.value)
        )}
      >
        {(option.choiceOrder.length ? option.choiceOrder : Object.keys(option.choices)).map((id) => (
          <option value={id} key={id}>{option.choices[id] ?? id}</option>
        ))}
      </select>
    );
  }
  if (option.type === "COLOR") {
    return (
      <div className="color-option">
        <input
          className="nodrag"
          type="color"
          value={String(value || "#5865f2")}
          onChange={(event) => onChange(block.id, option.id, event.target.value)}
        />
        <input
          {...common}
          value={String(value ?? "")}
          onChange={(event) => onChange(block.id, option.id, event.target.value)}
        />
      </div>
    );
  }
  const numeric = option.type === "NUMBER";
  return option.type === "TEXT" || option.type === "UNKNOWN" ? (
    <textarea
      {...common}
      value={String(value ?? "")}
      onChange={(event) => onChange(block.id, option.id, event.target.value)}
    />
  ) : (
    <input
      {...common}
      type={numeric ? "number" : "text"}
      value={String(value ?? "")}
      onChange={(event) => onChange(
        block.id,
        option.id,
        numeric && event.target.value !== "" ? Number(event.target.value) : event.target.value
      )}
    />
  );
}

function PortRows({
  block,
  ports,
  direction,
  counts
}: {
  block: WorkflowBlock;
  ports: BlockPort[];
  direction: "input" | "output";
  counts: Record<string, number>;
}) {
  return (
    <div className={`port-column ${direction}`}>
      {ports.flatMap((port) => {
        const connected = counts[`${direction}:${port.id}`] || 0;
        const inputValue = block.inputWireValues[port.id];
        const stored = direction === "input" && Array.isArray(inputValue)
          ? inputValue.length : 0;
        const total = port.allowsMultipleConnections ? Math.max(connected, stored) + 1 : 1;
        return Array.from({ length: total }, (_, occurrence) => (
          <div className="port-row" key={`${port.id}:${occurrence}`} title={port.description}>
            {direction === "output" && (
              <span>{port.name}{total > 1 ? ` ${occurrence + 1}` : ""}</span>
            )}
            <Handle
              type={direction === "input" ? "target" : "source"}
              position={direction === "input" ? Position.Left : Position.Right}
              id={`${direction}:${port.id}:${occurrence}`}
              className="connector"
              style={{ background: valueColors[resolvedType(port)] }}
            />
            {direction === "input" && (
              <span>{port.name}{total > 1 ? ` ${occurrence + 1}` : ""}</span>
            )}
          </div>
        ));
      })}
    </div>
  );
}

function WorkflowBlockNodeView({ data, selected }: NodeProps<WorkflowNode>) {
  const { block, workspaceID, connectionCounts, onOptionChange, onRename, onDelete } = data;
  const displayedID = block.runtimeBlockID?.startsWith(`${workspaceID}:`)
    ? block.runtimeBlockID.slice(workspaceID.length + 1)
    : block.runtimeBlockID;
  const hasInputs = block.definition.inputs.length > 0;
  const hasOptions = block.definition.options.length > 0;
  const hasOutputs = block.definition.outputs.length > 0;
  const minHeight = minimumBlockHeight(block, connectionCounts);
  const bodyClasses = [
    "block-body",
    hasInputs && "has-inputs",
    hasOptions && "has-options",
    hasOutputs && "has-outputs"
  ].filter(Boolean).join(" ");

  return (
    <div
      className={`workflow-block ${selected ? "selected" : ""} ${block.isLocked ? "locked" : ""}`}
      style={{ width: block.width, height: block.height }}
      onAuxClick={(event) => {
        if (event.button === 1) {
          event.preventDefault();
          onDelete(block.id);
        }
      }}
    >
      <NodeResizer
        isVisible={selected && !block.isLocked}
        minWidth={220}
        minHeight={minHeight}
        lineClassName="resize-line"
        handleClassName="resize-handle"
      />
      <div
        className={`block-header ${block.definition.autoExecute ? "auto-execute" : ""}`}
        onDoubleClick={() => onRename(block)}
      >
        {block.definition.autoExecute ? <Bolt size={15} /> : <Box size={15} />}
        <strong>{block.definition.name}</strong>
        <span className="block-category">[{block.definition.category}]</span>
        <Grip size={14} className="drag-grip" />
        {block.isLocked && <LockKeyhole size={13} />}
        {displayedID && <code>#{displayedID}</code>}
      </div>
      <div className={bodyClasses}>
        {hasInputs && (
          <PortRows
            block={block}
            ports={block.definition.inputs}
            direction="input"
            counts={connectionCounts}
          />
        )}
        {hasOptions && (
          <div className="option-column">
            {block.definition.options.map((option) => (
              <label className="option-field" key={option.id} htmlFor={`${block.id}-${option.id}`}>
                <span>{option.name}</span>
                {optionEditor(block, option, onOptionChange)}
              </label>
            ))}
          </div>
        )}
        {hasOutputs && (
          <PortRows
            block={block}
            ports={block.definition.outputs}
            direction="output"
            counts={connectionCounts}
          />
        )}
      </div>
    </div>
  );
}

export const WorkflowBlockNode = memo(WorkflowBlockNodeView);
