# /usr/share/apps/explorer.app -- der Dateimanager.
#
# DER ANZEIGENAME STEHT HIER UND NICHT IM QUELLTEXT. Eine Beschriftung,
# die einkompiliert ist, laesst sich nicht austauschen, ohne zu
# uebersetzen -- und dieses Projekt haelt austauschbare Zeichenketten in
# Daten (dieselbe Regel wie `brands/*.toml` in OrientOS).
#
# Der Name IST die Beschreibung: es heisst "Datei-Explorer" und nicht
# Nautilus, Finder oder sonst ein Kunstwort, das man erst lernen muss.
name=Datei-Explorer
info=Dateien und Ordner ansehen
exec=/bin/explorer
icon=4a90d0
# WOFUER DIE SCHLUESSELWOERTER DA SIND: man tippt "folder" oder
# "verzeichnis" und findet ihn, obwohl KEINES der beiden Woerter im
# Anzeigenamen oder in der Beschreibung steht. Genau das misst
# tools/k15/run.sh, und genau das ist der Unterschied zwischen einer
# Suche und einem Namensvergleich.
keys=datei,dateien,explorer,ordner,verzeichnis,manager,file,files,folder
