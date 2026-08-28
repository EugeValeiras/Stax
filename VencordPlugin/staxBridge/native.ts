/*
 * StaxBridge — parte que corre en el proceso principal de Discord (Node).
 *
 * Se conecta al socket UNIX que abre Stax y hace de cartero entre él y el renderer:
 * el renderer no puede hablar TCP/UNIX, y el proceso principal no puede tocar los módulos de Discord.
 *
 * El renderer consume los mensajes con `next()`, que es un *long poll*: la promesa queda pendiente
 * hasta que llega algo (o hasta el timeout), así el cambio de ventana no espera a ningún intervalo.
 */

import { createConnection, Socket } from "net";
import { homedir } from "os";
import { join } from "path";

import type { IpcMainInvokeEvent } from "electron";

const SOCKET_PATH = join(homedir(), ".config", "stax", "bridge.sock");
const RECONNECT_MS = 3000;
const POLL_TIMEOUT_MS = 30_000;

let socket: Socket | null = null;
let reconnectTimer: NodeJS.Timeout | null = null;
let stopped = false;
let inbox = "";

/** Mensajes que llegaron sin que nadie estuviera esperando. */
const pending: any[] = [];
/** El `next()` que está esperando ahora mismo, si hay alguno. */
let waiter: ((message: any) => void) | null = null;

function deliver(message: any) {
    if (waiter) {
        const resolve = waiter;
        waiter = null;
        resolve(message);
    } else {
        // Si el renderer se quedó sin consumir (recarga de la UI), no acumulamos para siempre.
        if (pending.length > 32) pending.shift();
        pending.push(message);
    }
}

function connect() {
    if (stopped || socket) return;

    const next = createConnection(SOCKET_PATH);
    socket = next;

    next.on("connect", () => {
        inbox = "";
        deliver({ event: "__connected" });
    });

    next.on("data", chunk => {
        inbox += chunk.toString("utf8");
        // NDJSON: un mensaje por línea; lo que queda sin \n espera al próximo chunk.
        let newline: number;
        while ((newline = inbox.indexOf("\n")) !== -1) {
            const line = inbox.slice(0, newline).trim();
            inbox = inbox.slice(newline + 1);
            if (!line) continue;
            try {
                deliver(JSON.parse(line));
            } catch {
                // Una línea rota no debería tirar abajo la conexión.
            }
        }
        if (inbox.length > 64 * 1024) inbox = "";
    });

    const drop = () => {
        if (socket !== next) return;
        socket = null;
        deliver({ event: "__disconnected" });
        scheduleReconnect();
    };

    // Stax no está corriendo todavía: es lo normal al arrancar, no hay nada que reportar.
    next.on("error", drop);
    next.on("close", drop);
}

function scheduleReconnect() {
    if (stopped || reconnectTimer) return;
    reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
    }, RECONNECT_MS);
}

// MARK: - API que ve el renderer

export function start(_: IpcMainInvokeEvent) {
    stopped = false;
    connect();
}

export function stop(_: IpcMainInvokeEvent) {
    stopped = true;
    if (reconnectTimer) clearTimeout(reconnectTimer);
    reconnectTimer = null;
    socket?.destroy();
    socket = null;
    pending.length = 0;
    waiter = null;
}

/** Espera el próximo mensaje de Stax. Devuelve null si en `POLL_TIMEOUT_MS` no llegó nada. */
export function next(_: IpcMainInvokeEvent): Promise<any> {
    if (pending.length) return Promise.resolve(pending.shift());
    return new Promise(resolve => {
        waiter = resolve;
        const timer = setTimeout(() => {
            if (waiter === resolve) {
                waiter = null;
                resolve(null);
            }
        }, POLL_TIMEOUT_MS);
        // Que el timeout no mantenga vivo el proceso al cerrar Discord.
        timer.unref?.();
    });
}

export function send(_: IpcMainInvokeEvent, message: any): boolean {
    if (!socket) return false;
    try {
        socket.write(JSON.stringify(message) + "\n");
        return true;
    } catch {
        return false;
    }
}

export function isConnected(_: IpcMainInvokeEvent): boolean {
    return socket !== null;
}
