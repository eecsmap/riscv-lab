#ifndef __TEACHING_DRIVER_H
#define __TEACHING_DRIVER_H

// An isolated PS-side host for the teaching CPU. A copy of zynq_driver, not an edit of it: the shared
// driver and fesvr_zynq.cc keep their exact bytes, which is the same discipline ZynqAdapterRD2 follows and
// for the same reason -- "the default path is untouched" is worth more as a hash than as a claim.
//
// The difference that matters is the restart handshake. zynq_driver_t's constructor writes SYSTEM_RESET=1
// and then 0 immediately, with no hold and nothing read back, so it cannot know whether the block device
// had finished the DMA it had already accepted. The teaching design answers that question in a register,
// so this host asks it instead of waiting a fixed time and hoping.

#include "teaching_ports.h"
#include <stdint.h>

// The RD2 adapter's status word at 0x14 (read-only). Bit order taken from the Cat in RD2Soc.scala and
// confirmed against the generated board RTL -- see xv6-board-prep/STATUS-MAP.md.
#define TEACHING_STATUS            0x14
#define TEACHING_QUIESCE           0x18
#define TEACHING_ST_CPU_RESTART_SAFE (1u << 0)
#define TEACHING_ST_PL_RECONFIG_SAFE (1u << 1)   // 0 in this design; reconfiguration is never claimed safe
#define TEACHING_ST_DRAINING         (1u << 2)
#define TEACHING_ST_DRAIN_TIMEOUT    (1u << 3)   // sticky to cold reset
#define TEACHING_ST_BOOT_READY       (1u << 4)   // old DMA done, old completions flushed, CPU reset applied
#define TEACHING_ST_BOOT_TIMEOUT     (1u << 5)   // sticky: the device never drained
#define TEACHING_ST_EPOCH(s)      (((s) >> 8) & 0xff)
#define TEACHING_ST_NDRAINED(s)   (((s) >> 16) & 0xffff)

// The accepted board operating condition is a hold of at least 50 ms before each program load. It is kept
// here as a *floor*, not as the criterion: elapsed time is not evidence that a DMA finished, so the hold
// and the ready bit are both required and neither substitutes for the other.
#define TEACHING_HOLD_FLOOR_MS   50
#define TEACHING_READY_TIMEOUT_MS 5000

class teaching_driver_t {
  public:
    // The ports are injected so the logic below can be tested. Ownership stays with the caller.
    teaching_driver_t(teaching_regs *regs, teaching_tsi *tsi, teaching_blk *bdev);
    ~teaching_driver_t();

    // Servicing existing work and initiating new work are separate things, and during the restart wait
    // only the first is allowed. A full poll() pushes tsi->recv_word() into TSI_IN and calls
    // switch_to_host(), which is how an ELF load *starts* -- doing that before BOOT_READY would load into a
    // design that has not finished draining, which is the exact thing this handshake exists to prevent.
    enum PollMode { POLL_ALL, POLL_DRAIN_ONLY };
    void poll(PollMode mode = POLL_ALL);

    // Assert the restart request, keep servicing work that was already accepted, and wait -- bounded -- for
    // the design to report full boot readiness. Returns true only if the ready bit was observed.
    //
    // On failure the request is deliberately LEFT ASSERTED and false is returned: the caller must not load
    // anything and must not release. A design that never drained is not made safe by letting go of it.
    bool request_restart_and_wait(unsigned timeout_ms = TEACHING_READY_TIMEOUT_MS);
    void release_restart(void);          // only legitimate after request_restart_and_wait returned true

    uint32_t status(void);
    static void describe_status(uint32_t s, char *buf, unsigned len);

  private:
    teaching_regs *regs;
    teaching_tsi *tsi;
    teaching_blk *bdev;
    bool ready_seen;

  protected:
    uint32_t read(int off);
    void write(int off, uint32_t word);
    struct blkdev_request read_blkdev_request();
    struct blkdev_data read_blkdev_req_data();
    void write_blkdev_response(struct blkdev_data &resp);
};

#endif
