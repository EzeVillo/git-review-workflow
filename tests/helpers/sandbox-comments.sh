#!/usr/bin/env sh
# Real, independent repositories for the full sandbox. Called with a fresh
# destination; never removes an existing directory or writes private fixtures.
set -eu
dest=${1:?fresh destination required}
root=${2:?product checkout required}
[ ! -e "$dest" ] || { printf 'error: comments sandbox already exists: %s\n' "$dest" >&2; exit 1; }
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
PATH=$root/bin:$PATH
export PATH
export GIT_REVIEW_ADVICE=0

configure() {
	git config user.name 'Comments sandbox'
	git config user.email comments-sandbox@example.invalid
	git config commit.gpgsign false
	git config core.autocrlf false
	git config reviewworkflow.base main
	printf '\n.idea/\n*.iml\n.vs/\n.vscode/\n' >>.git/info/exclude
}
review() { git-review "$@"; }
clone() {
	git -c core.autocrlf=false clone --quiet "$dest/origin.git" "$dest/$1"
	cd "$dest/$1"
	configure
}

git init --quiet --initial-branch=main "$dest/author"
cd "$dest/author"
configure
printf 'Base\n' >sample.txt
git add sample.txt
git commit --quiet -m 'Team sandbox base'
git switch --quiet -c feature/discussion
printf 'Original PR\n' >>sample.txt
git commit --quiet -am 'Original discussion PR'
git switch --quiet main
review start --offline --no-walk feature/discussion
review comments add --document shared --text 'Shared: original team question'
review finish
git commit --quiet -m 'Public discussion'
git switch --quiet feature/discussion
git merge --quiet --ff-only review-fixes/feature/discussion
review clean --keep-fixes feature/discussion
git branch -D review-fixes/feature/discussion >/dev/null
git show HEAD:.review/comments.md >"$dest/incoming.md"
git branch feature/renamed
git switch --quiet -c feature/copied main
mkdir .review
cp "$dest/incoming.md" .review/comments.md
printf 'A separate PR with copied prose\n' >another.txt
git add .
git commit --quiet -m 'Different history copies Shared'
git switch --quiet main
git init --quiet --bare --initial-branch=main "$dest/origin.git"
git remote add origin "$dest/origin.git"
git push --quiet origin main feature/discussion feature/copied feature/renamed

# Create a retained Local through the real lifecycle in each gitdir. These
# clones must not share private comments paths, owner metadata or result files.
for room in choice-new choice-continue renamed stale; do
	clone "$room"
	review start --no-walk feature/discussion
	review comments add --document local --text 'Local: private notes from the original PR'
	review finish
	review clean --keep-fixes feature/discussion
	git switch --quiet main
	git branch -D review-fixes/feature/discussion >/dev/null
	case "$room" in
		choice-*) review start --no-walk feature/copied ;;
		renamed) review start --no-walk feature/renamed ;;
		stale)
			review start --no-walk feature/discussion
			review comments add --document shared --text 'Bob: feedback on the old tip'
			printf 'Bob code correction\n' >bob-fix.txt
			;;
	esac
done

# Advance the author only after Bob's review exists, then leave both histories
# available. Bob's next Finish stays on his original tip; integration is Git's.
cd "$dest/author"
review start --no-walk feature/discussion
review comments add --document shared --text 'Alice: feedback published while Bob was reviewing'
printf 'Alice correction\n' >alice-fix.txt
review finish
git commit --quiet -m 'Alice feedback advances the PR'
git push --quiet origin HEAD:refs/heads/feature/discussion

cat >"$dest/LEEME.md" <<'GUIDE'
# Casos de comentarios entre personas

Abrí una sola carpeta de repositorio por ventana del cliente. Los cuatro casos
ya tienen una review activa. Usá la CLI de este checkout (`env.sh` o `env.ps1`
del sandbox principal agrega `bin` al PATH) y el cliente actualizado.

## Elegir una discusión nueva

Abrí `choice-new/`. La rama `feature/copied` trae el Shared del PR original, pero
su historia es distinta y en este clon hay Local privado de aquella review.

1. Agregá un comentario desde el panel. Debe aparecer **Continue a previous review?**.
2. El selector aclara que Shared viene de esta rama en ambos casos. Elegí
   **Start a new review**: las notas Local anteriores quedan separadas.
3. En el formulario elegí **Local (only for you)** y escribí algo reconocible.
4. Shared debe conservar **Shared: original team question**.
5. Local debe contener tu comentario, sin **Local: private notes from the original PR**.
6. Finish debe dejar Shared staged con otra identidad; Undo recupera esa preparación.
7. Cancel después de Undo descarta esta pasada y conserva el Local de la review original.

Son dos elecciones distintas. La primera decide si recuperar notas Local de una
review anterior. Local y Shared conviven siempre; el destino del formulario sólo
decide dónde guardar el comentario nuevo. **Shared (to share with the PR)** lo
agrega al documento compartible, sin publicar ni borrar Local.

## Continuar deliberadamente la anterior

Abrí `choice-continue/`. Repetí Add comment, pero elegí **Continue** junto a la review anterior,
identificada por fecha, counts y asunto. Local debe recuperar las notas privadas
originales y agregar tu comentario. Shared sigue saliendo de la rama actual.
Cancelar el selector no debe crear ni modificar documentos.

## Renombrar sin cambiar la historia

Abrí `renamed/`. La rama `feature/renamed` conserva el tip y la discusión original.
Agregar un comentario no debe pedir elegir contexto y Local ya contiene las notas
privadas originales. El nombre de la rama no basta para separar una discusión.

## Dos personas, una desactualizada

Abrí `stale/`: Bob está revisando el tip viejo y ya agregó prosa y una corrección.
Alice publicó otro comentario y otro archivo mientras tanto. Probá Save/Continue
o agregá más comentarios: Bob debe conservar su snapshot.

En la terminal de `stale/`:

```sh
git fetch origin
git review finish
git commit -m 'Bob feedback'
git merge origin/feature/discussion
```

El merge debe dejar un conflicto en `.review/comments.md`. El panel debe informar
que no puede leer Shared, sin presentar un conteo normal. Resolvé conservando los
dos bloques de feedback y una sola cabecera de documento; no uses el número visible
como identidad, porque ambos pueden tener el mismo. Después:

```sh
git add .review/comments.md
git commit -m 'Resolve Alice and Bob feedback'
git push origin HEAD:feature/discussion
```

Los dos archivos `alice-fix.txt` y `bob-fix.txt` deben sobrevivir. Local no se publica.
Los diffs de comentarios con ubicación conservarían sus OID originales; las
observaciones generales de este caso no ofrecen un diff de archivo.

## Reiniciar

Volvé a ejecutar `tests/sandbox.sh` con la misma carpeta de destino para reconstruir
todos los casos. No copies gitdirs entre carpetas: cada una tiene su propia custodia.
GUIDE
printf 'Comments team cases ready: %s\n' "$dest/LEEME.md"
