# User guide

## Your first workspace

1. Open QingFiles and click a pane to activate it. The active pane has a teal outline.
2. Click **Root /** in the sidebar to browse the filesystem's top level.
3. Click **Hidden** to show dotfiles such as `.ssh` and `.config`.
4. Open the source folder in one pane and the destination in its paired pane.
5. Select items in the source, verify the destination, then choose **Copy Across** or **Move**.

Each pane's search filters names only within its current folder. It does not recursively search child folders. Double-click folders to enter them and files to open them in their default application. Application and document bundles open through macOS instead of being treated as ordinary folders.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Edit path | `⌘L` |
| Search current folder | `⌘F` |
| Toggle hidden items | `⌘⇧.` |
| Go to Root | `⌘⇧/` |
| Go Home | `⌘⇧H` |
| Parent folder | `⌘↑` |
| Back / Forward | `⌘[` / `⌘]` |
| Quick Look | `Space` or `⌘Y` |
| Copy / Cut / Paste | `⌘C` / `⌘X` / `⌘V` |
| Move pasted files | `⌘⌥V` |
| Copy across | `⌘⌥C` |
| Move across | `⌘⌥M` |
| Copy path | `⌘⇧C` |
| New folder | `⌘⇧N` |
| Rename selected item | `⌘⇧R` |
| Move to Trash | `⌘Delete` |
| Refresh | `⌘R` |
| Favorite current folder | `⌘D` |

Cut prepares items for a later move; it does not remove them immediately. File-changing menu shortcuts are disabled while editing a path/search field where appropriate. Standard text copy, cut, and paste stay in the text editor.

## Favorites and persistence

Click Favorite to save the active folder. Right-click a custom favorite to remove it. Locations, layout, favorites, and hidden-item preference are stored in the application's macOS preferences (`local.qingfiles.app`). Moving the app does not delete those preferences.

## Troubleshooting

### macOS blocks a downloaded build

Published builds are ad-hoc signed and not notarized. If you trust the release, use the normal macOS **Privacy & Security → Open Anyway** flow after attempting to open it. Do not disable Gatekeeper globally. Alternatively, inspect the source and build locally.

### A folder cannot be read

Check the path, then review macOS Files and Folders permissions for QingFiles. Permission requests and system-generated errors may use your macOS language. QingFiles cannot bypass protected system locations.

### External changes do not appear

Press `⌘R`. Reactivating the application also refreshes its panes. There is no continuous filesystem watcher yet.

### An operation only partly succeeded

Read the failure dialog. Successfully transferred items are already at the destination; failed items are listed. Inspect both locations before retrying. Existing names will not be overwritten automatically.

### Restoring or undoing changes

Restore trashed items in Finder. There is no application-level undo for copy, move, rename, or folder creation. For an accidental move, verify both paths before moving the item back.
