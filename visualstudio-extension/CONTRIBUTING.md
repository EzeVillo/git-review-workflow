# Contributing to the Visual Studio extension

This covers working *on* the extension. For what it does and how to use it, see the
[README](README.md); for the CLI and the workflow itself, the [project README](../README.md) and
[CONTRIBUTING.md](../CONTRIBUTING.md) at the root.

## The CLI is the only source of truth

Same rule as the VS Code extension and the JetBrains plugin: the extension never derives review
state on its own. Everything it shows comes from re-invoking `git review status --porcelain` /
`--why` / `list --porcelain` and reading the result. If the panel needs something the CLI does not
report, it gets added to the CLI — never computed here.

`GitReview.Domain` is a mechanical port of `jetbrains-plugin/.../domain/`: pure C#, no
`Microsoft.VisualStudio.*` references, and the layer where `panelLayout` projection lives.
`GitReview.Host` invokes the CLI (`shell: false`, UTF-8, timeouts 15s / 120s / 300s) and refreshes
state. `GitReview.VS` is the VSIX itself — WPF `PanelView` renders `PanelLayout` in the same order
and the same English labels as JetBrains and VS Code; only colors follow the host theme. Canonical
contract for all three clients:
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml).

## Developing

```sh
cd visualstudio-extension
dotnet build GitReview.sln
dotnet test GitReview.sln                   # both suites, no Visual Studio
dotnet test tests/GitReview.Domain.Tests    # domain only, while you iterate
dotnet test tests/GitReview.Host.Tests      # the refresh pipeline and the invoker
```

```sh
dotnet run --project src/GitReview.VS -- --verify    # layout + constant smoke, no IDE
dotnet run --project src/GitReview.VS -- --preview    # all situations, arrow keys, no IDE
```

`--preview` is the closest thing this client has to the VS Code extension's `npm run preview`: it
renders every situation the panel can reach, real `PanelLayout` + `PanelRenderer`, without needing
Visual Studio open at all. Good for layout/label review; the buttons have no extension behind them,
same caveat as the other two clients' previews. For behaviour, run it in Visual Studio (below).

### Running it in a real Visual Studio

**F5 is the dev loop — reproducible across rebuilds, which `-Install` below is not.** Open
`GitReview.sln` directly in Visual Studio (not via `dotnet`/CLI), set **GitReview.VS** as the startup
project, and press F5.

That is this client's equivalent of F5 → Extension Development Host in VS Code and `./gradlew
runIde` in JetBrains. Opening the solution in the real IDE sets the MSBuild property
`BuildingInsideVisualStudio=true`, which two things in the csproj key off of:

- it turns on the net472/VSIX side of the build automatically (no `-p:GitReviewPackVsix=true` to
  remember), and
- it turns on `DeployExtension`, which is the VSSDK's own mechanism for writing the build straight
  into the **Experimental Instance** hive (a second registry hive with its own installed extensions,
  so this never touches your day-to-day Visual Studio) and explicitly marking the registration as
  changed. F5 again after editing code and the panel reflects it — no installer, no cache in the
  loop, which is the whole reason this path exists.
- it collapses `TargetFrameworks` from `net8.0-windows;net472` down to net472 alone. With both
  present, F5's target-framework picker can default to net8.0-windows, which has no package wiring
  at all — it just runs `Program.Main`'s banner and exits, a silently wrong build rather than an
  error. Inside a real Visual Studio there is nothing else to pick.

Once it launches:

- **View → Other Windows → git review** opens the tool window (it docks with Solution Explorer).
- **Tools → Options → git review → General** is where *Path to git-review* lives — point it at this
  checkout's `bin/git-review` if you have not installed the CLI, exactly like `gitReview.path` in VS
  Code and *Path to git-review* in JetBrains.
- Open a repository with a review in progress. `../tests/sandbox.sh` builds one:
  `git -C <sandbox>/work review start feature/checkout`, then **File → Open → Folder** on
  `<sandbox>/work`.

### Testing the shipped artifact

```powershell
./build-vsix.ps1 -Install -Experimental   # VSIXInstaller, the same path a user takes
devenv /rootsuffix Exp
./build-vsix.ps1 -Uninstall -Experimental # to remove it again
```

This is a **different thing than F5**, for a different purpose: it validates the actual `.vsix` a
user would download, going through `VSIXInstaller` the same way they would. Drop `-Experimental`
(from both commands) to install into your real Visual Studio.

Visual Studio has to be closed while installing: an in-proc extension cannot be replaced while
devenv has it loaded.

Two things about that install are the script's doing rather than `VSIXInstaller`'s, because on its
own the installer leaves the hive in a state that looks fine and is not:

- **It uninstalls before installing.** An install of a version already present is a silent no-op — it
  exits 0 and touches nothing — and the version is the same on every development build, so without
  this the hive keeps serving the previous assembly. Nothing reports it: the panel simply goes on
  showing the code from whenever the version last changed.
- **It runs `devenv /updateconfiguration` afterwards.** The installer unpacks into a folder name of
  its own choosing, so every reinstall lands somewhere new while the hive's merged configuration
  still points at the folder the previous one used — which the uninstall just deleted. Visual Studio
  then fails to load the package outright: a **"GitReviewPackage did not load correctly"** dialog,
  and a `FileNotFoundException` for the old path in `ActivityLog.xml`.

The script then checks what it cannot assume — that every `GitReview.VS.dll` in the hive is the one
just built — and warns if some other copy is still there. If a reinstall still does not show up,
deleting the hive is the fix that always works:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Microsoft\VisualStudio\<hive>Exp"
```

