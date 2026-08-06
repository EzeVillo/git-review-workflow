/** Comandos npm que el panel muestra y el host copia (allowlist por `kind`). */
export const NPM_INSTALL_CMD = "npm install -g git-review-workflow";
export const NPM_UPDATE_CMD = "npm install -g git-review-workflow@latest";

export type CliInstallKind = "install" | "update";

export function npmCommandFor(kind: CliInstallKind): string {
    return kind === "update" ? NPM_UPDATE_CMD : NPM_INSTALL_CMD;
}
