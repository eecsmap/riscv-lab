#include "teaching_driver.h"
#include "blkdev.h"

#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define ZYNQ_BASE_PADDR 0x43C00000L

#define TSI_OUT_FIFO_DATA 0x00
#define TSI_OUT_FIFO_COUNT 0x04
#define TSI_IN_FIFO_DATA 0x08
#define TSI_IN_FIFO_COUNT 0x0C
#define SYSTEM_RESET 0x10
#define BLKDEV_REQ_FIFO_DATA 0x20
#define BLKDEV_REQ_FIFO_COUNT 0x24
#define BLKDEV_DATA_FIFO_DATA 0x28
#define BLKDEV_DATA_FIFO_COUNT 0x2C
#define BLKDEV_RESP_FIFO_DATA 0x30
#define BLKDEV_RESP_FIFO_COUNT 0x34
#define BLKDEV_NSECTORS 0x38
#define BLKDEV_MAX_REQUEST_LENGTH 0x3C

#define BLKDEV_REQ_NWORDS 3
#define BLKDEV_DATA_NWORDS 3

static uint64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t) ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// The constructor maps the device and publishes the disk geometry. It deliberately does NOT touch
// SYSTEM_RESET: the restart handshake is an explicit, checkable step, not a side effect of construction.
teaching_driver_t::teaching_driver_t(teaching_regs *regs, teaching_tsi *tsi, teaching_blk *bdev)
{
    this->regs = regs;
    this->tsi = tsi;
    this->bdev = bdev;
    this->ready_seen = false;

    if (bdev == NULL) {
        write(BLKDEV_NSECTORS, 0);
        write(BLKDEV_MAX_REQUEST_LENGTH, 0);
    } else {
        write(BLKDEV_NSECTORS, bdev->nsectors());
        write(BLKDEV_MAX_REQUEST_LENGTH, bdev->max_request_length());
    }
}

teaching_driver_t::~teaching_driver_t() {}

uint32_t teaching_driver_t::read(int off)        { return regs->read(off); }
void teaching_driver_t::write(int off, uint32_t w) { regs->write(off, w); }

uint32_t teaching_driver_t::status(void) { return read(TEACHING_STATUS); }

void teaching_driver_t::describe_status(uint32_t s, char *buf, unsigned len)
{
    snprintf(buf, len,
             "status=0x%08x cpu_restart_safe=%d pl_reconfig_safe=%d draining=%d drain_timeout=%d "
             "boot_ready=%d boot_timeout=%d epoch=%u ndrained=%u",
             s,
             !!(s & TEACHING_ST_CPU_RESTART_SAFE), !!(s & TEACHING_ST_PL_RECONFIG_SAFE),
             !!(s & TEACHING_ST_DRAINING), !!(s & TEACHING_ST_DRAIN_TIMEOUT),
             !!(s & TEACHING_ST_BOOT_READY), !!(s & TEACHING_ST_BOOT_TIMEOUT),
             TEACHING_ST_EPOCH(s), TEACHING_ST_NDRAINED(s));
}

struct blkdev_request teaching_driver_t::read_blkdev_request()
{
    uint32_t word;
    struct blkdev_request req;

    word = read(BLKDEV_REQ_FIFO_DATA);
    req.write = word & 0x1;
    req.tag = word >> 1;
    req.offset = read(BLKDEV_REQ_FIFO_DATA);
    req.len = read(BLKDEV_REQ_FIFO_DATA);

    return req;
}

struct blkdev_data teaching_driver_t::read_blkdev_req_data()
{
    struct blkdev_data data;

    data.tag = read(BLKDEV_DATA_FIFO_DATA);
    data.data = read(BLKDEV_DATA_FIFO_DATA) & 0xffffffffU;
    data.data |= ((uint64_t) read(BLKDEV_DATA_FIFO_DATA)) << 32;

    return data;
}

void teaching_driver_t::write_blkdev_response(struct blkdev_data &resp)
{
    write(BLKDEV_RESP_FIFO_DATA, resp.tag);
    write(BLKDEV_RESP_FIFO_DATA, resp.data & 0xffffffffU);
    write(BLKDEV_RESP_FIFO_DATA, resp.data >> 32);
}

