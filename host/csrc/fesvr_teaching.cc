// The teaching CPU's PS-side host. An isolated copy of fesvr_zynq.cc: the shared one keeps its bytes.
//
// One difference, and it is the point of the file. fesvr_zynq constructs its driver -- which pulses
// SYSTEM_RESET 1 then 0 with no hold and no read-back -- and goes straight into the poll loop. Here the
// restart is an explicit step that must succeed before anything is loaded, and "succeed" means the design
// reported full boot readiness, not that a timer expired.
//
// Scope, stated so it is not over-read: this supports a COLD platform start. It does not claim that the
// host may be killed and restarted against a running design, and it does not claim PL reconfiguration is
// safe -- PL_RECONFIG_SAFE is 0 in this design and this host never asserts otherwise.

#include "teaching_driver.h"
#include "teaching_real_ports.h"
#include "fesvr/tsi.h"
#include <vector>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BLKDEV_NTAGS 2

static inline int copy_argv(int argc, char **argv, char **new_argv)
{
    int optind = 1;
    int new_argc = argc;

    new_argv[0] = argv[0];

    for (int i = 1; i < argc; i++) {
        if (argv[i][0] != '+') {
            optind = i - 1;
            new_argc = argc - i + 1;
            break;
        }
    }

    for (int i = 1; i < new_argc; i++)
        new_argv[i] = argv[i + optind];

    return new_argc;
}

// A mode that touches nothing. It must return before `tsi_t` is constructed and before any register
// backend exists, because constructing those is what opens /dev/mem and starts reading MMIO -- and on an
// unconfigured PL there is no AXI slave to answer, so there is no guaranteed clean exit and the access can
// hang or fault the PS. This is therefore the ONLY invocation that is safe on an unconfigured board, and
// it is safe by construction rather than by hope: it returns above every constructor.
static int teaching_self_test(void)
{
    printf("TEACHING_HOST_SELFTEST\n");
    printf("  build: %s %s\n", __DATE__, __TIME__);
    printf("  status word bit map: bit0 CPU_RESTART_SAFE, bit1 PL_RECONFIG_SAFE, bit2 DRAINING, "
           "bit3 DRAIN_TIMEOUT, bit4 BOOT_READY, bit5 BOOT_TIMEOUT\n");
    printf("  hold floor %d ms, default ready timeout %d ms\n",
           TEACHING_HOLD_FLOOR_MS, TEACHING_READY_TIMEOUT_MS);
    printf("  no device was opened, mapped, read or written by this invocation\n");
    return 0;
}

int main(int argc, char** argv)
{
    // Before anything else, and in particular before tsi_t and before any register backend.
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--self-test") == 0 || strcmp(argv[i], "--version") == 0)
            return teaching_self_test();
    }

    char **new_argv = (char **) malloc(sizeof(char *) * argc);
    int new_argc = copy_argv(argc, argv, new_argv);
    tsi_t tsi(new_argc, new_argv);

    BlockDevice *blkdev = NULL;
    unsigned ready_timeout_ms = TEACHING_READY_TIMEOUT_MS;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "+blkdev=", 8) == 0)
            blkdev = new BlockDevice(argv[i] + 8, BLKDEV_NTAGS);
        else if (strncmp(argv[i], "+ready_timeout_ms=", 18) == 0)
            ready_timeout_ms = (unsigned) strtoul(argv[i] + 18, NULL, 0);
    }

    // Cold-only scope, stated explicitly because it is what makes the gating claim meaningful: `tsi` is
    // a freshly constructed tsi_t for this process. Nothing has asked it for a word yet, and the driver
    // withholds TSI input for the whole of the restart wait, so the first word of the ELF cannot reach the
    // design before BOOT_READY. This does not rest on "main's poll loop starts later" -- the wait itself
    // is what refuses to push.
    teaching_mmap_regs regs;
    teaching_real_tsi  tsi_port(&tsi);
    teaching_real_blk  *blk_port = blkdev ? new teaching_real_blk(blkdev) : NULL;
    teaching_driver_t *driver = new teaching_driver_t(&regs, &tsi_port, blk_port);

    // Fail-stop: if readiness is not reported, nothing is loaded and the request stays asserted. Exiting
    // here with the design held is the safe state; releasing it would hand the bus back to a device that
    // may still have a transfer in flight, which is the failure this whole handshake exists to avoid.
    if (!driver->request_restart_and_wait(ready_timeout_ms)) {
        fprintf(stderr, "teaching: fail-stop before load. Recover by cold platform restart; do not "
                        "reconfigure the PL while transactions may be outstanding.\n");
        delete driver; delete blk_port;
        if (blkdev != NULL) delete blkdev;
        return 2;
    }
    driver->release_restart();

    while (!tsi.done())
        driver->poll();          // POLL_ALL from here: loading is allowed now, and only now

    delete driver; delete blk_port;
    if (blkdev != NULL)
        delete blkdev;

    return tsi.exit_code();
}
