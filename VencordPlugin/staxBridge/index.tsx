/*
 * StaxBridge — parte que corre en el renderer de Discord.
 *
 * Escucha al puente de Stax y, cuando llega una orden, cambia la ventana que Discord está transmitiendo.
 * Si ya hay un Go Live activo intenta cambiar la fuente en caliente (nadie del otro lado ve un corte);
 * si eso no prende, reinicia la transmisión, que siempre funciona.
 */

import { definePluginSettings } from "@api/Settings";
import { Logger } from "@utils/Logger";
import definePlugin, { OptionType, PluginNative } from "@utils/types";
import { findByCodeLazy, findByPropsLazy, findStoreLazy } from "@webpack";
import { ChannelStore, MediaEngineStore, SelectedChannelStore, showToast, Toasts } from "@webpack/common";

const Native = VencordNative.pluginHelpers.StaxBridge as PluginNative<typeof import("./native")>;
const logger = new Logger("StaxBridge");

const startStream = findByCodeLazy('type:"STREAM_START"');
const stopStream = findByCodeLazy('type:"STREAM_STOP"');
const getDesktopSources = findByCodeLazy("desktop sources");
const MediaEngineActions = findByPropsLazy("setGoLiveSource");

const ApplicationStreamingStore = findStoreLazy("ApplicationStreamingStore");
const ApplicationStreamingSettingsStore = findStoreLazy("ApplicationStreamingSettingsStore");

const settings = definePluginSettings({
    switchInPlace: {
        type: OptionType.BOOLEAN,
        description: "Cambiar de ventana sin cortar la transmisión (si falla, reinicia el Go Live)",
        default: true,
    },
    showToasts: {
        type: OptionType.BOOLEAN,
        description: "Avisar con un toast cada vez que cambia la ventana transmitida",
        default: false,
    },
});

/** Lo último que Stax nos pidió transmitir, para poder contárselo de vuelta. */
let shared: { app?: string; title?: string; } | null = null;
/** La clave del stream propio, que hace falta para cortarlo. */
let streamKey: string | null = null;
let running = false;

// MARK: - Estado que le reportamos a Stax

function voiceChannelId(): string | null {
    return SelectedChannelStore.getVoiceChannelId() ?? null;
}

function isStreaming(): boolean {
    try {
        return ApplicationStreamingStore.getCurrentUserActiveStream() != null;
    } catch {
        return streamKey != null;
    }
}

function reportState() {
    const streaming = isStreaming();
    if (!streaming) shared = null;
    Native.send({
        event: "state",
        inVoice: voiceChannelId() != null,
        streaming,
        app: shared?.app ?? null,
        title: shared?.title ?? null,
    });
}

function reportError(message: string, cmd?: string, windowId?: number) {
    logger.warn(message);
    Native.send({ event: "error", message, cmd, windowId });
}

// MARK: - Resolución de la ventana

/**
 * Traduce el CGWindowID que manda Stax al identificador que usa Discord.
 *
 * Discord nombra sus fuentes `<tipo>:<handle>` y en macOS el handle es el CGWindowID, pero en vez de
 * armar el string a mano preguntamos por las fuentes y buscamos la que coincida: así, si algún día
 * Discord cambia el formato, esto sigue andando.
 */
async function resolveSource(windowId: number): Promise<{ id: string; name?: string; } | null> {
    const wanted = String(windowId);
    try {
        const sources = (await getDesktopSources(MediaEngineStore.getMediaEngine(), false, ["window"], null)) ?? [];
        const match = sources.find((source: any) => {
            const id = String(source.id ?? "");
            return id === `window:${wanted}` || id.split(":")[1] === wanted;
        });
        return match ?? null;
    } catch (error) {
        logger.error("no pude listar las ventanas que ve Discord", error);
        return null;
    }
}

function qualityOptions() {
    const state = ApplicationStreamingSettingsStore.getState?.() ?? {};
    return {
        preset: state.preset,
        resolution: state.resolution,
        frameRate: state.fps ?? state.frameRate,
        sound: state.soundshareEnabled ?? true,
    };
}

/** El id de la fuente que Discord dice estar transmitiendo, o null si no se puede averiguar. */
function currentSourceId(): string | null {
    try {
        const source = (MediaEngineStore as any).getGoLiveSource?.();
        return source?.desktopSource?.id ?? source?.desktopDescription?.id ?? null;
    } catch {
        return null;
    }
}

// MARK: - Cambiar de ventana

/**
 * Cambia la fuente sin cortar el stream. Devuelve false si no se pudo — incluso cuando la llamada no
 * tira error, porque puede aceptar el pedido y no hacer nada; por eso después verificamos.
 */
