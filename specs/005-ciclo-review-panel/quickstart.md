# Quickstart: validar el ciclo completo desde el panel

Cómo comprobar a mano que la feature funciona de punta a punta. Los tests
automáticos cubren lo que puede romperse en silencio; esto cubre lo que sólo se
ve usándolo, más las dos rutas que no tienen cobertura automática posible
(credenciales y demora real).

## Prerrequisitos

```bash
./install.sh
```

La extensión invoca la CLI del `PATH`, así que este checkout tiene que estar
instalado —o hay que apuntar el ajuste `gitReview.path` a `bin/git-review`—.
Ojo con el detalle que ya está documentado en `CLAUDE.md`: el Extension
Development Host hereda el `PATH` del VS Code que lo lanzó, no el del `env.sh`
del sandbox.

```bash
./tests/sandbox.sh
```

Arma el PR de juguete y las ramas de cada estado. Esta feature le agrega dos
ramas nuevas: una con un cierre completo pendiente y otra con un cierre trabado
por conflicto — la segunda es la fixture cara y es la razón de construirla acá una
vez en lugar de rearmarla en cada validación.

```bash
cd vscode-extension && npm install && npm run watch
```

Y F5 en VS Code (configuración *Run Extension*) abriendo `<sandbox>/work`.

---

## 1. La CLI sola, antes de tocar el editor

Todo lo que el panel va a consumir tiene que verse primero acá.

```bash
git -C <sandbox>/work review config --porcelain
```

Se espera: un registro `config` por clave con valor efectivo (`remote` siempre;
`base` si está configurada) y un `candidate` por rama elegible, con su origen.
**Ninguna** fila `review/*`, `review-saved/*` ni `review-fixes/*`.

```bash
git -C <sandbox>/work review config base
git -C <sandbox>/work review config base main
git -C <sandbox>/work review config --unset base
git -C <sandbox>/work review config bese main
```

Se espera: leer, escribir, borrar; y la última tiene que fallar con exit `1`
diciendo que `bese` no es una clave, **sin** haber guardado nada.

En la rama con el cierre trabado:

```bash
git -C <sandbox>/work review status --porcelain
```

Se espera: exit `0`, el registro `state` de siempre, y una línea `finish
conflict 0` (el último campo es si el cierre iba con `--onto-source`). Que el
exit siga siendo `0` es parte de la prueba: convertirlo en error rompería a los
consumidores existentes.

```bash
git -C <sandbox>/work review list --porcelain
```

Se espera: una línea `finish <rama> pending 0` para la review con cierre
completo, y `finish <rama> conflict 0` para la trabada — `list` ve el
repositorio entero, así que reporta las dos aunque estés parado en otro lado.

---

## 2. Iniciar una review desde el estado vacío

Parado en una rama sin review, con el panel mostrando el estado vacío.

1. Acción de iniciar → aparece la lista de ramas, la actual primera, filtrable.
2. Elegir la rama del PR de juguete → aparecen las tres formas de leer, **cada
   una con su descripción**. No hay ítem "walkthrough": es lo que se está
   verificando.
3. Aceptar el automático → confirmación con una frase que dice qué rama, contra
   qué y cómo se va a leer.
4. Confirmar → el panel queda mostrando la primera entrada del walkthrough.

**Contraste obligatorio**, que es lo que prueba SC-003:

```bash
git -C <sandbox>/work review status
```

Tiene que describir exactamente la misma review que si se hubiera corrido
`git review start feature/checkout` a mano.

Repetir con *Commit por commit* y con *Ignorar el walkthrough*.

### Sin base configurada

Borrar la base (`review config --unset base`) y volver a iniciar. Se espera: el
asistente **dice que falta** y deja elegirla de la lista ahí mismo; después de
elegirla, la siguiente review ya no la pide.

### Con el working tree sucio

Tocar un archivo sin commitear y volver a iniciar. Se espera: el diagnóstico de
la CLI tal cual (`you have local changes; commit or stash them first`) y **ninguna
rama de review a medio crear** — verificar con `git branch --list 'review/*'`.

---

## 3. Cerrar, deshacer, destrabar

Con una review abierta y algún archivo editado:

1. Cerrar → el `QuickPick` de dos ítems explica la diferencia entre dejar las
   ediciones en una rama aparte o sobre la rama del PR.
