# User guide

## Your first workspace

1. Open QingFiles and click a pane to activate it. The active pane has a blue caption and keyboard focus.
2. Click **Root /** in the sidebar to browse the filesystem's top level.
3. Click **Hidden** to show dotfiles such as `.ssh` and `.config`.
4. Click **Two Folders**, then open the source folder in one pane and the destination in its paired pane.
5. Select items in the source, verify the destination, then choose **Copy Across** or **Move**.

Each pane's search filters names only within its current folder. It does not recursively search child folders. Double-click folders to enter them and files to open them in their default application. Application and document bundles open through macOS instead of being treated as ordinary folders.

## Right-pane preview

Select a file in the left pane to preview it on the right. For a folder or archive, choose **Structure** below the selected item’s name to expand its directory tree, or **Media** to list images and videos in its subfolders. The list fills the pane until you select a file. The preview then appears below the list, and images fit the available space proportionally. Press Escape while the preview list has focus to clear the selection and regain the full list. Quick Look determines which media codecs can play. Press Space in the main file list to open a separate system preview.

Archive preview supports ZIP, 7z, RAR, TAR (including gzip, bzip2, xz, and lzip), CAB, CPIO, XAR, ISO, LHA, Unix ar, and single-file gzip, bzip2, xz, LZMA, lzip, and Unix compress streams, subject to the system archive reader. Password-protected entries cannot be opened. The pane shows up to 10,000 entries per selection. For an archive, opening a file previews just that entry in a temporary location, up to 512 MiB.

Click **Two Folders** to browse both folders independently. Click **Preview Pane** to resume following the left selection.

## Drag files between panes

With both folder panes visible, drag one or more selected items onto the destination pane’s file list to move them to that pane’s folder. Drop directly onto a folder row to move into that folder. Hold Option while dropping to copy. QingFiles reports a conflict if the destination already contains an item of the same name.

## Remote servers

Click **Connect** or press `⌘⇧K`. See [Remote connections](REMOTE_CONNECTIONS.md) for FTP, FTPS, SFTP, host fingerprints, saved passwords, transfers, and SSH Terminal.

## Storage capacity

The storage bar below the file panes shows the active folder's disk name, used space, total capacity, and available space. It follows the active pane when browsing another disk and refreshes after file operations, manual refresh, returning to the app, and every 30 seconds while the main window is visible.

Capacity comes from macOS volume information. Available space uses the filesystem's reported free capacity. System Settings may account for reclaimable storage differently. If capacity cannot be read, the bar displays an unavailable message.

## Compact pane headers and search

Each pane shows its folder title above a single navigation row. Back, Forward, Parent Folder, and Refresh sit to the left of the path field, with a search button at the right. The active pane's folder title is blue. Positional pane labels remain available as accessibility descriptions.

Click the search button or press `⌘F` to expand and focus the current-folder name filter. Wide panes show the path and search together. In narrow panes, search temporarily occupies the path area. Moving focus elsewhere keeps the filter visible. The search field's clear button restores the full list and keeps search expanded. Escape or the Close Search button clears and collapses it. Changing folders also clears and collapses search. `⌘L` clears and collapses search before focusing the path field, avoiding a hidden active filter while editing a path.

## Breadcrumb paths and full-path editing

Click a directory name in the path bar to navigate directly to it. Click the arrow immediately to its right to list that directory’s direct subfolders and jump to one. The arrow points down while its menu is open below the path bar. The menu follows the pane’s hidden-item setting. Home appears as `~` and the filesystem root as `/`. When the path is too long, a `…` menu lists omitted ancestor folders. Hover over a segment to highlight it and see the full path in a tooltip.

Click empty space in the shaded path bar or press `⌘L` to edit the full absolute path with all text selected. The pointer becomes a text cursor over the editing area. Copy it with `⌘C`, paste another path, or click again to position the cursor for a partial edit. Return navigates, accepting absolute paths, `~`, and paths relative to the current folder. The original spelling of symbolic-link paths is preserved. Missing paths and file paths keep the editor open and show feedback in the pane footer.

Press Escape, click outside the field (including blank space), or switch away from the browser window to discard unsubmitted path input and restore breadcrumbs. Press Return to navigate to the entered path. Each pane retains its own location and history. Opening path editing clears and collapses search, while opening search ends path editing.

## Reveal files from another app

In Finder or a compatible app, choose **Open With → QingFiles** on a PDF, Word, Excel, PowerPoint, text, image, or archive file (such as ZIP). QingFiles opens or activates its main window, navigates the active pane to the containing folder, and selects and scrolls to the original file. Search in that pane is cleared so the file can be seen. Use the existing copy, Quick Look, and open actions after revealing it.

For a folder, use **Services → Reveal in QingFiles** in the Finder context menu to browse its contents in the active pane. The service appears as **在 QingFiles 中显示** in Simplified Chinese. The same service accepts files and appears in other apps that provide selected local files to macOS Services. A single ordinary folder opens directly; document packages and multiple selected items are revealed in their containing folder.

You can select several files from one folder together. Requests spanning different folders show an error asking you to reveal one folder at a time. An explicitly revealed hidden file remains visible in that pane until you navigate away, while the Hidden setting continues to control other hidden items. Missing or inaccessible files produce an error. Finish an active naming operation or close a dialog before retrying a reveal request.

QingFiles registers as an alternate application for documents, archive files, and folders. Archive requests reveal and select the original file without extracting it or changing its default application. Finder offers Services for folders even when its context menu omits Open With. Menu availability in third-party apps such as WeChat depends on the app and should be checked with a downloaded local attachment. An independent Reveal in QingFiles item in an app’s own context menu requires integration by that app. The system’s **Show in Finder** action invokes Finder.

For WeChat on macOS, install QingFiles in `/Applications`, then use **Open With → Other Apps → QingFiles** on the downloaded attachment. In local acceptance testing, the app appeared in this menu after installation in `/Applications`; the development-directory copy was absent. Choosing it revealed and selected the attachment in QingFiles.

### WeChat Show in Finder setting

Open **QingFiles → Settings…** or press **Command-comma**, then enable **Use QingFiles for Show in Finder in WeChat**. Fully quit and reopen WeChat. Its existing **Show in Finder** command then requests QingFiles to reveal the attachment. The menu label remains controlled by WeChat.

This setting starts off when WeChat has no QingFiles viewer preference. It persists across normal launches and changes WeChat's own viewer preference. Turning it off restores the value saved before enabling it, or removes the override if none existed. Fully quit and reopen WeChat after turning it off too. If another tool changes the preference while the feature is enabled, QingFiles preserves that newer value when disabling it. The Settings window reports access or write failures so you can retry.

## Create a blank document

Right-click in a local pane and choose **New**, then Folder, Word Document (`.docx`), Excel Workbook (`.xlsx`), PowerPoint Presentation (`.pptx`), PDF Document (`.pdf`), Text Document (`.txt`), or Markdown Document (`.md`). The item is created in that pane's displayed folder, including when you right-click an existing item. Existing names receive a numbered suffix such as `New Word Document (2).docx`.

The new item is selected and scrolled into view. Its name enters inline editing when the originating pane is still active. The full filename stays visible, with only its stem selected, so typing a replacement preserves the extension. Press Return or click elsewhere to commit. Escape keeps the created item with its original default name. Invalid or conflicting names show an error and let you retry. The app does not open the document automatically. An active name filter in the originating pane is cleared after creation so the item is visible.

Single-click an existing item's filename to rename it in the same row. Editing begins after the system double-click interval, allowing double-clicks to keep opening files and folders. Clicking an icon or row whitespace only selects; modifier clicks and dragging keep their usual behavior. Files select the name before the last extension; extensionless files, dotfiles such as `.env`, and folders select their entire name. The extension remains editable if you deliberately select it. Return or clicking outside commits; Escape cancels. Renamed items stay selected after sorting. If a renamed selected item no longer matches the current name filter, that filter is cleared to keep it visible. Rename errors preserve existing items and leave the editor available for retry.

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
