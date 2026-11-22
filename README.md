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
- Exportar proyectos desde Terminal con `PromoEditorCLI`, usando el mismo
  motor que la app.
- Añadir títulos animados de apertura y cierre, además de un logo superpuesto.

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
El comando de exportación queda en `dist/PromoEditorCLI`. Ejemplo:

```sh
dist/PromoEditorCLI --project mi-proyecto.promo.json --output prueba.mp4
```

Por seguridad, el comando no reemplaza archivos existentes salvo que se
indique expresamente `--overwrite`.
También se puede abrir la app directamente con un proyecto:

```sh
open -a "dist/Promo Editor.app" --args --project "/ruta/al/proyecto.promo.json"
```

## Próximas mejoras posibles

Corrección de color, transiciones entre tomas, plantillas de marca, más formatos
de exportación y una conexión más directa para que el asistente aplique un plan
de edición.
