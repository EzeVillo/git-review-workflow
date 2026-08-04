const esbuild = require("esbuild");
const fs = require("fs");
const path = require("path");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

// El askpass no-op (T008/T008a) es un script standalone que git/ssh invocan
// como proceso propio, no algo que importe código de la extensión: no pasa
// por el bundler, sólo se copia tal cual al lado de extension.js — `dist/` es
// lo único que empaqueta `vsce package` y a lo que `__dirname` resuelve en
// runtime una vez bundleado.
function copyStaticAssets() {
    fs.mkdirSync("dist", {recursive: true});
    fs.copyFileSync(
        path.join(__dirname, "scripts", "askpass-noop.js"),
        path.join(__dirname, "dist", "askpass-noop.js")
    );
}

async function main() {
    const ctx = await esbuild.context({
        entryPoints: ["src/extension.ts"],
        bundle: true,
        format: "cjs",
        minify: production,
        sourcemap: !production,
        sourcesContent: false,
        platform: "node",
        outfile: "dist/extension.js",
        external: ["vscode"],
        logLevel: "warning",
    });
    if (watch) {
        await ctx.watch();
        copyStaticAssets();
    } else {
        await ctx.rebuild();
        copyStaticAssets();
        await ctx.dispose();
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
