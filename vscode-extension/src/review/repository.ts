import * as path from "node:path";
import * as vscode from "vscode";

/**
 * A qué repositorio corresponde el panel (data-model.md § RepositoryTarget).
 * Único dato que la extensión toma de la API de `vscode.git`, junto con la
 * señal de cambio (research.md Decisión 7) — ningún campo de ReviewState o
 * SequenceEntry se alimenta de acá (SC-005).
 */
export interface RepositoryTarget {
	rootUri: vscode.Uri;
	label: string;
}

interface GitApiRepositoryState {
	onDidChange: vscode.Event<void>;
}

interface GitApiRepository {
	rootUri: vscode.Uri;
	state: GitApiRepositoryState;
}

export interface GitApi {
	repositories: GitApiRepository[];
	onDidOpenRepository: vscode.Event<GitApiRepository>;
	onDidCloseRepository: vscode.Event<GitApiRepository>;
	/** Construye el Uri `git:` de un archivo en un ref dado; API pública de `vscode.git` (no interna). */
	toGitUri(uri: vscode.Uri, ref: string): vscode.Uri;
}

interface GitExtensionExports {
	getAPI(version: 1): GitApi;
}

function labelFor(rootUri: vscode.Uri): string {
	return path.basename(rootUri.fsPath);
}

/**
 * La API de `vscode.git` **si ya está activa**, sin esperar nada. Es el arranque
 * en frío: sirve para no diferir el primer render cuando la extensión git ya
 * cargó, y devuelve `undefined` cuando todavía no — ver `ensureGitApi`.
 */
export function peekGitApi(): GitApi | undefined {
	const ext = vscode.extensions.getExtension<GitExtensionExports>("vscode.git");
	if (!ext || !ext.isActive) {
		return undefined;
	}
	return ext.exports.getAPI(1);
}

/**
 * La API de `vscode.git`, activando la extensión si hace falta.
 *
 * `vscode.git` se activa con `"*"`, que es **asíncrono**: si esta extensión
 * arranca por `onView` (la vista quedó abierta al reabrir la ventana), git
 * puede no haber terminado de activarse todavía. Sin este `activate()` la API
 * se leía como ausente en ese instante — y como el resultado se capturaba una
 * sola vez, quedaba ausente para toda la sesión aunque git cargara un segundo
 * después. Por eso se resuelve *en el momento de usarla* y nunca se cachea un
 * `undefined`.
 */
export async function ensureGitApi(): Promise<GitApi | undefined> {
	const ext = vscode.extensions.getExtension<GitExtensionExports>("vscode.git");
	if (!ext) {
		return undefined;
	}
	try {
		const exports = ext.isActive ? ext.exports : await ext.activate();
		return exports.getAPI(1);
	} catch {
		return undefined;
	}
}

/**
 * Por qué no hay API de git, para poder decir algo accionable en vez de "no
 * está disponible". `untrusted` primero: en modo restringido VS Code deshabilita
 * `vscode.git` entera (declara `untrustedWorkspaces.supported: false`), así que
 * cualquier otra explicación sería un síntoma de esa causa.
 */
export type GitApiUnavailable = "untrusted" | "missing" | "inactive";

export function gitApiUnavailableReason(): GitApiUnavailable {
	if (!vscode.workspace.isTrusted) {
		return "untrusted";
	}
	if (!vscode.extensions.getExtension("vscode.git")) {
		return "missing";
	}
	return "inactive";
}

export function listRepositoryTargets(gitApi: GitApi | undefined): RepositoryTarget[] {
	if (!gitApi) {
		return [];
	}
	return gitApi.repositories.map((repo) => ({
		rootUri: repo.rootUri,
		label: labelFor(repo.rootUri),
	}));
}

/**
 * Se suscribe a cambios de cualquier repositorio conocido (apertura, cierre,
 * o `state.onDidChange` de cada uno) y llama a `onChange` por cada evento.
 * Usado por extension.ts como señal de refresco (FR-019).
 */
export function watchGitApiChanges(gitApi: GitApi, onChange: () => void): vscode.Disposable {
	const subscriptions: vscode.Disposable[] = [];
	const repoSubscriptions = new Map<GitApiRepository, vscode.Disposable>();

	const subscribeRepo = (repo: GitApiRepository) => {
		repoSubscriptions.set(repo, repo.state.onDidChange(onChange));
	};

	for (const repo of gitApi.repositories) {
		subscribeRepo(repo);
	}

	subscriptions.push(
		gitApi.onDidOpenRepository((repo) => {
			subscribeRepo(repo);
			onChange();
		})
	);
	subscriptions.push(
		gitApi.onDidCloseRepository((repo) => {
			repoSubscriptions.get(repo)?.dispose();
			repoSubscriptions.delete(repo);
			onChange();
		})
	);

	return {
		dispose() {
			for (const sub of subscriptions) {
				sub.dispose();
			}
			for (const sub of repoSubscriptions.values()) {
				sub.dispose();
			}
			repoSubscriptions.clear();
		},
	};
}

/**
 * Fallback cuando la extensión git está deshabilitada: observa `HEAD` y
 * `config` bajo `.git` de cada carpeta del workspace (research.md Decisión 7).
 */
export function watchGitDirFallback(rootUri: vscode.Uri, onChange: () => void): vscode.Disposable {
	const pattern = new vscode.RelativePattern(rootUri, ".git/{HEAD,config}");
	const watcher = vscode.workspace.createFileSystemWatcher(pattern);
	const subscriptions = [
		watcher.onDidChange(onChange),
		watcher.onDidCreate(onChange),
		watcher.onDidDelete(onChange),
	];
	return {
		dispose() {
			for (const sub of subscriptions) {
				sub.dispose();
			}
			watcher.dispose();
		},
	};
}

export function workspaceFolderTargets(): RepositoryTarget[] {
	return (vscode.workspace.workspaceFolders ?? []).map((folder) => ({
		rootUri: folder.uri,
		label: folder.name,
	}));
}
