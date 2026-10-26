#include "util.h"

#ifndef PROOF_MARKER
#error PROOF_MARKER missing
#endif

#define STALL_US 2000000

u64 EFIAPI efi_main(handle_t image, system_table_t *st)
{
    (void)image;
    log_init(st);
    log_str("\nPROOF: ");
    log_str(PROOF_MARKER);
    log_str("\n");
#ifdef PROOF_RETURN_ERROR
    st->bs->stall(STALL_US);
    return EFI_ABORTED;
#else
    for (;;) st->bs->stall(STALL_US);
#endif
}
