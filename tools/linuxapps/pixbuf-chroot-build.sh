set -e
apk add --no-cache build-base meson ninja pkgconf glib-dev libpng-dev libjpeg-turbo-dev shared-mime-info gdk-pixbuf-dev >/tmp/apk.log 2>&1 || true
cd /src
meson setup /b -Dglycin=disabled -Dpng=enabled -Djpeg=enabled -Dtiff=disabled -Dgif=disabled -Dothers=disabled -Dlegacy_xpm=disabled -Dbuiltin_loaders=png,jpeg -Dintrospection=disabled -Dgtk_doc=false -Ddocumentation=false -Dman=false -Dtests=false -Dinstalled_tests=false -Dthumbnailer=disabled -Drelocatable=false --prefix=/usr
ninja -C /b
cp -L /b/gdk-pixbuf/libgdk_pixbuf-2.0.so.0 /out.so
strip --strip-unneeded /out.so