(find `<hive>` with `Get-ChildItem "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Directory` — the one
ending in `Exp`). It rebuilds itself on the next `devenv /rootsuffix Exp`. For iterating on a change,
F5 is still the shorter loop — it writes straight to the hive and has none of this to go wrong.

`build-vsix.ps1` finds MSBuild through `vswhere` and builds with `-p:GitReviewPackVsix=true`. You can
run that by hand, but it must be **MSBuild from Visual Studio, not `dotnet build`** — the VSSDK
build tasks are .NET Framework tasks and MSBuild for .NET Core cannot load them. No Visual Studio
workload is needed: `Microsoft.VSSDK.BuildTools` and `Microsoft.VisualStudio.Shell.15.0` come from
NuGet.

### Why the extension is net472

`devenv.exe.config` says `supportedRuntime sku=".NETFramework,Version=v4.7.2"` — Visual Studio is a
.NET Framework process, and an extension it loads in-proc has to be too, along with every assembly
that extension pulls in. So `GitReviewPackVsix=true` adds **net472** next to net8.0 in Domain, Host
and GitReview.VS; without the flag all three stay single-target, `dotnet build`, `dotnet test` and
`dotnet run` need no `-f`, and nothing about the default workflow changes.

What .NET Framework's BCL is missing is filled in by three small files, all compiled only for
net472: [`src/Compat/IsExternalInit.cs`](src/Compat/IsExternalInit.cs) (records and `init`),
[`src/Compat/IndexRange.cs`](src/Compat/IndexRange.cs) (so `s[prefix.Length..]` still compiles to
`Substring`) and a `StringCompat`/`DictionaryCompat` per assembly, declared in the namespace that
uses them so no caller needs an extra `using`. Process APIs that only exist on .NET Core —
`ArgumentList`, `WaitForExitAsync`, `Kill(entireProcessTree)` — go through
[`ProcessCompat`](src/GitReview.Host/Compat/ProcessCompat.cs), which is the one file with an `#if`
in it. **Nothing else in the tree should grow an `#if`:** add the shim instead, so the domain keeps
reading the same on both frameworks.

Because net472 is off by default, code that only breaks there will not break `dotnet build`. Run
`./build-vsix.ps1` before pushing a change to Domain, Host or the panel — that is the gate.

### What the package wires up

[`Vsix/`](src/GitReview.VS/Vsix) is the only part that touches `Microsoft.VisualStudio.*`, and it is
excluded from the net8.0 build:

- [`GitReviewPackage.cs`](src/GitReview.VS/Vsix/GitReviewPackage.cs) — the `AsyncPackage`. Its
  attributes are what the build turns into `GitReview.VS.pkgdef`, which registers the package, the
  menu, the tool window and the options page. `GitReviewPackage.vsct` declares the one command.
- [`GitReviewToolWindow.cs`](src/GitReview.VS/Vsix/GitReviewToolWindow.cs) — hosts the same
  `PanelView` the preview renders, driven by the same `GitReviewPanelController`. Git roots are
  resolved on the UI thread and cached, because the panel refreshes from a timer and asking Visual
  Studio for the solution off the UI thread is not allowed.
- [`VsHostActions.cs`](src/GitReview.VS/Vsix/VsHostActions.cs) — the half of the action matrix only
  an IDE can do: open a file, open a diff (`IVsDifferenceService`, left side from `git show
  HEAD:<path>` — in a review HEAD sits at the merge-base, so that *is* the "before"), show the why,
  run the start wizard. Confirmations and staleness stay in the shared `ActionDispatcher`.
