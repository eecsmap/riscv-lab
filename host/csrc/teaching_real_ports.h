#ifndef __TEACHING_REAL_PORTS_H
#define __TEACHING_REAL_PORTS_H

// The production implementations of the three ports. Declared separately from the interfaces so that the
// host test can link the driver without fesvr or a /dev/mem mapping.

#include "teaching_ports.h"
#include "blkdev.h"

class tsi_t;

class teaching_mmap_regs : public teaching_regs {
  public:
    teaching_mmap_regs();
    ~teaching_mmap_regs();
    uint32_t read(int off);
    void write(int off, uint32_t word);
  private:
    uint8_t *dev;
    int fd;
};

class teaching_real_tsi : public teaching_tsi {
  public:
    teaching_real_tsi(tsi_t *t) : t(t) {}
    bool data_available(); uint32_t recv_word(); void send_word(uint32_t w);
    void switch_to_host(); bool done(); int exit_code();
  private:
    tsi_t *t;
};

class teaching_real_blk : public teaching_blk {
  public:
    teaching_real_blk(BlockDevice *b) : b(b) {}
    void send_request(struct blkdev_request &r); void send_data(struct blkdev_data &d);
    bool resp_valid(); struct blkdev_data recv_response(); void switch_to_host();
    uint32_t nsectors(); uint32_t max_request_length();
  private:
    BlockDevice *b;
};

#endif
