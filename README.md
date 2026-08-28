<p align="center">
  <img src="Resources/AppIcon-preview.png" width="128" alt="Stax">
</p>

<h1 align="center">Stax</h1>

<p align="center">
  Cambiá de ventana por tercios en tu monitor ultrawide, como si cada tercio fuera un monitor aparte.
</p>

<p align="center">
  <img src="docs/demo-cycle.gif" width="960" alt="⌘` cicla las ventanas apiladas en el tercio activo">
</p>

Stax es una app de barra de menú para macOS. Divide la pantalla en columnas (por defecto, tres tercios) y
te deja moverte entre las ventanas apiladas en cada columna con atajos de teclado globales. Es la
experiencia de tener tres monitores, en uno solo.

**¿Por qué?** En un ultrawide es natural repartir las ventanas en tercios. Pero cuando en un tercio hay
varias apps una detrás de otra, ⌘⇥ te lleva a cualquier lado y ⌘` sólo cicla las ventanas de la misma
app. Stax hace que el ciclo sea *por tercio*.

## Cómo funciona

- Cada ventana visible del escritorio actual se asigna a la columna donde cae el **centro** de su frame.
- Dentro de cada columna las ventanas forman una pila ordenada de adelante hacia atrás.
- La **columna activa** es la de la ventana que tiene el foco (configurable: también puede ser la que está bajo
  el puntero).

### Ciclar el tercio activo — ⌘` y ⌘⇧`

⌘` trae al frente la ventana del fondo de la pila (`[A,B,C] → [C,A,B]`); ⌘⇧` va al revés. Reemplaza al ⌘`
nativo de macOS, que sólo cicla las ventanas de la misma app. Sólo se sube la ventana objetivo: si una app tiene
ventanas en dos columnas, las otras se quedan donde estaban.

### Saltar de tercio — ⌃⌘← y ⌃⌘→

<img src="docs/demo-focus.gif" width="960" alt="⌃⌘← salta el foco al tercio de la izquierda; ⌘` cicla ahí sin mover el resto">

El foco pasa a la ventana frontal del tercio de al lado, como si cambiaras de monitor. Cada tercio tiene su
propia pila: ciclar uno no toca los otros.

### Acomodar la ventana en un tercio — ⌃⌥D, ⌃⌥F y ⌃⌥G

<img src="docs/demo-move.gif" width="960" alt="⌃⌥G, ⌃⌥D y ⌃⌥F mueven la ventana con foco al tercer, primer y segundo tercio">

Mueve y redimensiona la ventana con foco al primer, segundo o tercer tercio, dentro del área visible (sin barra
de menú ni Dock). Son los mismos atajos que usa Rectangle para los tercios, así que si sólo usabas Rectangle
para eso, Stax lo reemplaza. Si lo dejás abierto con esos atajos, desactivalos ahí para que no se pisen.

### Cambiar la ventana que compartís en una videollamada — ⌃⌥S

<img src="docs/demo-share.gif" width="960" alt="⌃⌥S hace que Stax Share refleje la ventana con foco; con «Seguir la ventana con foco» el espejo cambia solo">

Ninguna app de videollamada deja cambiar desde afuera la ventana que se comparte. Stax lo resuelve con una ventana
propia, **Stax Share**, que refleja en vivo el contenido de la ventana que elijas (con ScreenCaptureKit, así que
funciona aunque la ventana original quede tapada). En Meet, Zoom o Slack compartís *Stax Share* una sola vez y,
desde ahí, cada vez que hacés foco en otra ventana y tocás ⌃⌥S, la videollamada pasa a mostrar esa.

- El espejo aparece del tamaño de la ventana original (acotado a la pantalla) sin robarle el foco, y se acomoda
  solo si la original cambia de tamaño. Podés moverlo o mandarlo a un tercio con ⌃⌥D/F/G como a cualquier ventana.
