# Probar los clientes en Windows

Guía rápida para compilar y abrir cada cliente con el código de este checkout.
Usá **Git Bash** para los bloques `sh` y **PowerShell** para los bloques
`powershell`. Necesitás Go para la TUI, Node.js/npm y VS Code para su extensión,
JDK 21 para JetBrains y Visual Studio con MSBuild para el VSIX.

## Preparar un repositorio de prueba

En **Git Bash**:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
./tests/sandbox.sh -f
. "$HOME/.cache/git-review-sandbox/env.sh"
```

Esto recrea el sandbox (borra las pruebas anteriores), pone la CLI de este
checkout en el `PATH` de esta terminal y te deja dentro del repositorio de prueba.
La carpeta para abrir en los IDEs es:

```text
C:\Users\ezevi_30ey2ks\.cache\git-review-sandbox\work
```

Para entrar directamente con una review activa, ejecutá en esa misma terminal:

```sh
git review start feature/checkout
```

Si querés iniciar desde la interfaz, dejá ese último comando sin ejecutar y usá
**Start a Review** (en VS Code está también en la paleta de comandos).

Para probar solamente la CLI, con esa review activa:

```sh
git review status
git review next
git review prev
```

## VS Code — Git Bash + F5

Con el sandbox ya creado, abrí la carpeta de la extensión en VS Code:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/vscode-extension
npm install
code .
```

1. En **Run and Debug**, elegí **Run Extension** y presioná **F5**. Compila la
   extensión y abre otra ventana, el **Extension Development Host**.
2. En esa nueva ventana, **File → Open Folder**: abrí solamente la carpeta `work`
   del sandbox.
3. En la configuración de usuario de esa ventana, agregá este ajuste para usar
   la CLI del checkout:

   ```json
   "gitReview.path": "C:/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/bin/git-review"
   ```

4. Abrí **git review** desde su icono en la barra lateral. La paleta de comandos
   (`Ctrl+Shift+P`) también ofrece las acciones bajo **git review**.

Después de cambiar TypeScript, detené la depuración y volvé a presionar **F5**
para recompilar. Para recompilar al guardar, podés dejar `npm run watch` en una
terminal de `vscode-extension/` y ejecutar **Developer: Reload Window** en el
Extension Development Host después de cada cambio.

## TUI — Git Bash

Con el sandbox ya creado:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
mkdir -p /tmp/git-review-ui
(cd tui && go build -o /tmp/git-review-ui/git-review-ui.exe ./cmd/git-review-ui)
. "$HOME/.cache/git-review-sandbox/env.sh"
GIT_REVIEW_UI=/tmp/git-review-ui/git-review-ui.exe GIT_REVIEW_UI_WATCH=1 git review ui
```

Se abre la TUI en el sandbox, con vigilancia de cambios activada. Salí con `q`.
Después de cambiar código Go, cerrá la TUI y repetí el bloque para recompilar.

## Visual Studio — PowerShell

Cerrá Visual Studio antes de instalar. Compilá e instalá el VSIX en la instancia
experimental y después abrila:

```powershell
Set-Location 'C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\visualstudio-extension'
.\build-vsix.ps1 -Install -Experimental
& 'C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\devenv.exe' /rootsuffix Exp
```

En esa instancia:

1. **File → Open → Folder**: abrí la carpeta `work` del sandbox.
2. **Tools → Options → git review → General → Path to git-review**: indicá
   `C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\bin\git-review`
   para usar la CLI de este checkout.
3. **View → Other Windows → git review**: abrí el panel y probá el flujo.

Después de cambiar código, cerrá la instancia experimental y repetí el bloque.
Para iterar con depuración, abrí `visualstudio-extension/GitReview.sln` en Visual
Studio, elegí **GitReview.VS** como proyecto de inicio y presioná **F5**.

## JetBrains — Git Bash

Para abrir IntelliJ IDEA con el plugin de este checkout:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/jetbrains-plugin
./gradlew runIde
```

La primera ejecución descarga el IDE y puede tardar. `runIde` compila y carga
el plugin; no hace falta ejecutar `buildPlugin` antes.

En el IDE que se abre:

1. **File → Open**: abrí solamente la carpeta `work` del sandbox.
2. **Settings → Tools → git review → Path to git-review**: indicá
   `C:\Users\ezevi_30ey2ks\Desktop\Proyectos\git-review-workflow\bin\git-review`.
3. **View → Tool Windows → git review**: abrí el panel. El menú
   **Tools → git review** también ofrece las acciones.

Después de cambiar código Kotlin, cerrá ese IDE y volvé a ejecutar `./gradlew runIde`.

Si necesitás el ZIP para instalarlo manualmente en un IDE:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow/jetbrains-plugin
./gradlew buildPlugin
```

El ZIP queda en `jetbrains-plugin/build/distributions/`. Instalalo desde
**Settings → Plugins → ⚙ → Install Plugin from Disk…**.

En **PowerShell**, usá `.\gradlew.bat runIde` o `.\gradlew.bat buildPlugin`
desde la misma carpeta.

## Probar la configuración inicial — Git Bash

El sandbox completo ya tiene la rama base configurada. Para ver la pantalla de
configuración inicial, creá el sandbox mínimo:

```sh
cd /c/Users/ezevi_30ey2ks/Desktop/Proyectos/git-review-workflow
./tests/sandbox-min.sh
. "$HOME/.cache/git-review-sandbox-min/env.sh"
```

En los IDEs, abrí `C:\Users\ezevi_30ey2ks\.cache\git-review-sandbox-min\work`.
Para la TUI, ejecutá desde esa terminal el comando de arranque del apartado TUI
(con el binario ya compilado). No inicies una review antes: probá primero
**Set the base branch**, elegí `develop` y después iniciá `feature/discount`.

Ambos sandboxes se reinician al volver a ejecutar su script. Probá un cliente
por vez sobre cada carpeta para que sus acciones no cambien la sesión de otro.
