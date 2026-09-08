import { BaseEdge, getBezierPath, type Edge, type EdgeProps } from "@xyflow/react";

export type WorkflowEdgeData = { color: string } & Record<string, unknown>;
export type WorkflowEdgeType = Edge<WorkflowEdgeData, "workflowEdge">;

export function WorkflowEdge({
  id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition,
  data, selected, markerEnd, interactionWidth
}: EdgeProps<WorkflowEdgeType>) {
  const [path] = getBezierPath({
    sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition,
    curvature: 0.35
  });
  return (
    <>
      {selected && (
        <BaseEdge id={`${id}-outline`} path={path} style={{ stroke: "var(--text)", strokeWidth: 7 }} />
      )}
      <BaseEdge
        id={id}
        path={path}
        markerEnd={markerEnd}
        interactionWidth={interactionWidth || 24}
        style={{ stroke: data?.color || "#a4a7ae", strokeWidth: selected ? 4 : 3 }}
      />
    </>
  );
}