- Su título es `Stax Share — App: título de la ventana`, para reconocerlo en el selector de la videollamada.
- Si la ventana original se cierra, el espejo queda con un aviso; ⌃⌥S sobre otra lo retoma sin cortar la llamada.
- *Dejar de compartir* en el menú ⫼ (o cerrar el espejo) termina la captura.
- **Modo automático**: con *Seguir la ventana con foco* activado (menú ⫼, ⌃⌥⇧S o `shareFollowsFocus` en la
  config), mientras se esté compartiendo algo cada cambio de ventana con foco — otra app, ⌘`, ⌃⌘←/→ — cambia
  solo el origen. Ignora diálogos y sheets, y la propia ventana Stax Share (podés moverla sin que pase nada).

Necesita el permiso de **Grabación de pantalla** (lo pide la primera vez que usás ⌃⌥S).

#### El espejo, en una pantalla que no existe

Con **Espejo en una pantalla virtual** (menú ⫼, o `shareUsesVirtualDisplay` en la config), Stax registra un
monitor que no está enchufado a nada y pone el espejo ahí, ocupándolo entero. En la videollamada compartís la
*pantalla* «Stax Share» en vez de una ventana:

- El espejo deja de robarte lugar en el ultrawide: vive fuera de tus monitores reales.
- La llamada recibe siempre 1920×1080 (a 2x), sin importar cuán grande sea la ventana original.

La pantalla aparece al empezar a compartir y se da de baja al terminar; macOS reacomoda las ventanas como si
enchufaras y desenchufaras un monitor. Usa la misma API privada de CoreGraphics que DeskPad y BetterDisplay;
si un macOS futuro la saca, la opción se deshabilita sola y el espejo vuelve a ser una ventana común.

#### En Discord, sin ventana espejo — el plugin StaxBridge

Discord es el caso donde se puede hacer mejor: con el plugin [StaxBridge](VencordPlugin/) instalado en Vencord,
⌃⌥S cambia **directamente la fuente del Go Live**, sin espejo y sin abrir el selector. Discord captura la
ventana original con ScreenCaptureKit, a resolución nativa y con un solo encode; los del otro lado no ven ningún
corte al cambiar de ventana.

En el menú ⫼ → **Compartir por** elegís el camino:

| Opción | Qué hace |
|---|---|
| *Automático* (por defecto) | Discord si el plugin está conectado y estás en un canal de voz; si no, el espejo. Si el espejo ya está abierto lo respeta, para no cortar una llamada de Meet en curso. |
| *Ventana espejo* | Siempre el espejo, como antes. |
| *Discord* | Siempre el plugin. |

Si el plugin no puede (no hay canal de voz, Discord no ve la ventana), Stax cae al espejo solo.

La instalación está en [`VencordPlugin/README.md`](VencordPlugin/README.md). Requiere **Vencord**, un mod de
cliente de terceros que parchea `/Applications/Discord.app` (y por lo tanto rompe su firma) y va contra los
Términos de Servicio de Discord; ahí están los detalles y cómo revertirlo.

### Todos los atajos

| Atajo | Acción | Qué hace |
|---|---|---|
| ⌘` | `cycleNext` | Trae al frente la ventana del fondo de la pila de la columna activa |
| ⌘⇧` | `cyclePrev` | Manda la frontal al fondo |
| ⌃⌘← | `focusColumnLeft` | Foco a la ventana frontal de la columna de la izquierda |
| ⌃⌘→ | `focusColumnRight` | Foco a la ventana frontal de la columna de la derecha |
| ⌃⌥D | `moveToColumn` 1 | Mueve la ventana con foco al primer tercio |
| ⌃⌥F | `moveToColumn` 2 | Mueve la ventana con foco al tercio del medio |
| ⌃⌥G | `moveToColumn` 3 | Mueve la ventana con foco al último tercio |
| ⌃⌥S | `shareFocusedWindow` | La ventana con foco pasa a ser la que refleja *Stax Share* |
| ⌃⌥⇧S | `toggleFollowFocus` | Activa/desactiva que *Stax Share* siga sola a la ventana con foco |

## El asistente de configuración

La primera vez que abrís Stax aparece un asistente de cinco pasos que deja todo listo: muestra las mismas
animaciones de este README, el estado en vivo de los dos permisos con un botón para otorgarlos, cómo se
comparte en las videollamadas, y ofrece abrir Stax al iniciar sesión.

En el paso de columnas hay una animación por cada cantidad — `docs/demo-columns-2.gif`, `-3` y `-4` — y al
elegir 2, 3 o 4 la demo cambia con un fundido para que veas cómo queda repartida la pantalla antes de decidir.

La ventana se ajusta de alto a lo que ocupa cada paso, y las filas entran escalonadas desde el lado hacia el
que estés yendo.

Se puede volver a abrir cuando quieras desde el menú ⫼ → **Asistente de configuración…**. Cada cambio se
guarda en el momento, así que cerrarlo por la mitad nunca deja la config a medio hacer.

## El menú

<img src="docs/menu.png" width="262" align="right" alt="Menú de Stax">

Desde el ícono ⫼ de la barra de menú:

- **Estado**: si tiene los permisos de Accesibilidad y Grabación de pantalla y si los atajos están activos, con la
  lista de atajos configurados.
- **Columna 1 / 2 / 3**: la pila de ventanas de cada columna (● la frontal, ○ las de atrás), con ▶ en la
  columna activa. Elegí una ventana del submenú para traerla al frente (con ⌥ apretada, para compartirla), o
  *Mover la ventana con foco acá*.
- **Compartir la ventana con foco** / **Dejar de compartir**: lo mismo que ⌃⌥S, y qué se está compartiendo
  (por el espejo o transmitiendo en Discord).
- **Seguir la ventana con foco**: el modo automático de Stax Share (✓ cuando está activo).
- **Compartir por**: *Automático*, *Ventana espejo* o *Discord*, con el estado del plugin StaxBridge.
- **Espejo en una pantalla virtual**: saca el espejo del escritorio y lo pone en un monitor virtual.
- **Columnas**: 2, 3 o 4 columnas.
- **Columna objetivo**: *Ventana con foco* (por defecto) o *Bajo el puntero*.
- **Asistente de configuración…**: vuelve a abrir el asistente de cinco pasos.
- **Abrir config.json** / **Recargar config** (⌘R): para cambiar atajos y ajustes finos.
- **Salir de Stax** (⌘Q).

<br clear="right">

## Instalación

1. Compilar y armar el bundle (firmado con tu certificado de desarrollo si tenés uno, para que el permiso de
   Accesibilidad sobreviva a los rebuilds):

   ```bash
   scripts/bundle.sh                                                    # firma ad hoc
   SIGN_IDENTITY="Apple Development: Tu Nombre (XXXXXXXXXX)" scripts/bundle.sh
   cp -R build/Stax.app /Applications/
   open /Applications/Stax.app
   ```

2. **Accesibilidad**: Ajustes → Privacidad y seguridad → Accesibilidad → agregar `Stax.app`.
   Hace falta tanto para interceptar los atajos como para reordenar ventanas.
   **Grabación de pantalla**: sólo para compartir con ⌃⌥S; Stax lo pide la primera vez (relanzá la app después
   de otorgarlo).

3. Para que arranque al iniciar sesión: Ajustes → General → Ítems de inicio → agregar Stax.

## Configuración

`~/.config/stax/config.json` (se crea con los defaults la primera vez; "Recargar config" en el menú ⫼):

```json
{
  "columns": 3,
  "columnSelection": "focused",
  "hotkeys": [
    { "key": "`", "modifiers": ["command"], "action": "cycleNext" },
    { "key": "`", "modifiers": ["command", "shift"], "action": "cyclePrev" },
    { "key": "left", "modifiers": ["control", "command"], "action": "focusColumnLeft" },
    { "key": "right", "modifiers": ["control", "command"], "action": "focusColumnRight" },
    { "key": "d", "modifiers": ["control", "option"], "action": "moveToColumn", "column": 1 },
    { "key": "f", "modifiers": ["control", "option"], "action": "moveToColumn", "column": 2 },
    { "key": "g", "modifiers": ["control", "option"], "action": "moveToColumn", "column": 3 },
    { "key": "s", "modifiers": ["control", "option"], "action": "shareFocusedWindow" },
    { "key": "s", "modifiers": ["control", "option", "shift"], "action": "toggleFollowFocus" }
  ],
  "shareFollowsFocus": false,
  "shareBackend": "auto",
  "shareUsesVirtualDisplay": false,
  "setupCompleted": false,
  "raiseOnlyTargetWindow": true,
  "minimumWindowSize": 120,
  "verbose": false
}
```

- `columnSelection`: `focused` (columna de la ventana con foco) o `pointer` (columna bajo el mouse).
- `hotkeys[].key`: un carácter (`"\`"`, `"1"`), un nombre (`left`, `right`, `up`, `down`, `tab`, `space`,
  `escape`, `return`, `delete`) o `"keycode:50"`. Los caracteres se comparan sin modificadores, así ⌘⇧` sigue
  siendo "`" y no "~".
