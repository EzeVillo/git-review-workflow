import * as vscode from "vscode";
import {GitReviewTestApi} from "../../../src/extension";

const EXTENSION_ID = "EzeVillo.git-review-workflow";

/**
 * Fuerza la activación de la extensión (perezosa por `onView:...`) y devuelve
 * la API de test que `activate()` expone — la única forma de inspeccionar el
 * `PanelModel` y el `ReviewState`, porque el webview corre en su propio
 * contexto y no hay API para leerlo (ver src/extension.ts § GitReviewTestApi).
 */
export async function getTestApi(): Promise<GitReviewTestApi> {
    const ext = vscode.extensions.getExtension<GitReviewTestApi>(EXTENSION_ID);
    if (!ext) {
        throw new Error(`extension ${EXTENSION_ID} not found in the test host`);
    }
    if (ext.isActive) {
        return ext.exports;
    }
    return ext.activate();
}