async function switchInPlace(sourceId: string): Promise<boolean> {
    if (!settings.store.switchInPlace) return false;

    const quality = qualityOptions();
    try {
        MediaEngineActions.setGoLiveSource({
            desktopSettings: { sourceId, sound: quality.sound },
            qualityOptions: { preset: quality.preset, resolution: quality.resolution, frameRate: quality.frameRate },
            context: "stream",
        });
    } catch (error) {
        logger.warn("setGoLiveSource falló; reinicio la transmisión", error);
        return false;
    }

    // Si Discord expone la fuente actual, la usamos para confirmar. Si no, confiamos en la llamada.
    const before = currentSourceId();
    if (before === null) return true;
    await new Promise(resolve => setTimeout(resolve, 400));
    const after = currentSourceId();
    if (after === sourceId) return true;
    logger.warn(`la fuente no cambió (sigue en ${after ?? "?"}); reinicio la transmisión`);
    return false;
}

async function restartStream(sourceId: string, sourceName: string): Promise<boolean> {
    const channelId = voiceChannelId();
    if (!channelId) return false;
    const channel = ChannelStore.getChannel(channelId);
    if (!channel) return false;

    if (streamKey) {
        try {
            stopStream(streamKey);
        } catch (error) {
            logger.warn("no pude cortar el stream anterior", error);
        }
    }

    const quality = qualityOptions();
    startStream(channel.guild_id ?? null, channelId, {
        appContext: "APP",
        sourceId,
        sourceName,
        sourceIcon: null,
        sourcePid: null,
        sound: quality.sound,
        previewDisabled: false,
    });
    return true;
}

async function handleShare(command: any) {
    const windowId = Number(command.windowId);
    if (!Number.isFinite(windowId)) return reportError("windowId inválido", "share");

    const label = [command.app, command.title].filter(Boolean).join(" — ") || `Ventana ${windowId}`;

    if (!voiceChannelId()) {
        return reportError("no estás en un canal de voz", "share", windowId);
    }

    const source = await resolveSource(windowId);
    if (!source) {
        return reportError(`Discord no encuentra la ventana #${windowId}`, "share", windowId);
    }
    const sourceId = source.id;
    // El nombre que ve el resto es el que usa Discord para esa ventana; si no lo trae, el nuestro.
    const sourceName = source.name || label;

    const wasStreaming = isStreaming();
    const changed = wasStreaming
        ? (await switchInPlace(sourceId)) || (await restartStream(sourceId, sourceName))
        : await restartStream(sourceId, sourceName);

    if (!changed) {
        return reportError(`no pude transmitir ${label}`, "share", windowId);
    }

    shared = { app: command.app, title: command.title };
    logger.info(`transmitiendo ${label} (${sourceId})`);
    if (settings.store.showToasts) showToast(`Compartiendo ${label}`, Toasts.Type.SUCCESS);
    reportState();
}

function handleStop() {
    if (streamKey) {
        try {
            stopStream(streamKey);
        } catch (error) {
            logger.warn("no pude cortar la transmisión", error);
        }
    }
    shared = null;
    reportState();
}

// MARK: - Bucle principal

async function pump() {
    running = true;
    while (running) {
        let message: any;
        try {
            message = await Native.next();
        } catch (error) {
            logger.error("el puente se rompió", error);
            await new Promise(resolve => setTimeout(resolve, 3000));
            continue;
        }
        if (!running) break;
        if (message == null) continue;   // timeout del long poll: volvemos a esperar

        try {
            switch (message.event ?? message.cmd) {
                case "__connected":
                    logger.info("conectado a Stax");
                    Native.send({ event: "hello", version: 1 });
                    reportState();
                    break;
                case "__disconnected":
                    logger.info("Stax se desconectó; reintento solo");
                    break;
                case "share":
                    await handleShare(message);
                    break;
                case "stop":
                    handleStop();
                    break;
                default:
                    logger.warn("orden desconocida", message);
            }
        } catch (error) {
            logger.error("error procesando una orden de Stax", error);
        }
    }
}

export default definePlugin({
    name: "StaxBridge",
    description: "Deja que Stax (macOS) cambie con un atajo la ventana que estás transmitiendo, sin cortar el Go Live.",
    authors: [{ name: "Eugenio Valeiras", id: 0n }],
    settings,

    start() {
        Native.start();
        pump();
    },

    stop() {
        running = false;
        Native.stop();
    },

    flux: {
        VOICE_STATE_UPDATES: () => reportState(),
        STREAM_CREATE: (data: any) => {
            streamKey = data.streamKey ?? data;
            reportState();
        },
        STREAM_DELETE: () => {
            streamKey = null;
            shared = null;
            reportState();
        },
    },
});
