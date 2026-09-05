# Sincronización del repositorio de IntelliJ después de una mutación

## Objetivo

Después de que una acción de git review termine, IntelliJ debe releer el estado de su `GitRepository` para que la rama visible en la barra del IDE coincida inmediatamente con `HEAD`.

## Causa

`MutationActions` refresca el estado porcelain que alimenta el panel, pero no refresca el modelo Git propio de IntelliJ. La CLI corre como un proceso externo al subsistema Git4Idea; por eso un `checkout` realizado por `finish`, `start`, `continue`, `save`, `abort`, `undo` o `compare` puede quedar reflejado en el panel de git review mientras el widget nativo continúa mostrando la rama anterior.

## Alternativas consideradas

1. Actualizar IntelliJ sólo desde las acciones que hoy cambian de rama. Evita algunas lecturas, pero duplica conocimiento de la CLI en el cliente y no cubre bien los resultados parciales: una acción fallida puede haber movido `HEAD` antes de detenerse por un conflicto.
2. Actualizar el repositorio después de toda mutación completada. Es la opción elegida: usa el mismo punto central que ya hace el refresh porcelain, incluye éxitos y fallos parciales y mantiene el cliente independiente de los detalles internos de cada verbo.
3. Vigilar `.git/HEAD` o hacer polling. Duplica la vigilancia que ya pertenece a Git4Idea, introduce carreras y sigue sin expresar que la propia extensión originó el cambio.

## Diseño

`RepositoryTargets.kt`, que ya encapsula el acceso a `GitRepositoryManager`, expondrá una operación pequeña para actualizar el único repositorio Git seleccionado por el cliente. Esa operación se ejecutará en el hilo de fondo de la mutación; `GitRepository.update()` exige no ejecutarse en el EDT y publica el evento `GIT_REPO_CHANGE` que consume el widget de rama.

Los dos caminos que invocan mutaciones, `runStart` y `runSimple`, llamarán a esa operación inmediatamente después de que el proceso termine y antes de releer el estado del panel. La llamada no dependerá del exit code: un conflicto o fallo parcial también puede haber cambiado refs, índice, rama o estado del repositorio.

No se agrega un refresh recursivo de la VFS ni polling. El alcance es sincronizar el modelo Git del IDE; Git4Idea conserva la responsabilidad sobre sus vistas y listeners.

## Pruebas

El módulo no tiene habilitado el harness de plataforma para instanciar `Project` y `GitRepositoryManager`. Siguiendo el precedente de `VfsAccessTest`, se agregará un gate estructural que compruebe:

- que la única puerta nueva llama a `repository.update()`;
- que los dos sitios de invocación de mutaciones notifican al IDE;
- que la notificación ocurre antes del refresh porcelain posterior.

Después se ejecutarán los tests del plugin y el verificador de contrato del monorepo.

## Otros clientes

VS Code ya escucha `Repository.state.onDidChange` de la extensión Git y usa un watcher de `.git` como fallback, por lo que cuenta con una señal nativa para cambios externos. El cliente de Visual Studio refresca su panel después de mutar, pero no notifica explícitamente al proveedor Git del IDE; puede compartir el síntoma, aunque requiere reproducción y una API host específica antes de cambiarlo. La TUI no tiene un widget de rama externo que sincronizar.
