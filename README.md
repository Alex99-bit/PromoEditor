# Promo Editor

Primera versión de una app nativa para Mac enfocada en armar promocionales
verticales a partir de videos existentes.

## Funciones de esta versión

- Abrir una carpeta con videos `.mp4`, `.mov` o `.m4v`.
- Previsualizar clips y añadirlos a una secuencia.
- Cambiar el orden, quitar tomas y ajustar sus puntos de inicio y fin.
- Exportar una secuencia vertical 9:16 en MP4 (1080 × 1920).
- Guardar y abrir proyectos `.json`; ese formato también permite que un
  asistente proponga o edite la lista de tomas.

Los originales no se modifican. El exportador crea un archivo nuevo; el
encuadre vertical rellena el lienzo recortando el centro de cada toma.

## Compilar en este Mac

Xcode está instalado en `/Applications/Xcode.app`. Antes de compilar por
primera vez, abre Xcode y acepta su licencia. Después, desde Terminal:

```sh
cd ~/PromoEditor
./build-app.sh
open "dist/Promo Editor.app"
```

La app queda en `dist/Promo Editor.app`.

## Próximas mejoras posibles

Subtítulos y títulos, música, transiciones, plantillas de marca, más formatos
de exportación y una conexión más directa para que el asistente aplique un
plan de edición.