- `hotkeys[].modifiers`: combinación de `command`, `option`, `control`, `shift`.
- `hotkeys[].action`: `cycleNext`, `cyclePrev`, `focusColumnLeft`, `focusColumnRight`, `moveToColumn`
  (este último con `column`, 1-based), `shareFocusedWindow`, `stopSharing`, `toggleFollowFocus`.
- `shareFollowsFocus`: mientras se esté compartiendo, el origen sigue solo a la ventana con foco.
- `shareBackend`: `auto`, `mirror` (siempre el espejo) o `discord` (siempre el plugin StaxBridge).
- `shareUsesVirtualDisplay`: el espejo vive en una pantalla virtual en vez de ocupar lugar en el escritorio.
- `setupCompleted`: si el asistente ya se mostró. Ponelo en `false` para que vuelva a aparecer al arrancar.
- `raiseOnlyTargetWindow`: usa la API privada de SkyLight (técnica de AltTab/yabai) para subir sólo esa
  ventana. En `false` usa Accessibility puro, que trae todas las ventanas de la app.
- `verbose`: escribe cada atajo y acción en `~/Library/Logs/Stax.log`.

## Diagnóstico desde la terminal

```bash
.build/debug/Stax list              # ventanas por columna (▶ = columna activa)
.build/debug/Stax do cycleNext 2    # ejecuta una acción sobre la columna 2
.build/debug/Stax do moveToColumn 3 # mueve la ventana con foco al tercer tercio
tail -f ~/Library/Logs/Stax.log     # con "verbose": true
```

