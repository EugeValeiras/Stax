# StaxBridge — el plugin de Vencord

Deja que **⌃⌥S** de Stax cambie la ventana que estás transmitiendo en Discord, sin abrir el selector y
sin cortar el Go Live. Es la otra mitad del puente: el lado de Stax ya viene en la app.

Con esto, compartir en Discord deja de pasar por la ventana espejo: Discord captura la ventana original
directo con ScreenCaptureKit, a resolución nativa y con un solo encode.

## Cómo funciona

```
⌃⌥S en Stax ──► ~/.config/stax/bridge.sock ──► native.ts (proceso principal de Discord)
                                                    │
                                                    ▼
                                             index.tsx (renderer)
                                             setGoLiveSource(nueva fuente)
```

Stax abre el socket y manda `{"cmd":"share","windowId":…}`; el plugin traduce ese CGWindowID al
identificador que usa Discord y cambia la fuente. Si el cambio en caliente no prende, reinicia la
transmisión; si tampoco, le avisa a Stax, que cae a la ventana espejo de siempre.

## Instalación

Los *userplugins* no se pueden instalar desde la UI de Vencord: hay que compilar Vencord con el plugin
adentro. Una sola vez:

```bash
# 1. Dependencias (si no las tenés)
brew install node git
npm install -g pnpm

# 2. Vencord desde fuente
git clone https://github.com/Vendicated/Vencord ~/workspace/Vencord
cd ~/workspace/Vencord
pnpm install --frozen-lockfile

# 3. Copiar el plugin y compilar
~/workspace/macos/Stax/scripts/install-vencord-plugin.sh

# 4. Parchear Discord (cerralo antes)
cd ~/workspace/Vencord && pnpm inject
```

Cada vez que toques el plugin, `scripts/install-vencord-plugin.sh` lo vuelve a copiar y recompila; después,
reiniciá Discord. Se **copia** y no se enlaza con symlink porque esbuild resuelve los archivos por su ruta
real y, desde afuera del árbol de Vencord, no encuentra los alias `@webpack`, `@utils` y compañía.

Después de inyectar: reiniciá Discord, andá a **Ajustes → Vencord → Plugins**, buscá **StaxBridge** y activalo.

> Si preferís Equicord (el fork con más plugins), el procedimiento es igual clonando
> `https://github.com/Equicord/Equicord`.

### Qué le hace exactamente a Discord

`pnpm inject` **sí modifica `/Applications/Discord.app`** (en versiones viejas de Vencord se parcheaba la
carpeta de módulos en Application Support; ya no):

- Renombra `Contents/Resources/app.asar` a `_app.asar` — tu Discord original, intacto, respaldado ahí.
- Escribe un `app.asar` nuevo de 4 KB cuyo contenido es, literalmente,
  `require("<ruta a tu clon>/Vencord/dist/patcher.js")`.

Consecuencias a tener en cuenta:

- **La firma de Discord queda rota** (`codesign -v` falla). Discord arranca igual, pero es un cambio real
  sobre una app firmada por terceros.
- Una actualización de Discord puede pisar el parche: si Vencord desaparece, volvé a correr `pnpm inject`.
- Para revertir todo: `pnpm uninject` (restaura `_app.asar` en su lugar).
- Como es un *dev install*, Vencord no se autoactualiza: los builds salen de tu clon.

## Uso

1. Entrá a un canal de voz en Discord.
2. En Stax, menú ⫼ → **Compartir por** → dejalo en *Automático*.
3. Enfocá la ventana que querés mostrar y tocá **⌃⌥S**.

La primera vez arranca el Go Live; a partir de ahí, cada ⌃⌥S cambia la ventana en vivo. Con
**Seguir la ventana con foco** (⌃⌥⇧S) ni siquiera hace falta el atajo: la transmisión sigue sola a la
ventana que uses.

El menú ⫼ de Stax, en **Compartir por**, muestra si el plugin está conectado y si detecta un canal de voz.

## Ajustes del plugin

| Ajuste | Por defecto | Qué hace |
|---|---|---|
| Cambiar de ventana sin cortar la transmisión | Sí | Usa `setGoLiveSource`. Si falla, reinicia el Go Live igual. |
| Avisar con un toast | No | Muestra qué ventana pasó a transmitirse. |

## Cuando algo no anda

- **El menú de Stax dice "no conectado"**: fijate que Stax esté corriendo (crea el socket al arrancar) y
  que el plugin esté activado. El plugin reintenta solo cada 3 segundos.
- **"no estás en un canal de voz"**: Discord no puede transmitir fuera de un canal de voz; Stax cae al espejo.
- **"Discord no encuentra la ventana"**: suele ser falta del permiso de Grabación de pantalla *de Discord*.
- **Los logs**: los de Stax en `~/Library/Logs/Stax.log` (con `"verbose": true` en la config); los del
  plugin en la consola de Discord (⌥⌘I → Console, filtrando por `StaxBridge`).

## Sobre los mods de cliente

Vencord es un proyecto de la comunidad, sin relación con Discord. Modificar el cliente va contra los
Términos de Servicio de Discord; en la práctica no se conocen baneos por mods de este tipo, pero la
decisión (y la cuenta) son tuyas. Nada acá automatiza tu cuenta ni toca la API de Discord: sólo cambia,
localmente, qué ventana captura tu propia transmisión.
