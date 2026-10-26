Real firmware tables (AMD server, read from /sys/firmware/acpi/tables).
Replay: rewrite the signature to SSDT, fix the checksum, pass each file to qemu with -acpitable sig=SSDT,file=<f>.
Expected with the loader: aml_hold e=0 bad=0 nodes=3476 (was e=9 bad=1: OperationRegion base named a Field).
