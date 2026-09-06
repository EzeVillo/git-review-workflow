// Original instrumental score. All instruments are synthesized here: no samples,
// recordings, third-party melodies, or network services are used.
import fs from 'node:fs';

export function renderMusic(file) {
    const rate = 48000, duration = 40, count = rate * duration;
    const left = new Float32Array(count), right = new Float32Array(count);
    const wetL = new Float32Array(count), wetR = new Float32Array(count);
    const tau = Math.PI * 2;
    let seed = 823714;
    const noise = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 2147483648 - 1; };
    const hz = midi => 440 * 2 ** ((midi - 69) / 12);
    const clamp = (x, low, high) => Math.min(high, Math.max(low, x));
    function voice(start, length, gain, pan, send, sample) {
        const offset = Math.round(start * rate), n = Math.round(length * rate);
        const l = Math.sqrt((1 - pan) / 2), r = Math.sqrt((1 + pan) / 2);
        for (let i = 0; i < n && offset + i < count; i++) {
            const x = sample(i / rate, i) * gain;
            left[offset + i] += x * l; right[offset + i] += x * r;
            wetL[offset + i] += x * l * send; wetR[offset + i] += x * r * send;
        }
    }
    // Dmaj9 – Bm7 – Gmaj9 – Aadd9. Two bars per harmony, 120 BPM.
    const chords = [[50, 57, 61, 66, 69], [47, 54, 57, 62, 66], [43, 54, 57, 62, 66], [45, 52, 59, 61, 64]];
    for (let section = 0; section < 10; section++) {
        const start = section * 4;
        const chord = section >= 9 ? chords[0] : chords[section % 4];
        chord.slice(1).forEach((note, j) => {
            const f = hz(note);
            voice(start, 4, .075, (j - 1.5) * .35, .42, t => {
                const env = Math.min(1, t / .25) * Math.min(1, (4 - t) / .8);
                return env * (Math.sin(tau * f * t) + .24 * Math.sin(tau * f * 2.003 * t)) * (.85 + .15 * Math.sin(tau * .3 * t));
            });
        });
        // Syncopated bass: space around the kick keeps the mix light.
        if (section > 0 && section < 9) {
            for (const beat of [0, .75, 1.5, 2, 2.75, 3.5]) {
                const f = hz(chord[0] - 12);
                voice(start + beat, .43, .24, 0, .02, t => {
                    const env = Math.min(1, t / .012) * Math.exp(-t * 7) * Math.min(1, (.43 - t) / .06);
                    return env * (Math.sin(tau * f * t) + .25 * Math.sin(tau * 2 * f * t) + .1 * Math.sin(tau * 3 * f * t));
                });
            }
        }
        // Bell-like eighth-note pulse, alternating stereo positions.
        const pattern = [0, 2, 1, 3, 2, 1, 3, 1];
        for (let step = 0; step < 16 && start + step * .25 < 37; step++) {
            if (section === 0 && step % 2) continue;
            const f = hz(chord[pattern[step % 8] + 1] + 12);
            voice(start + step * .25, .8, section === 0 ? .095 : .07, step % 2 ? .38 : -.38, .5, t => {
                const env = Math.min(1, t / .006) * Math.exp(-t * 9);
                return env * (Math.sin(tau * f * t + .6 * Math.sin(tau * 2 * f * t) * Math.exp(-t * 15)) + .14 * Math.sin(tau * 3 * f * t));
            });
        }
    }
    // A short original motif enters after the intro, with space for the captions.
    const motif = [[0, 78, .38], [.75, 76, .35], [1.5, 73, .7], [2.75, 69, .35], [3.5, 73, .7]];
    for (const start of [8, 16, 24, 28]) {
        for (const [beat, note, length] of motif) {
            const f = hz(note + (start === 28 ? -2 : 0));
            voice(start + beat, length + .3, .095, -.13, .65, t => {
                const env = Math.min(1, t / .024) * Math.exp(-t * 3.7) * clamp((length + .3 - t) / .2, 0, 1);
                return env * (Math.sin(tau * f * t) + .18 * Math.sin(tau * 2 * f * t) + .06 * Math.sin(tau * 3 * f * t));
            });
        }
    }
    // Kick, soft clap and hats. The final card drops the drums for a resolution.
    for (let beat = 8; beat < 68; beat++) {
        const start = beat * .5;
        voice(start, .32, .43, 0, 0, t => {
            const phase = tau * (48 * t + (110 - 48) * .035 * (1 - Math.exp(-t / .035)));
            return Math.sin(phase) * Math.exp(-t * 15) * Math.min(1, t / .002);
        });
        if (beat % 2) {
            let previous = 0;
            voice(start, .16, .12, .07, .2, t => {
                const n = noise(), hp = n - previous * .8; previous = n;
                return hp * (Math.exp(-t * 40) + (t > .012 ? .55 * Math.exp(-(t - .012) * 55) : 0)) * Math.min(1, t / .002);
            });
        }
        for (const [offset, gain] of [[0, .028], [.25, .046]]) {
            let previous = 0;
            voice(start + offset, .085, gain, offset ? .45 : -.3, .08, t => {
                const n = noise(), hp = n - previous; previous = n;
                return hp * Math.exp(-t * 70) * Math.min(1, t / .001);
            });
        }
    }
    // Airy transition accents align with the picture edits, never overpower them.
    for (const end of [5, 11, 17, 22, 27, 34]) {
        let smooth = 0;
        voice(end - .5, .65, .07, .1, .6, t => {
            smooth = smooth * .92 + noise() * .08;
            const env = t < .5 ? (t / .5) ** 2 : Math.exp(-(t - .5) * 25);
            return smooth * env;
        });
    }
    // A warm D major resolution lands with the final brand card.
    [62, 66, 69, 73, 78].forEach((note, j) => {
        const f = hz(note);
        voice(34 + j * .025, 5.8, .1, (j - 2) * .22, .65, t => Math.min(1, t / .012) * Math.exp(-t * 1.15) * Math.sin(tau * f * t));
    });
    // Stereo echoes / early reflections. No unbounded feedback or hidden assets.
    for (const [seconds, gain, cross] of [[.1875, .24, true], [.375, .17, false], [.563, .12, true], [.751, .08, false], [.113, .1, true], [.071, .08, false]]) {
        const offset = Math.round(seconds * rate);
        for (let i = offset; i < count; i++) {
            left[i] += (cross ? wetR : wetL)[i - offset] * gain;
            right[i] += (cross ? wetL : wetR)[i - offset] * gain;
        }
    }
    let peak = 0;
    for (let i = 0; i < count; i++) {
        const t = i / rate;
        const fade = Math.min(1, t / .1) * clamp((duration - t) / 1.8, 0, 1);
        left[i] *= fade; right[i] *= fade;
        peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
    }
    // Leave headroom for the final loudness normalization in render.mjs.
    const scale = .78 / peak;
    const wav = Buffer.alloc(44 + count * 4);
    wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
    wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(2, 22);
    wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 4, 28); wav.writeUInt16LE(4, 32); wav.writeUInt16LE(16, 34);
    wav.write('data', 36); wav.writeUInt32LE(count * 4, 40);
    for (let i = 0; i < count; i++) {
        wav.writeInt16LE(Math.round(left[i] * scale * 32767), 44 + i * 4);
        wav.writeInt16LE(Math.round(right[i] * scale * 32767), 46 + i * 4);
    }
    fs.writeFileSync(file, wav);
    return file;
}
