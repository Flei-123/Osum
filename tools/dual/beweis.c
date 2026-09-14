// beweis.c -- eine winzige UEFI-Anwendung, die NUR eines tut: sie
// schreibt einen unverwechselbaren Satz auf die serielle Leitung (COM1,
// 0x3F8) und auf den Schirm, und bleibt dann stehen.
//
// WOFUER. Der Kettenstart (`efi_chainload`) laesst sich nur dann wirklich
// belegen, wenn die Datei, auf die gekettet wird, sich SELBST zu erkennen
// gibt. Eine zweite Kopie von limine tut das nicht -- sie sucht dieselbe
// Konfiguration wie die erste und ist von ihr nicht zu unterscheiden.
// Diese Datei steht an der Stelle, an der auf einem echten Rechner
// \EFI\Microsoft\Boot\bootmgfw.efi liegt.

typedef unsigned short u16;
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned char u8;

struct SimpleTextOut;
struct SimpleTextOut {
    void *reset;
    u64 (*output_string)(struct SimpleTextOut *, u16 *);
};

struct SystemTable {
    char hdr[24];
    u16 *fw_vendor;
    u32 fw_revision;
    void *con_in_handle;
    void *con_in;
    void *con_out_handle;
    struct SimpleTextOut *con_out;
};

static void outb(u16 port, u8 v) {
    __asm__ __volatile__("outb %0, %1" : : "a"(v), "Nd"(port));
}

static u8 inb(u16 port) {
    u8 v;
    __asm__ __volatile__("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}

static void ser_init(void) {
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x80);
    outb(0x3F8 + 0, 0x03);
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x03);
    outb(0x3F8 + 2, 0xC7);
    outb(0x3F8 + 4, 0x0B);
}

static void ser_putc(char c) {
    int guard = 0;
    while (!(inb(0x3F8 + 5) & 0x20) && guard < 100000) guard++;
    outb(0x3F8, (u8)c);
}

static void ser_puts(const char *s) {
    while (*s) {
        if (*s == '\n') ser_putc('\r');
        ser_putc(*s);
        s++;
    }
}

u64 __attribute__((ms_abi)) efi_main(void *image, struct SystemTable *st) {
    static u16 msg[] = {
        'B','E','W','E','I','S',':',' ','K','E','T','T','E','N','S','T',
        'A','R','T',' ','H','A','T',' ','F','U','N','K','T','I','O','N',
        'I','E','R','T','\r','\n', 0
    };
    ser_init();
    ser_puts("\nBEWEIS: KETTENSTART HAT FUNKTIONIERT -- bootmgfw.efi laeuft\n");
    if (st && st->con_out && st->con_out->output_string) {
        st->con_out->output_string(st->con_out, msg);
    }
    for (;;) {
        ser_puts("BEWEIS: fremder Bootmanager steht\n");
        for (volatile u64 i = 0; i < 200000000ULL; i++) { }
    }
    return 0;
}
