# User guide

## Your first workspace

1. Open QingFiles and click a pane to activate it. The active pane has a blue caption and keyboard focus.
2. Click **Root /** in the sidebar to browse the filesystem's top level.
3. Click **Hidden** to show dotfiles such as `.ssh` and `.config`.
4. Open the source folder in one pane and the destination in its paired pane.
5. Select items in the source, verify the destination, then choose **Copy Across** or **Move**.

Each pane's search filters names only within its current folder. It does not recursively search child folders. Double-click folders to enter them and files to open them in their default application. Application and document bundles open through macOS instead of being treated as ordinary folders.

## Remote servers

Click **Connect** or press `⌘⇧K`. See [Remote connections](REMOTE_CONNECTIONS.md) for FTP, FTPS, SFTP, host fingerprints, saved passwords, transfers, and SSH Terminal.

## Storage capacity

The storage bar below the file panes shows the active folder's disk name, used space, total capacity, and available space. It follows the active pane when browsing another disk and refreshes after file operations, manual refresh, returning to the app, and every 30 seconds while the main window is visible.

Capacity comes from macOS volume information. Available space uses the filesystem's reported free capacity. System Settings may account for reclaimable storage differently. If capacity cannot be read, the bar displays an unavailable message.

## Compact pane headers and search

Each pane shows its folder title above a single navigation row. Back, Forward, Parent Folder, and Refresh sit to the left of the path field, with a search button at the right. The active pane's folder title is blue. Positional pane labels remain available as accessibility descriptions.

Click the search button or press `⌘F` to expand and focus the current-folder name filter. Wide panes show the path and search together. In narrow panes, search temporarily occupies the path area. Moving focus elsewhere keeps the filter visible. The search field's clear button restores the full list and keeps search expanded. Escape or the Close Search button clears and collapses it. Changing folders also clears and collapses search. `⌘L` clears and collapses search before focusing the path field, avoiding a hidden active filter while editing a path.

## Create a blank document

Right-click in a local pane and choose **New**, then Folder, Word Document (`.docx`), Excel Workbook (`.xlsx`), PowerPoint Presentation (`.pptx`), PDF Document (`.pdf`), Text Document (`.txt`), or Markdown Document (`.md`). The item is created in that pane's displayed folder, including when you right-click an existing item. Existing names receive a numbered suffix such as `New Word Document (2).docx`.

The new item is selected and scrolled into view. Its name enters inline editing when the originating pane is still active. Type a name and press Return, or click elsewhere to commit. File extensions are preserved automatically. Escape keeps the created item with its original default name. Invalid or conflicting names show an error and let you retry. The app does not open the document automatically. An active name filter in the originating pane is cleared after creation so the item is visible.

Word starts with an empty paragraph, Excel with one empty worksheet, PowerPoint with one blank slide, and PDF with one blank A4 page. Text and Markdown files have no content. Office and PDF resources are bundled with the app, so creation works offline and does not require Office. Editing or viewing them requires a compatible application. Custom templates and creation on FTP/SFTP servers are outside this feature's scope.

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
