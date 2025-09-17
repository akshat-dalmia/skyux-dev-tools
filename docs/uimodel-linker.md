# UIModel Linker Script

Interactive helper to build and link the SKY UX UIModel library to the Infinity SPA (and any additional SPAs).

## Features (Current)

1. Prompts for:
   - UIModel library path
   - Infinity SPA path
   - (Optional) additional SPA paths (comma or semicolon separated)
2. Builds the workspace + the `uimodel` library + schematics.
3. Runs `npm link` on the built `dist\uimodel` output.
4. Links the library package into Infinity and each additional SPA (`npm link <package>`).
5. Starts a library watch build (`npx ng build uimodel --watch`) in a separate PowerShell window.
6. Saves paths to a config file (asks only the first run or when values change).

## How It Works

Flow (per run):

1. Load existing config (if present) from `%APPDATA%\SkyUXDev\uimodel-link-config.json`.
2. Prompt for any missing paths (unless future flags are added to skip prompting).
3. If first run → ask to save.  
   If subsequent run and paths unchanged → no prompt.  
   If paths changed → prompt to update.
4. Build & link (unless you later introduce skip flags).
5. Spawn a new PowerShell window running the watch process.

## Config Storage

**Location:**

```
%APPDATA%\SkyUXDev\uimodel-link-config.json
```

**Stored fields:**

```
LibraryPath, InfinityPath, AdditionalSpaPaths, PackageName, Updated
```

**Reset by deleting the file:**

```powershell
Remove-Item "$env:APPDATA\SkyUXDev\uimodel-link-config.json" -ErrorAction SilentlyContinue
```

## Usage

First run (interactive):

```powershell
powershell -File .\uimodel-linker.ps1
```

Subsequent run (paths reused silently):

```powershell
powershell -File .\uimodel-linker.ps1
```

After changing a path (e.g., moved repo):

- Script detects difference and asks to update the saved config.

## Example Session

1. Run script.
2. Enter:
   - Library path: `C:\Projects\SkyUX\skyux-lib-uimodel`
   - Infinity path: `C:\Projects\SkyUX\skyux-spa-infinity`
   - Additional SPAs: `C:\Projects\SkyUX\skyux-spa-uim-constituent;C:\Projects\SkyUX\skyux-spa-uim-fundraising`
3. Confirm saving.
4. Build + link executes.
5. A new PowerShell window opens running `npx ng build uimodel --watch`.

## Parameters / Flags

These are the flags supported in the current version :

| Flag                            | Purpose                                              |
| ------------------------------- | ---------------------------------------------------- |
| `-LibraryPath <path>`           | Provide library path explicitly                      |
| `-InfinityPath <path>`          | Provide Infinity SPA path                            |
| `-AdditionalSpaPaths "<p1;p2>"` | Additional SPAs (comma or semicolon separated)       |
| `-SavePaths`                    | Force overwrite saved config without prompt          |
| `-NoSave`                       | Do not write config (even if changed)                |
| `-NoBuild`                      | Skip build steps (assumes dist ready)                |
| `-NoLink`                       | Skip linking (just watch)                            |
| `-NoWatch`                      | Skip watch (build/link only)                         |
| `-SkipMissing`                  | Ignore missing additional SPA paths                  |
| `-DebugPaths`                   | Print diagnostic path info                           |
| `-NoPrompt`                     | Non-interactive (requires prior config or all paths) |

## Troubleshooting

| Problem                       | Cause                            | Fix                                                          |
| ----------------------------- | -------------------------------- | ------------------------------------------------------------ |
| Prompts again unexpectedly    | Path text changed (even spacing) | Re-confirm or delete config and re-enter clean paths         |
| `Library not found` error     | Wrong or malformed path          | Re-run and enter a clean absolute path                       |
| Watch window closes instantly | Build error in Angular project   | Manually run `npx ng build uimodel` to see error             |
| Linking fails (`ENOENT`)      | Library not built yet            | Ensure build ran (avoid using future `-NoBuild` prematurely) |

## Planned Enhancements

- Shared common helper module
- Logging & status summary
