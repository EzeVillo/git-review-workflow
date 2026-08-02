import * as vscode from "vscode";
import {GitReviewTestApi} from "../../../src/extension";

const EXTENSION_ID = "EzeVillo.git-review-vscode";

/**
 * Fuerza la activación de la extensión (perezosa por `onView:...`) y devuelve
 * la API de test que `activate()` expone — la única forma de inspeccionar el
 * `TreeDataProvider` y el `ReviewState` sin una API pública de lectura de
 * `TreeView` (ver src/extension.ts § GitReviewTestApi).
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