2. Elegir la primera → el editor queda en `review-fixes/<rama>` con las ediciones
   staged, y el panel **no** dice "no hay ninguna review": dice que hay un cierre
   pendiente.
3. Deshacerlo → vuelta a editar la review, con las ediciones intactas.

Repetir con la segunda ubicación.

### Deshacer un cierre sobre el que se trabajó

Después de cerrar, commitear algo en la rama de arreglos y recién ahí deshacer.
Se espera: **falla**, con el mensaje de la CLI, y sólo entonces aparece la
segunda confirmación —distinta de la primera— que menciona qué se descarta. Si
esa segunda confirmación aparece antes de que la CLI rechace, es un bug.

### El cierre trabado

En la rama que el sandbox deja trabada:

- El panel lo dice, y ofrece las dos salidas.
- **La navegación por la secuencia no está disponible.** Es FR-027 y es lo más
  importante de este paso: navegar ahí operaría sobre una review a medio cerrar.
- Resolver los marcadores en el working tree y continuar → el cierre termina como
  si nunca se hubiera trabado.
- **Con `--onto-source`, y recargando la ventana antes de continuar**: las
  ediciones tienen que terminar sobre la rama del PR igual. Es lo que verifica
  que el flag sale del contrato y no de una variable en memoria — si sale de
  memoria, este caso manda las ediciones a una rama de arreglos sin avisar.

---

## 4. Pausar y retomar

Con ediciones sin commitear, pausar. Se espera: vuelta a la rama de origen, la
review listada como pausada con su modo y su posición, y al retomarla —con la
acción que ya existía desde `002`— las ediciones vuelven.

Hacerlo también en modo commit por commit con ediciones en varios pasos: es el
caso donde se pierde trabajo si algo está mal.

---

## 5. Cancelar

Con ediciones sin guardar, cancelar. Se espera: la confirmación **dice que esas
ediciones se pierden**, con esas palabras, antes de que se pierdan. Descartarla no
tiene ningún efecto.

---

## 6. Las dos rutas que los tests no cubren

### Credenciales

Apuntar el remoto a algo que pida autenticación y iniciar una review. Se espera:
**no se cuelga**. Falla con el diagnóstico de git y ofrece *Run in Terminal*, que
manda el comando exacto a una terminal integrada donde sí se puede contestar.

Es la validación que confirma o refuta el riesgo registrado en la Decisión 5: si
el `stderr` de un fallo de autenticación no resulta distinguible de otros fallos
de red, la salida es ofrecer el escape ante cualquier fallo de red.

### Demora

Iniciar una review en un repositorio grande. Se espera: progreso visible, editor
usable, y **ningún** control de la extensión operable mientras corre.

---

## 7. Estado cambiado por fuera

Abrir la confirmación de cerrar y, sin confirmarla, correr `git review abort` en
una terminal. Volver y confirmar. Se espera: **no se invoca nada**, y se informa
que el estado cambió.

---

## 8. Contra una CLI vieja

Apuntar `gitReview.path` a un checkout en `0.3.x`. Se espera: **el panel entero
entra en el estado de CLI desactualizada**, con el aviso y el botón de
actualizar que ya existen — no lee, no navega y no ofrece ninguna acción. Es el
mismo trato que `002` le dio a `0.2.x` al subir el mínimo, y es lo que hace
cierto SC-009 sin necesidad de una segunda forma de decidir qué mostrar.

Lo que **no** hay que ver: un panel que sigue leyendo con las acciones nuevas
escondidas. Si aparece eso, alguien implementó degradación por capacidad, que es
justamente lo que la Decisión 12 descarta.

---

## 9. Tema, teclado y ancho

Recorrer los estados nuevos del panel en los temas claro, oscuro y de alto
contraste, y con navegación sólo por teclado. Los controles nuevos son `<button>`
reales en orden de tab, y ninguna distinción se transmite sólo por color — la
regla de `002/FR-031`, que los estados nuevos heredan.

```bash
cd vscode-extension && npm run preview
```

Muestra los estados del panel lado a lado a ancho de sidebar. Los estados nuevos
se agregan a `preview/fixtures.ts` como salida `--porcelain` de ejemplo, así que
siguen al código en vez de mantenerse aparte.

---

## Antes de dar por terminado

```bash
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh
./tests/run-docker.sh
cd vscode-extension && npm test
```

Y la verificación que no es automática pero es un gate igual: **los dos README**
actualizados en el mismo cambio, con el verbo nuevo y los registros nuevos.
