import * as path from "node:path";
import * as vscode from "vscode";

/**
 * A qué repositorio corresponde el panel (data-model.md § RepositoryTarget).
 * Único dato que la extensión toma de la API de `vscode.git`, junto con la
 * señal de cambio (research.md Decisión 7) — ningún campo de ReviewState,
 * SequenceEntry o UncoveredFile se alimenta de acá (SC-005).
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
 * Enumera los repositorios del workspace vía la extensión git incorporada.
 * Si esa extensión está deshabilitada o no cargó todavía, devuelve `[]` — el
 * llamador cae al fallback de FileSystemWatcher (research.md Decisión 7).
 */
export function getGitApi(): GitApi | undefined {
	const ext = vscode.extensions.getExtension<GitExtensionExports>("vscode.git");
	if (!ext) {
		return undefined;
	}
	const exports = ext.isActive ? ext.exports : undefined;
	return exports?.getAPI(1);
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
