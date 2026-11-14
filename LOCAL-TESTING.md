# Testing the clients on Windows

Quick guide to build and open each client using the code in this checkout.
Use **Git Bash** for the `sh` blocks and **PowerShell** for the `powershell`
blocks. You need Go for the TUI, Node.js/npm and VS Code for its extension,
JDK 21 for JetBrains, and Visual Studio with MSBuild for the VSIX.

## Set up a test repository

In **Git Bash**:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
./tests/sandbox.sh -f
. "$HOME/.cache/git-review-sandbox/env.sh"
```

This recreates the sandbox (deleting previous test data), adds this checkout's
CLI to this terminal's `PATH`, and leaves you in the test repository. The folder
to open in the IDEs is:

```text
C:\Users\ezevi_30ey2ks\.cache\git-review-sandbox\work
```

To enter directly with an active review, run this in the same terminal:

```sh
git review start feature/checkout
```

To start from the UI, leave that last command unrun and use **Start a Review**
(in VS Code, it is also available from the Command Palette).

To test only the CLI, with that review active:

```sh
git review status
git review next
git review prev
```

## VS Code — Git Bash + F5

With the sandbox created, open the extension folder in VS Code:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/vscode-extension
npm install
code .
```

1. In **Run and Debug**, select **Run Extension** and press **F5**. This builds
   the extension and opens another window, the **Extension Development Host**.
2. In that new window, select **File → Open Folder** and open only the
   sandbox's `work` folder.
3. In that window's user settings, add this setting to use the checkout's CLI:

   ```json
   "gitReview.path": "C:/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/bin/git-review"
   ```

4. Open **git review** from its icon in the Activity Bar. The Command Palette
   (`Ctrl+Shift+P`) also offers the actions under **git review**.

After changing TypeScript, stop debugging and press **F5** again to rebuild.
To rebuild on save, you can leave `npm run watch` running in a terminal in
`vscode-extension/` and run **Developer: Reload Window** in the Extension
Development Host after each change.

## TUI — Git Bash

With the sandbox created:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
mkdir -p /tmp/git-review-ui
(cd tui && go build -o /tmp/git-review-ui/git-review-ui.exe ./cmd/git-review-ui)
. "$HOME/.cache/git-review-sandbox/env.sh"
GIT_REVIEW_UI=/tmp/git-review-ui/git-review-ui.exe GIT_REVIEW_UI_WATCH=1 git review ui
```

The TUI opens in the sandbox with file watching enabled. Quit with `q`.
After changing Go code, close the TUI and repeat the block to rebuild.

## Visual Studio — PowerShell

Close Visual Studio before installing. Build and install the VSIX in the
experimental instance, then open it:

```powershell
Set-Location 'C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\visualstudio-extension'
.\build-vsix.ps1 -Install -Experimental
& 'C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\devenv.exe' /rootsuffix Exp
```

In that instance:

1. Select **File → Open → Folder** and open the sandbox's `work` folder.
2. Under **Tools → Options → git review → General → Path to git-review**, enter
   `C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\bin\git-review`
   to use this checkout's CLI.
3. Open the panel from **View → Other Windows → git review** and try the workflow.

After changing code, close the experimental instance and repeat the block.
To iterate with the debugger, open `visualstudio-extension/GitReview.sln` in
Visual Studio, select **GitReview.VS** as the startup project, and press **F5**.

## JetBrains — Git Bash

To open IntelliJ IDEA with this checkout's plugin:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/jetbrains-plugin
./gradlew runIde
```

The first run downloads the IDE and may take a while. `runIde` builds and loads
the plugin; you do not need to run `buildPlugin` first.

In the IDE that opens:

1. Select **File → Open** and open only the sandbox's `work` folder.
2. Under **Settings → Tools → git review → Path to git-review**, enter
   `C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\bin\git-review`.
3. Open the panel from **View → Tool Windows → git review**. The **Tools → git review**
   menu also offers the actions.

After changing Kotlin code, close that IDE and run `./gradlew runIde` again.

If you need the ZIP to install the plugin manually in an IDE:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/jetbrains-plugin
./gradlew buildPlugin
```

The ZIP is created in `jetbrains-plugin/build/distributions/`. Install it from
**Settings → Plugins → ⚙ → Install Plugin from Disk…**.

In **PowerShell**, run `.\gradlew.bat runIde` or `.\gradlew.bat buildPlugin`
from the same folder.

## Test the initial setup — Git Bash

The full sandbox already has the base branch configured. To see the initial
setup screen, create the minimal sandbox:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
./tests/sandbox-min.sh
. "$HOME/.cache/git-review-sandbox-min/env.sh"
```

In the IDEs, open `C:\Users\ezevi_30ey2ks\.cache\git-review-sandbox-min\work`.
For the TUI, run the startup command from its section in that terminal (with
the binary already built). Do not start a review first: try **Set the base
branch**, choose `develop`, and then start `feature/discount`.

Both sandboxes are reset when you run their scripts again. Test one client at a
time on each folder so its actions do not change another client's session.
