# Captura Larga

App para iPhone (SwiftUI, iOS 17 o posterior) que crea **capturas de pantalla largas**: une varias
capturas hechas mientras deslizas en cualquier app en una sola imagen, o captura una página web
completa de arriba abajo.

[![iOS CI](https://github.com/WilliamMCh7/ai-edge-skills/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/WilliamMCh7/ai-edge-skills/actions/workflows/ios-ci.yml)

## Qué hace

La app tiene dos pestañas:

1. **Unir**: eliges varias capturas de pantalla (de un chat, una red social, una web, unos ajustes…)
   y la app las ordena, detecta qué parte de cada una repite a la anterior y las une sin cortes ni
   duplicados. Quita las barras fijas (barra de estado, barra de navegación, barra de pestañas) de las
   capturas intermedias, para que el resultado parezca una sola pantalla muy alta.
   - «Elegir capturas» abre tu fototeca (puedes elegir hasta 30, en orden).
   - «Usar capturas recientes» toma automáticamente la última tanda de capturas que hiciste seguidas.
   - «Probar con un ejemplo» carga cuatro capturas de muestra para ver cómo funciona.
   - En el resultado puedes revisar y ajustar cada unión al píxel («Ajustar»), mostrar u ocultar las
     barras superior e inferior, guardar en Fotos como PNG o compartir.
2. **Web**: escribes una dirección (o lo que quieras buscar), navegas hasta la página y pulsas
   «Capturar página». La app recorre la página para que cargue todo su contenido y genera una imagen
   de la página completa en alta resolución, además de un **PDF** que puedes compartir.

## Cómo instalarla en tu iPhone

No está en la App Store: se instala desde el código con Xcode. Solo necesitas un Mac y una cuenta de
Apple normal (gratuita).

1. **Requisitos**: un Mac con **Xcode 16 o posterior** (gratis en la Mac App Store) y un iPhone con
   **iOS 17 o posterior**.
2. **Descarga el código**: clona este repositorio (`git clone https://github.com/WilliamMCh7/ai-edge-skills.git`)
   o descárgalo como ZIP desde GitHub y descomprímelo.
3. **Abre el proyecto**: haz doble clic en `iphone-long-screenshot/LongScreenshot.xcodeproj`.
4. **Añade tu cuenta de Apple**: en Xcode, menú *Xcode → Settings… → Accounts*, pulsa «+» y entra con
   tu Apple ID. La cuenta gratuita basta (crea un «Personal Team»).
5. **Configura la firma**: en el navegador del proyecto selecciona el proyecto *LongScreenshot*, luego el
   target **LongScreenshot** → pestaña *Signing & Capabilities*:
   - Deja marcado *Automatically manage signing*.
   - En *Team* elige tu «Personal Team».
   - Cambia el *Bundle Identifier* `com.capturalarga.app` por uno único, por ejemplo
     `com.tunombre.capturalarga` (los identificadores no se pueden repetir entre cuentas).
6. **Conecta el iPhone** por cable (o por la misma red Wi-Fi una vez emparejado) y desbloquéalo. Si
   pregunta «¿Confiar en este ordenador?», pulsa *Confiar*.
7. **Activa el Modo desarrollador** en el iPhone (iOS 16 o posterior): *Ajustes → Privacidad y
   seguridad → Modo desarrollador*, actívalo y reinicia cuando lo pida. Si la opción no aparece,
   conecta primero el iPhone al Mac con Xcode abierto y vuelve a mirar.
8. **Ejecuta la app**: en la barra superior de Xcode elige tu iPhone como destino y pulsa ▶︎ (*Run*,
   `⌘R`). La primera vez tarda un poco.
9. **Confía en el perfil del desarrollador**: la primera vez el iPhone dirá que el desarrollador no es
   de confianza. Ve a *Ajustes → General → VPN y gestión de dispositivos*, toca tu Apple ID y pulsa
   *Confiar*. Vuelve a abrir la app.

> **La firma gratuita caduca a los 7 días.** Con una cuenta gratuita la app deja de abrirse al cabo de
> una semana; basta con volver a conectar el iPhone y pulsar ▶︎ en Xcode para renovarla (tus fotos no
> se ven afectadas). Con una cuenta del Apple Developer Program (de pago) dura un año.

## Cómo usarla bien

- **Haz las capturas con superposición.** Cada captura debe repetir una parte de la anterior: así la
  app sabe exactamente dónde unirlas. Un buen consejo es **dejar más o menos 1/4 de pantalla
  repetida**: desliza unas tres cuartas partes de la pantalla entre captura y captura.
- Desliza despacio y espera a que el contenido se detenga antes de capturar (botón lateral + subir
  volumen).
- Elige las capturas **de arriba abajo**. Si te equivocas de orden y todas están al revés, la app lo
  detecta y lo corrige sola («Orden invertido automáticamente»); también puedes reordenar arrastrando.
- Si una zona repetida está totalmente en blanco (sin texto ni dibujos), no se puede medir: la app la
  une de forma estimada y te pide que la revises. Usa «Ajustar» para moverla píxel a píxel.
- Las capturas de pantalla del iPhone se guardan en PNG (sin pérdida), que es el caso ideal. Si usas
  imágenes JPEG (por ejemplo, reenviadas por una app de mensajería), también funciona, con una
  tolerancia mayor.

## Cómo funciona el algoritmo

El código está en `LongScreenshot/Stitching/` y es una traducción directa del prototipo en Python de
`reference/` (mismas constantes y mismas decisiones).

1. **Firmas por fila.** Cada captura se convierte a escala de grises y cada fila de píxeles se resume
   en una «firma»: el gris medio de entre 48 y 128 franjas verticales. Comparar firmas es mucho más
   rápido que comparar píxeles y tolera pequeñas diferencias.
2. **Filas clave.** Solo cuentan las filas que cambian respecto a la anterior (bordes de texto,
   iconos, separadores). Las filas de bloques lisos se repiten y darían coincidencias falsas.
3. **Ignorar barras fijas.** Las filas idénticas en la misma posición de dos capturas consecutivas
   (barra de estado, barra de navegación, barra de pestañas, botones flotantes) se marcan como fijas y
   no se usan para medir el desplazamiento.
4. **Desplazamiento por votación.** Para cada desplazamiento posible se cuentan las filas clave de la
   captura inferior que coinciden con la superior (aciertos menos el doble de fallos, sobre hasta 400
   filas). Los 24 mejores candidatos se analizan en detalle: se busca el tramo continuo de
   coincidencias más largo (la zona común) y se exige un mínimo de apoyos. Después se afina ±6
   píxeles.
5. **Costuras dentro de la zona común.** El corte entre dos capturas se hace en mitad de la zona
   repetida, lejos de las barras fijas, de modo que no se ve ninguna unión.
6. **Modo JPEG.** Si alguna de las dos imágenes tiene compresión con pérdida (JPEG o HEIC) se usa una
   comparación tolerante basada en el coste (mediana de diferencias) y un margen claro frente al
   segundo mejor candidato.
7. **Uniones estimadas.** Si la zona común está en blanco o es demasiado pequeña, no hay nada que
   medir: la unión se marca como *estimada*, se quitan las barras fijas y se fusiona el espacio en
   blanco compartido. La app avisa («Revisa N uniones»).
8. **Duplicados y orden.** Las capturas idénticas a la anterior se descartan, y si todas las uniones
   parecen al revés se invierte el orden automáticamente.
9. **Ajuste manual.** En el editor de uniones ves cada costura de cerca y puedes moverla con
   precisión de un píxel o restablecerla. Los cambios se vuelven a dibujar al momento.

Con capturas PNG cuya zona común tiene algo de contenido, el resultado es exacto al píxel (validado
en más de 380 uniones sintéticas sin ninguna coincidencia errónea).

## Limitaciones (honestas)

- **iOS no permite que una app capture la pantalla de otras apps ni haga scroll en ellas.** Por eso
  tienes que hacer tú las capturas mientras deslizas; la app solo las une. (El modo Web sí captura la
  página completa por sí mismo porque la página se abre dentro de la propia app).
- **Contenido animado o que cambia** entre capturas (vídeos, GIF, anuncios rotativos, relojes,
  indicadores de «escribiendo…») puede impedir encontrar la zona común; esas uniones quedan estimadas
  y conviene revisarlas.
- **JPEG**: con imágenes recomprimidas la unión puede desviarse unos pocos píxeles; revisa las
  uniones si ves un salto.
- Zonas repetidas completamente en blanco no se pueden medir (ver «Uniones estimadas»).
- Algunas webs bloquean el contenido hasta iniciar sesión, usan desplazamiento dentro de marcos o
  cabeceras flotantes; la captura web refleja lo que el motor WebKit puede imprimir en PDF.
- Las imágenes muy altas se reducen de forma uniforme para no superar unos 60 millones de píxeles.

## Estructura del proyecto

```
iphone-long-screenshot/
├── LongScreenshot.xcodeproj        Proyecto de Xcode 16 (carpetas sincronizadas) y esquema compartido
├── LongScreenshot/                 Código de la app (todo lo que hay aquí entra en la app)
│   ├── App/                        Punto de entrada y pestañas (RootView)
│   ├── DesignSystem/               Colores, botones, tarjetas y chips (Theme)
│   ├── Features/
│   │   ├── Stitch/                 Pestaña «Unir»: lista de capturas y modelo de vista
│   │   ├── Result/                 Resultado, vista por mosaicos y editor de uniones
│   │   └── Web/                    Pestaña «Web»: navegador y captura de página completa
│   ├── Imaging/                    Carga/exportación de imágenes, Fotos, capturas recientes y demo
│   ├── Stitching/                  Algoritmo de unión: firmas, detección de costuras, plan y render
│   └── Assets.xcassets             Icono y color de acento
├── LongScreenshotTests/            Tests unitarios (algoritmo, plan, imágenes, captura web)
├── LongScreenshotUITests/          Recorrido de la app con capturas de cada paso
└── reference/                      Prototipo del algoritmo en Python (no forma parte de la app)
```

No hay `Info.plist`: se genera a partir de los ajustes de compilación del proyecto (nombre visible,
textos de permiso de Fotos, orientación vertical). La app no usa paquetes de terceros.

## Tests y CI

- **Tests unitarios** (`LongScreenshotTests`): reconstrucción exacta de páginas sintéticas con
  distintos solapamientos, listas repetitivas, botón flotante, resolución 3x, JPEG, orden invertido,
  duplicados, zonas en blanco, carga de imágenes y orientación EXIF, y captura web.
- **Tests de interfaz** (`LongScreenshotUITests/AppTourUITests.swift`): abren la app, cargan el
  ejemplo, unen las capturas, abren el editor de uniones y capturan `example.com` en la pestaña Web,
  guardando una captura de pantalla de cada paso.

Para ejecutarlos en tu Mac: en Xcode, `⌘U`; o desde la terminal:

```sh
cd iphone-long-screenshot
xcodebuild test -project LongScreenshot.xcodeproj -scheme LongScreenshot \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

**Integración continua**: cada cambio en `iphone-long-screenshot/` ejecuta el flujo
[`iOS CI`](https://github.com/WilliamMCh7/ai-edge-skills/actions/workflows/ios-ci.yml) en un Mac de
GitHub Actions (pestaña [Actions](https://github.com/WilliamMCh7/ai-edge-skills/actions)): compila con
el Xcode más reciente, ejecuta todos los tests en un simulador de iPhone y publica como artefactos
las capturas de pantalla del recorrido, el `.xcresult` y el log de compilación.

## Carpeta `reference/`

Contiene el **prototipo en Python** del algoritmo (`stitch.py`), un generador de capturas sintéticas
con su verdad de referencia (`synth.py`), los casos de prueba (`test_stitch.py`) y una prueba de
estrés con cientos de uniones aleatorias (`stress.py`). Sirve para diseñar y comprobar cambios en el
algoritmo rápidamente antes de llevarlos a Swift. Requiere `numpy` y `pillow`; consulta
`reference/README.md`.