- [`VsTheme.cs`](src/GitReview.VS/Vsix/VsTheme.cs) — builds `PanelChrome` from Visual Studio's
  environment colors. Structure and labels stay identical to the other clients; only colors follow
  the host.

## Testing

```sh
dotnet test tests/GitReview.Domain.Tests
dotnet test tests/GitReview.Host.Tests
node ../scripts/check-client-product-surface.mjs   # checks all three client trees at once
```

```powershell
./build-vsix.ps1        # the net472 gate: nothing else compiles that target framework
```

**Two suites, and they cover different halves.** `GitReview.Domain.Tests` is the pure projection:
porcelain in, `PanelModel`/`PanelLayout` out, plus the argv table and the copy. It carries the two
anti-drift gates against
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml) —
`PanelLayoutContractTests` (each situation's controls, their labels and their emphasis) and
`ConfirmationContractTests` (which ids confirm) — and `PanelLayoutInvariantsTests`, which is the
only thing that asks for rules the layout checks on the way in: a violation there is an exception on
the render path, not a red test, unless something constructs the bad shape on purpose.
`GitReview.Host.Tests` is the layer that talks to the CLI: the refresh pipeline against a scripted
invoker (`FakeCliInvoker` — that is why `CliInvoker` is not sealed), and the handful of cases that
need a real process, which spawn git rather than fake it.

**Fixtures live in [`fixtures/`](fixtures/PanelFixtures.cs) and are compiled into both the test
project and `GitReview.VS`** via `Compile Include`, the same way `jetbrains-plugin/fixtures/` is
shared between that client's tests and its preview. They were duplicated once — a private copy in
the test project and another in `PreviewApp.cs` — and the situations only the gallery had
(finish-conflict, out-of-range, error, whole with 300 files) were the ones no test ever asserted on.
Adding a situation means adding it to `All()`, which puts it in the gallery, in `--verify` and
within reach of the contract test at once.

**When the canonical contract says a control is `not_in: [visualstudio]`, assert it by id.** The
enum has no `OpenAllChanges` member, so a label check for the one action this client omits could
never fail; `PanelLayoutContractTests` reads the `not_in` out of the YAML and checks both
directions, and it also rejects any control the situation does not declare — without that last part
the matcher only proved the expected controls were present, and an extra button anywhere in the
panel went unnoticed.

CI runs those same commands on `windows-latest` — the `visualstudio-extension` job in
[`../.github/workflows/ci.yml`](../.github/workflows/ci.yml). Windows-only, and not for
convenience: the VSIX is built by the MSBuild of a Visual Studio installation, so no other runner
can carry the net472 gate. And because `GitReviewPackVsix` is off by default, that last step is the
only thing between a Compat/VSSDK-only breakage and a release — everything above it compiles net8.0
and never sees it.

There is no dockerized integration suite here yet — unlike the VS Code extension, which drives a
real editor in a Linux container because a `git review` process costs ~50ms on Windows against
~1ms on Linux. Both suites run natively and fast: the domain one never shells out at all, and the
host one only spawns git for the few cases that cannot be faked without testing the fake (UTF-8
capture, the cwd, an executable that is not on PATH). `--verify` (above) is the layout/constant
smoke test that stands in for what a headless IDE integration suite would otherwise cover; it
renders the real WPF panel, so it also holds the button-chrome checks that no unit test can.

## Packaging

Bump the version (stamps `GitReview.VS.csproj`, `source.extension.vsixmanifest`, and
`Directory.Build.props` so they cannot drift) before packaging:

```sh
./bump-version.sh X.Y.Z   # from this directory
# or from the monorepo root: ./visualstudio-extension/bump-version.sh X.Y.Z
# then move Unreleased notes under ## [X.Y.Z] in CHANGELOG.md
```

```powershell
./build-vsix.ps1        # src/GitReview.VS/bin/Release/net472/GitReview.VS.vsix
```

Two things travel inside that package and are therefore user-facing: the
[README](README.md) (rendered as `GettingStartedGuide`) and the [CHANGELOG](CHANGELOG.md)
(`ReleaseNotes`) referenced from `source.extension.vsixmanifest`. The **tagline** — the opening
sentence of the vsixmanifest `Description` — is shared with the VS Code and JetBrains listings and
checked by `node ../scripts/check-client-product-surface.mjs`
(`listing.tagline`); change it in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml) and all
three at once, never in one place.