## Ícono y demo

Todo lo visual se genera por código, sin assets externos:

```bash
swift scripts/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
swift scripts/make-demo.swift                             # docs/demo-{cycle,focus,move,share}.gif
build/Stax.app/Contents/MacOS/Stax screenshot-menu docs/menu.png   # captura real del menú
```

## Cómo está hecho

- `Hotkeys.swift`: event tap global (`CGEvent.tapCreate`) sobre keyDown; consume el evento cuando coincide
  con un atajo configurado.
- `Windows.swift`: `CGWindowListCopyWindowInfo` (ventanas en pantalla, capa 0, apps regulares) + reparto en
  columnas; la ventana con foco se obtiene por Accessibility.
- `Focus.swift`: `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` + `AXRaise`, con fallback a
  `NSRunningApplication.activate` + `AXRaise`.
- `Share.swift`: `SCStream` sobre una sola ventana (`SCContentFilter(desktopIndependentWindow:)`) dibujado en un
  `AVSampleBufferDisplayLayer` dentro de la ventana *Stax Share*; cambiar de origen es `updateContentFilter`, sin
  cortar la captura.
- `Follow.swift`: `NSWorkspace.didActivateApplicationNotification` + `AXObserver` sobre la app frontal
  (`kAXFocusedWindowChangedNotification`) para el modo automático.
- `Bridge.swift`: socket UNIX en `~/.config/stax/bridge.sock` con JSON por líneas, para hablar con el plugin
  StaxBridge de Vencord; Stax es el servidor y el plugin reconecta solo.
- `VirtualDisplay.swift` + `Sources/StaxPrivate/`: la API privada `CGVirtualDisplay` de CoreGraphics (la misma
  de DeskPad y BetterDisplay) para registrar el monitor virtual donde vive el espejo.
- `scripts/make-demo.swift`: dibuja todas las animaciones de `docs/` con CoreGraphics, sin grabar pantalla.
  La cantidad de columnas es un parámetro de cada demo, de ahí salen las tres del asistente.
- `Setup.swift`: el asistente, en AppKit. Las transiciones son Core Animation sobre la capa de cada vista
  (`CASpringAnimation` para la entrada escalonada), así el layout lo sigue manejando Auto Layout sin pelearse
  con la animación.
- `VencordPlugin/staxBridge/`: el plugin, en TypeScript. `native.ts` habla por el socket desde el proceso
  principal de Discord; `index.tsx` cambia la fuente del Go Live con `setGoLiveSource` desde el renderer.

## Licencia

MIT. La técnica para subir una sola ventana de una app (`Focus.swift`) es la misma que usan
[yabai](https://github.com/koekeishiya/yabai) y [AltTab](https://github.com/lwouis/alt-tab-macos).
