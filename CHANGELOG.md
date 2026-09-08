# Release notes

## 0.2.0 — 2026-09-08

Version 0.2.0 focuses on making the editor feel like a dependable desktop tool
and correcting the block-layout issues found while working with larger PAL
projects.

### Project navigation

- Discord App Builder now opens on a dedicated Home screen instead of
  automatically opening a project.
- Recent projects are available from Home and can be reopened with one click.
- Added a Home button above the project list.
- Added **Close Project** to each open project's context menu.
- Removed the misleading unread-style marker beside open projects.

### Workflow editor

- Reworked block spacing and alignment for a cleaner, more consistent layout.
- Blocks now calculate a safe minimum height from their controls and repeatable
  input/output ports, preventing content from extending below the node.
- Text areas expand into available block space without forcing other controls
  outside the node.
- Connection handles now sit 8 px inside the node with 24 px of side spacing,
  while connection paths terminate directly on the handle circles.
- Replaced the prominent line grid with a quieter dotted background.
- Removed the canvas minimap.

### Packaging and maintenance

- Added Linux AppImage and Debian packages for x86-64 and ARM64.
- Added Linux Flatpak bundles for x86-64 and ARM64 using the Freedesktop 25.08
  runtime.
- Added a tag-driven release pipeline that publishes x86-64 and ARM64 DEB,
  RPM, Flatpak, generic Linux ZIP, and Windows ZIP packages.
- Added SHA-256 manifests to tagged releases for package verification.
- Moved generated-project templates to the platform-neutral
  `Shared/project-templates.json` source.
- Removed the retired Swift/macOS implementation and its release workflow.
- Expanded smoke checks for node containment, handle placement, and connection
  endpoints.
