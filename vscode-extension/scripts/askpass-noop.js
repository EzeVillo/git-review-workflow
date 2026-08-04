#!/usr/bin/env node
"use strict";

// Askpass no-op (research.md Decisión 5 de `005`): git/ssh lo invocan
// esperando una respuesta interactiva a un pedido de credenciales. Devolver
// stdout vacío de inmediato hace que git falle rápido con su propio
// diagnóstico de autenticación en vez de colgarse esperando un TTY que no
// existe. Nunca se ejecuta solo (src/cli/invoke.ts lo invoca vía `node`,
// porque Windows no sabe ejecutar un `.js` directo).
process.stdout.write("\n");
