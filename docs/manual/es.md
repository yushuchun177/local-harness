# Local-Harness. Manual de usuario

> **Este programa no incluye ningún peso de modelo GGUF.** Debes descargar e importar un modelo por tu cuenta.

Local-Harness es una capa gráfica (harness) para llama.cpp: reúne la carga del modelo, los parámetros y el chat de varios turnos en una sola ventana, sin usar la línea de comandos.

---

## 1. Instalación y arranque

1. Descarga la versión publicada (zip portable o un único exe) y descomprímela en cualquier carpeta (se admiten rutas con acentos).
2. Ejecuta `local-harness.exe`.
3. En el primer arranque se carga el modelo; en el centro aparece un indicador durante unos segundos.
4. Cuando termine, escribe la pregunta en el cuadro inferior y pulsa Enter.

Estructura de la carpeta:

```
local-harness.exe      programa principal
_internal\             bibliotecas de ejecución (no las borres ni renombres)
llama\                 binarios de llama.cpp (llama-cli.exe y sus DLL)
model\                 tus modelos .gguf
chats\                 historial de conversaciones (se crea al primer arranque)
config.json            ajustes de interfaz y parámetros (se crea al primer arranque)
```

## 2. Preparar un modelo

No se incluye ningún modelo. Descarga un archivo GGUF (termina en `.gguf`), por ejemplo una versión cuantizada de Hugging Face o ModelScope.

Dos formas de importarlo:

- **Copiar a la carpeta**: coloca el `.gguf` en `model\`, reinicia el programa y aparecerá en el desplegable de modelos.
- **Importar desde la interfaz**: pulsa «Importar» y elige una carpeta con modelos; la ruta se recuerda.

Notas:

- En modelos divididos solo hace falta la primera parte (`xxx-00001-of-00002.gguf`); deja el resto en la misma carpeta.
- Los archivos mmproj, proyectores de visión, modelos de embeddings y reranking, y los archivos de menos de 20 MB se ignoran automáticamente.
- Los pesos se licencian por sus editores (por ejemplo, Qwen usa Apache-2.0). Respeta la licencia correspondiente.

Referencia de memoria:

| Tamaño del modelo | Tamaño de archivo (referencia) | Memoria recomendada |
| --- | --- | --- |
| 0.4B – 1B | 300 MB – 900 MB | 4 GB o más |
| 1.5B – 2B | 1 GB – 2 GB | 8 GB |
| 3B – 4B | 2 GB – 3 GB | 16 GB |

## 3. Interfaz

- **Barra superior**: selector de modelo, «Importar», parámetros (temperatura / contexto / límite de respuesta), modo de razonamiento, «Acerca de», «Ajustes» y cambio de tema.
- **Panel izquierdo**: lista de conversaciones. Al pasar el ratón aparece borrar; con clic derecho, renombrar o borrar.
- **Centro**: área de mensajes. La respuesta se muestra en streaming.
- **Abajo**: cuadro de texto y botón «Enviar»; mientras genera se convierte en «Detener».
- **Barra de estado**: a la izquierda el modelo, el contexto usado y el límite nativo del modelo; a la derecha el porcentaje de tokens de la conversación.

## 4. Parámetros

| Parámetro | Rango | Descripción |
| --- | --- | --- |
| Temperatura | 0 – 2 | Más bajo, más estable; más alto, más creativo. Código 0.2–0.6, preguntas 0.7, redacción 0.9–1.2 |
| Contexto | 512 – límite nativo del modelo | Tokens que conserva una conversación. El máximo del control lo marca el propio modelo; la barra de estado muestra «native xxxx» |
| Límite de respuesta | 64 – 8192 | Tokens máximos por respuesta. Si se corta, auméntalo |
| Modo de razonamiento | on / off | Para modelos con razonamiento (p. ej. Qwen3): primero razona y luego responde; el razonamiento no se muestra en la respuesta |

Los valores se pueden escribir directamente o cambiar con el control deslizante; se aplican al instante y se guardan en `config.json`.

## 5. Compresión de contexto

Las conversaciones largas acaban superando la ventana de contexto. Con la compresión automática activada, cuando la conversación alcanza el umbral, antes de la siguiente pregunta se resume el historial antiguo en un solo mensaje y se conservan los últimos turnos tal cual.

- Dónde: **Ajustes → Compresión de contexto**.
- El umbral se ajusta en pasos de 1024 tokens: **1024 / 2048 / 3072 / 4096**; por defecto **2048**.
- Puedes elegir cuántos turnos recientes se conservan literalmente (por defecto 4).
- La compresión lanza un proceso temporal del modelo y tarda unos segundos; durante ese tiempo no se puede enviar.
- Si la desactivas, inicia una conversación nueva cuando el contexto se llene.

## 6. Atajos de teclado

| Tecla | Acción |
| --- | --- |
| Enter | Enviar |
| Shift + Enter | Salto de línea |
| Ctrl + Enter | Enviar |
| Esc | Detener la generación |
| Ctrl + L | Limpiar el cuadro de texto |

## 7. Datos y copia de seguridad

- Las conversaciones se guardan en `chats\`, un `.json` por conversación; si borras el archivo, borras la conversación.
- La interfaz, los parámetros y las carpetas de modelos importadas están en `config.json`; si lo borras, vuelven los valores por defecto.
- El programa no accede a la red y no requiere cuenta; el contenido no se sube a ningún sitio.
- Para cambiar de equipo, copia toda la carpeta del programa, incluida `model\`.

## 8. Preguntas frecuentes

**Se abre y se cierra al instante**
Probablemente `_internal\` o `llama\` se movió o el antivirus lo bloqueó. Descomprime de nuevo la versión publicada.

**Dice que no hay archivo de modelo**
`model\` está vacía. Copia un `.gguf` o usa «Importar» para elegir una carpeta y reinicia.

**Mi modelo no aparece**
Comprueba que sea `.gguf`, de más de 20 MB y que no sea mmproj o de embeddings. En modelos divididos, solo la primera parte.

**Las respuestas son lentas**
Usa un modelo más pequeño; en «Ajustes» fija los hilos al número de núcleos de la CPU; conecta el portátil a la corriente y desactiva el ahorro de energía.

**Las respuestas se cortan**
Sube el «Límite de respuesta» (por ejemplo, 2048).

**Se vuelve lento tras una conversación larga o avisa del contexto**
La compresión automática está activa por defecto; revisa el umbral en «Ajustes» o inicia una conversación nueva.

**El nombre del modelo aparece como «Qwen3 0.6B · Q8_0»**
Es lo esperado: el nombre y la cuantización se leen de los metadatos GGUF.

## 9. Entorno de pruebas

Verificado en: Windows 11 (64 bits), Intel Core i5-4590 (4 núcleos / 4 hilos, AVX2), 16 GB de RAM, inferencia solo por CPU, sin usar GPU dedicada.

Velocidad de generación medida (4 hilos, contexto 2048): SmolLM2-360M unos 42 t/s, Llama-3.2-1B 21 t/s, Qwen3-0.6B 15 t/s, Qwen2.5-1.5B / Qwen3-1.7B unos 7 t/s, Qwen2.5-3B 6 t/s. La tabla completa está en el README.

## 10. Licencia

Este proyecto se distribuye bajo GPLv3. Se permite distribuir binarios empaquetados, pero al distribuir el programa (código fuente o binario) hay que proporcionar también el código fuente completo correspondiente; las versiones modificadas deben seguir siendo de código abierto.

Los pesos de los modelos no forman parte del proyecto y se rigen por las licencias de sus editores.
