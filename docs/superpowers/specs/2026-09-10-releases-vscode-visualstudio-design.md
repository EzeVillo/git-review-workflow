# Diseño: releases automatizados de VS Code y Visual Studio

## Objetivo

Publicar cada cliente desde su propio tag, después de construir y verificar el
artefacto que se sube. Los dos clientes usan el secreto de Actions
`VS_MARKETPLACE_TOKEN` y nunca imprimen su valor.

## Alcance

- `vscode-vX.Y.Z` publica la extensión de VS Code y crea su GitHub Release.
- `visualstudio-vX.Y.Z` construye el VSIX de Visual Studio, lo publica y crea
  su GitHub Release.
- Los dos releases son independientes de la CLI, la TUI y JetBrains; por eso
  nunca se marcan como el release "latest" del repositorio.

No se modifica la funcionalidad de los clientes ni se publica un tag existente.

## Workflow de VS Code

El workflow se ejecuta en Ubuntu al recibir un tag `vscode-v*`.

1. Comprueba que el sufijo del tag coincida con la versión de
   `vscode-extension/package.json`.
2. Detiene el trabajo con un mensaje accionable si falta
   `VS_MARKETPLACE_TOKEN`.
3. Instala las dependencias bloqueadas, ejecuta las pruebas del cliente y
   empaqueta con `npm run package`.
4. Publica el VSIX resultante con `vsce`, autenticado únicamente mediante la
   variable de entorno que contiene el secreto.
5. Crea un GitHub Release no-latest con ese mismo VSIX y la sección de versión
   de `vscode-extension/CHANGELOG.md`.

## Workflow de Visual Studio

El workflow se ejecuta en Windows al recibir un tag `visualstudio-v*`.

1. Comprueba que el sufijo del tag coincida con las tres copias de la versión:
   el proyecto VSIX, `source.extension.vsixmanifest` y `Directory.Build.props`.
2. Detiene el trabajo si falta `VS_MARKETPLACE_TOKEN`.
3. Ejecuta las pruebas .NET y `build-vsix.ps1`, que produce el VSIX net472.
4. Publica exactamente ese VSIX mediante `VsixPublisher.exe`, instalado con
   Visual Studio en el runner, y un manifiesto de publicación versionado que
   declara el publisher `EzeVillo`, el overview y la identidad del VSIX.
5. Crea un GitHub Release no-latest con el VSIX y la sección correspondiente de
   `visualstudio-extension/CHANGELOG.md`.

## Seguridad y fallos

El secreto solo se expone a los comandos de publicación mediante variables de
entorno. Las verificaciones de versión y de secreto se ejecutan antes de pasos
costosos. Si falla una prueba, el empaquetado, la publicación o la creación del
release de GitHub, el job falla y no continúa con pasos posteriores.

La primera publicación requiere que el publisher `EzeVillo` ya exista en cada
Marketplace y que el token tenga el permiso Marketplace Manage. El workflow no
crea publishers ni altera sus permisos.

## Verificación

La implementación añade cobertura de regresión para los tags, fuentes de
versión, secreto requerido, artefacto esperado y extracción de notas. También
se validan los YAML y los comandos de prueba existentes para cada cliente.
