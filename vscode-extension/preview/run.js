// Compila `preview/build.ts` (que importa el `panelHtml` real) y lo ejecuta.
// Con `--watch`, esbuild reconstruye y regenera el HTML en cada guardado: el
// navegador sólo tiene que recargar.
//
// El generador corre en un proceso aparte y no con `require`: en watch el
// módulo cachearía la primera versión y el preview se congelaría en ella.
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const esbuild = require("esbuild");

const watch = process.argv.includes("--watch");
const outDir = path.join(__dirname, "..", "out", "preview");
const bundle = path.join(outDir, "build.cjs");

function generate() {
    const result = spawnSync(process.execPath, [bundle, outDir], {stdio: "inherit"});
    if (result.status !== 0) {
        // En watch un fixture roto no puede matar el watcher: se arregla y
        // la próxima reconstrucción regenera.
        if (!watch) {
            process.exit(result.status ?? 1);
        }
    }
}

async function main() {
    const ctx = await esbuild.context({
        entryPoints: [path.join(__dirname, "build.ts")],
        bundle: true,
        format: "cjs",
        platform: "node",
        outfile: bundle,
        external: ["vscode"],
        logLevel: "warning",
        plugins: [
            {
                name: "run-generator",
                setup(build) {
                    build.onEnd((result) => {
                        if (result.errors.length === 0) {
                            generate();
                        }
                    });
                },
            },
        ],
    });

    if (watch) {
        await ctx.watch();
    } else {
        await ctx.rebuild();
        await ctx.dispose();
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
