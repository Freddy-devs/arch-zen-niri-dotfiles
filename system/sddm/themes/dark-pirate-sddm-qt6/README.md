![Dark Pirate SDDM preview](login-preview.png "Dark Pirate SDDM preview")

# Dark Pirate SDDM

Tema de inicio de sesión para SDDM con estilo oscuro y acentos configurables. Construido sobre **Qt Quick Controls 2** para buen rendimiento y transiciones suaves.

Personaliza colores, fuente, formatos de hora/fecha y textos desde [`theme.conf`](theme.conf). Variables útiles: `MainColor`, `AccentColor`, `Font`, `HourFormat`, `TranslateUsernamePlaceholder`.

### Dependencies

[`sddm >= 0.18.0`](https://github.com/sddm/sddm), [`qt5 >= 5.11.0`](http://doc.qt.io/qt-5/index.html), [`qt5-quickcontrols2 >= 5.11.0`](http://doc.qt.io/qt-5/qtquickcontrols2-index.html), [`qt5-svg >= 5.11.0`](https://doc.qt.io/qt-5/qtsvg-index.html)

*Make sure these are up to date!*

### Installing the theme

###### From KDE Plasma

En [KDE Plasma](https://www.kde.org/plasma-desktop) ve a Configuración del sistema → "Inicio y apagado" → "Pantalla de inicio de sesión (SDDM)" → "Obtener nuevo tema" y busca "Dark Pirate SDDM".

Si no ves la categoría "Pantalla de inicio de sesión (SDDM)" instala `sddm-kcm` con tu gestor de paquetes.

###### From other desktop environments

[Descarga el paquete] y extrae en el directorio de temas de SDDM:
```
$ sudo tar -xzvf ~/Downloads/dark-pirate-sddm.tar.gz -C /usr/share/sddm/themes
```
Esto creará la carpeta "dark-pirate-sddm" dentro de `/usr/share/sddm/themes`.

Luego edita `/etc/sddm.conf.d/sddm.conf` *(créalo si no existe)*. Puedes tomar como referencia `/usr/lib/sddm/sddm.conf.d/sddm.conf`.

En la sección `[Theme]` del archivo agrega: `Current=dark-pirate-sddm`. Consulta también la [Arch wiki de SDDM](https://wiki.archlinux.org/index.php/SDDM).

### Theming the theme

Edita `theme.conf` para cambiar colores e imágenes, formatos, apariencia y textos. También puedes traducir etiquetas según tus necesidades.

Consulta `theme.conf` para ver y cambiar todas las variables disponibles.

### Aviso legal

Copyright (C) 2025 Freddy Sedano.

Este tema se distribuye bajo la **GPLv3**. Se proporciona sin garantía de ningún tipo. Consulta <https://www.gnu.org/licenses/> para más detalles.

[Mockup psd created by Qeaql-studio - Freepik.com](https://www.freepik.com/free-photos-vectors/mockup)

### Créditos

Autor: Freddy Sedano — hypercod.com — github:https://github.com/Freddy-system — freddy.sc.dev@gmail.com
