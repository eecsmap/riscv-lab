#ifndef __TEACHING_PORTS_H
#define __TEACHING_PORTS_H

// The three things the teaching host talks to, behind interfaces so that the host's own logic can be
// exercised without a board. The real implementations are thin wrappers over /dev/mem, fesvr's tsi_t and
// testchipip's BlockDevice and add no behaviour of their own; the test implementations are in
// teaching_host_test.cc.
//
// This exists because of a specific question that could not otherwise be answered: the restart wait must
// not begin a new ELF load, and "it does not" is only worth something if something counts the words that
// would have started one.

#include <stdint.h>

struct teaching_regs {
    virtual uint32_t read(int off) = 0;
    virtual void write(int off, uint32_t word) = 0;
    virtual ~teaching_regs() {}
};

struct teaching_tsi {
    virtual bool data_available() = 0;
    virtual uint32_t recv_word() = 0;          // host -> design: this is how a load begins
    virtual void send_word(uint32_t w) = 0;    // design -> host
    virtual void switch_to_host() = 0;
    virtual bool done() = 0;
    virtual int exit_code() = 0;
    virtual ~teaching_tsi() {}
};

struct blkdev_request;
struct blkdev_data;

struct teaching_blk {
    virtual void send_request(struct blkdev_request &req) = 0;
    virtual void send_data(struct blkdev_data &data) = 0;
    virtual bool resp_valid() = 0;
    virtual struct blkdev_data recv_response() = 0;
    virtual void switch_to_host() = 0;
    virtual uint32_t nsectors() = 0;
    virtual uint32_t max_request_length() = 0;
    virtual ~teaching_blk() {}
};

#endif