void teaching_driver_t::poll(PollMode mode)
{
    if (tsi != NULL) {
        // Draining the design's outgoing words is always safe and is necessary: a full TSI_OUT FIFO
        // backpressures the design and can stop it reaching the quiescent state we are waiting for.
        while (read(TSI_OUT_FIFO_COUNT) > 0) {
            uint32_t out_data = read(TSI_OUT_FIFO_DATA);
            tsi->send_word(out_data);
        }

        // Pushing words *in* is how a load begins. Withheld until readiness.
        if (mode == POLL_ALL) {
            while (tsi->data_available() && read(TSI_IN_FIFO_COUNT) > 0) {
                uint32_t in_data = tsi->recv_word();
                write(TSI_IN_FIFO_DATA, in_data);
            }
            tsi->switch_to_host();
        }
    }

    if (bdev != NULL) {
        while (read(BLKDEV_REQ_FIFO_COUNT) >= BLKDEV_REQ_NWORDS) {
            struct blkdev_request req = read_blkdev_request();
            bdev->send_request(req);
        }

        while (read(BLKDEV_DATA_FIFO_COUNT) >= BLKDEV_DATA_NWORDS) {
            struct blkdev_data data = read_blkdev_req_data();
            bdev->send_data(data);
        }

        while (bdev->resp_valid() && read(BLKDEV_RESP_FIFO_COUNT) >= BLKDEV_DATA_NWORDS) {
            struct blkdev_data resp = bdev->recv_response();
            write_blkdev_response(resp);
        }

        bdev->switch_to_host();
    }
}

bool teaching_driver_t::request_restart_and_wait(unsigned timeout_ms)
{
    char buf[256];

    // The request is data, not a reset: in RD2BoardTop it drives softReset, while the subsystem's own
    // reset stays cold-only. Holding it is what lets the design drain instead of being cut off mid-DMA.
    write(SYSTEM_RESET, 1);

    uint64_t start = now_ms();
    uint64_t deadline = start + timeout_ms;

    for (;;) {
        // Keep servicing what the device already accepted. Without this the drain cannot finish: a
        // transfer the block device took before the request still needs its data and its response, and the
        // host is the only thing that can supply them.
        // Drain-only: the block device is serviced in full, because a transfer it accepted before the
        // request still needs its data and its response and the host is the only thing that can supply
        // them. TSI input is withheld, so no new load can begin before readiness.
        poll(POLL_DRAIN_ONLY);

        uint32_t s = status();

        if (s & TEACHING_ST_BOOT_TIMEOUT) {
            describe_status(s, buf, sizeof(buf));
            fprintf(stderr, "teaching: the design reports it never drained; %s\n", buf);
            fprintf(stderr, "teaching: leaving the restart request asserted and loading nothing.\n");
            return false;
        }

        // The full readiness bit, not CPU_RESTART_SAFE: the CPU having taken its reset says nothing about
        // the block device's outstanding DMA, and the two are separate bits precisely because they differ.
        if (s & TEACHING_ST_BOOT_READY) {
            uint64_t held = now_ms() - start;
            if (held < TEACHING_HOLD_FLOOR_MS) {
                // The ready bit is the evidence; the hold floor is the accepted board operating condition.
                // Both are required, so wait out the remainder rather than releasing early -- but fall
                // through to the deadline check rather than `continue`, which skipped it. A timeout shorter
                // than the floor, or a readiness bit that flickers, must still be honoured.
                if (now_ms() < deadline) continue;
                describe_status(s, buf, sizeof(buf));
                fprintf(stderr, "teaching: readiness seen but the %u ms timeout expired inside the %d ms "
                                "hold floor; %s\n", timeout_ms, TEACHING_HOLD_FLOOR_MS, buf);
                fprintf(stderr, "teaching: leaving the restart request asserted and loading nothing.\n");
                return false;
            }
            ready_seen = true;
            describe_status(s, buf, sizeof(buf));
            fprintf(stderr, "teaching: ready after %llu ms; %s\n", (unsigned long long) held, buf);
            return true;
        }

        if (now_ms() >= deadline) {
            describe_status(s, buf, sizeof(buf));
            fprintf(stderr, "teaching: no boot readiness within %u ms; %s\n", timeout_ms, buf);
            fprintf(stderr, "teaching: leaving the restart request asserted and loading nothing.\n");
            return false;
        }
    }
}

void teaching_driver_t::release_restart(void)
{
    // Releasing without having seen readiness is the exact mistake this host exists to prevent.
    assert(ready_seen);
    write(SYSTEM_RESET, 0);
}

