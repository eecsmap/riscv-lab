// Exercise the teaching host's restart logic without a board.
//
// The question this exists to answer is codex's: request_restart_and_wait services the ports while it
// waits, and a full poll() pushes words into TSI_IN, which is how an ELF load *begins*. Claiming that no
// load starts before BOOT_READY is worth nothing unless something counts the words. The fake TSI below
// counts every recv_word(), and always reports data available -- i.e. it behaves like a host with an ELF
// ready to send, the worst case for this claim.

#include "teaching_driver.h"
#include "blkdev.h"
#include <cstdio>
#include <cstring>
#include <vector>

#define REG_SYSTEM_RESET 0x10
#define REG_STATUS       0x14
#define ST_CPU_RESTART_SAFE (1u<<0)
#define ST_BOOT_READY       (1u<<4)
#define ST_BOOT_TIMEOUT     (1u<<5)

static int pass = 0, fail = 0;
static void want(bool c, const char *what, const char *why)
{ if (c) { pass++; printf("  ok   : %s\n", what); } else { fail++; printf("  FAIL : %s -- %s\n", what, why); } }

// ---- fake ports -------------------------------------------------------------------------------------
struct FakeRegs : teaching_regs {
    uint32_t sys_reset = 1;          // as the adapter does: RegInit(true.B)
    uint32_t st = 0;
    int polls = 0;
    int ready_after = 0;             // status reads before BOOT_READY appears
    bool ever_timeout = false;
    uint32_t read(int off) {
        if (off == REG_SYSTEM_RESET) return sys_reset;
        if (off == REG_STATUS) {
            polls++;
            uint32_t s = st;
            if (ever_timeout) s |= ST_BOOT_TIMEOUT;
            else if (sys_reset && polls >= ready_after) s |= ST_BOOT_READY;
            return s;
        }
        if (off == 0x0C) return 16;  // TSI_IN_FIFO_COUNT: space available, so a push WOULD happen
        return 0;                    // the other FIFO counts: nothing waiting
    }
    void write(int off, uint32_t w) { if (off == REG_SYSTEM_RESET) sys_reset = w; }
};

struct FakeTsi : teaching_tsi {
    int recvs = 0, sends = 0, switches = 0;
    // A host with an ELF ready to send: a finite number of words so that a driver which does push can
    // finish rather than spin, and so the count below is a real number and not an artefact.
    bool data_available() { return recvs < 32; }
    uint32_t recv_word() { recvs++; return 0; }     // <-- this is a load starting
    void send_word(uint32_t) { sends++; }
    void switch_to_host() { switches++; }
    bool done() { return false; }
    int exit_code() { return 0; }
};

struct FakeBlk : teaching_blk {
    int serviced = 0;
    void send_request(struct blkdev_request &) {}
    void send_data(struct blkdev_data &) {}
    bool resp_valid() { return false; }
    struct blkdev_data recv_response() { struct blkdev_data d; memset(&d, 0, sizeof(d)); return d; }
    void switch_to_host() { serviced++; }
    uint32_t nsectors() { return 4000; }
    uint32_t max_request_length() { return 16; }
};

int main()
{
    printf("== 1. a design that is ready: no TSI word may be pushed before readiness\n");
    {
        FakeRegs r; FakeTsi t; FakeBlk b;
        r.ready_after = 5;
        teaching_driver_t d(&r, &t, &b);
        bool ok = d.request_restart_and_wait(5000);
        want(ok, "the wait succeeds", "readiness was reported and should have been seen");
        want(t.recvs == 0, "no TSI word was pulled from the host during the wait",
             "a word pulled here is the first word of an ELF going into a design that has not drained");
        want(t.switches == 0, "switch_to_host was not called during the wait",
             "that is the other half of how a load is driven");
        want(b.serviced > 0, "the block device WAS serviced during the wait",
             "without this the drain cannot finish: accepted transfers still need data and responses");
        want(r.sys_reset == 1, "the request is still asserted when the wait returns",
             "releasing is the caller's separate step");
        d.release_restart();
        want(r.sys_reset == 0, "release_restart clears it", "the design must actually be let go");
    }

    printf("== 2. a design that never drains: timeout\n");
    {
        FakeRegs r; FakeTsi t; FakeBlk b;
        r.ready_after = 1 << 30;                    // never
        teaching_driver_t d(&r, &t, &b);
        bool ok = d.request_restart_and_wait(300);
        want(!ok, "the wait fails", "a design that never reports readiness must not be accepted");
        want(r.sys_reset == 1, "SYSTEM_RESET is LEFT ASSERTED on failure",
             "letting go of a design that may still have a transfer in flight is the failure to avoid");
        want(t.recvs == 0, "still no TSI word was pulled", "nothing may be loaded on this path");
    }

    printf("== 3. the design reports it never drained (BOOT_TIMEOUT)\n");
    {
        FakeRegs r; FakeTsi t; FakeBlk b;
        r.ever_timeout = true;
        teaching_driver_t d(&r, &t, &b);
        bool ok = d.request_restart_and_wait(5000);
        want(!ok, "the wait fails on the sticky timeout bit", "the design said so explicitly");
        want(r.sys_reset == 1, "SYSTEM_RESET is left asserted", "same rule");
        want(t.recvs == 0, "no TSI word was pulled", "same rule");
    }

    printf("== 4. a timeout shorter than the 50 ms hold floor is still honoured\n");
    {
        // codex's finding: the hold-floor path used `continue`, which skipped the deadline check, so a
        // timeout below the floor could never fire.
        FakeRegs r; FakeTsi t; FakeBlk b;
        r.ready_after = 1;                          // ready immediately, so the floor path is taken
        teaching_driver_t d(&r, &t, &b);
        bool ok = d.request_restart_and_wait(10);    // 10 ms < 50 ms floor
        want(!ok, "the wait fails rather than spinning past its deadline",
             "the deadline must be honoured on every path, including inside the hold floor");
        want(r.sys_reset == 1, "SYSTEM_RESET is left asserted", "same rule");
        want(t.recvs == 0, "no TSI word was pulled", "same rule");
    }

    printf("TEACHING_HOST_TEST pass=%d fail=%d\n", pass, fail);
    return fail ? 1 : 0;
}
