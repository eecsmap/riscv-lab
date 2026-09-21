#include "teaching_real_ports.h"
#include <unistd.h>
#include <assert.h>

#define ZYNQ_BASE_PADDR 0x43C00000L

// ---------------------------------------------------------------- the real ports
// Thin wrappers. They add no behaviour: everything that decides anything is in the driver above, which is
// what the host test exercises.

#include "fesvr/tsi.h"
#include <sys/mman.h>
#include <fcntl.h>

teaching_mmap_regs::teaching_mmap_regs()
{
    fd = open("/dev/mem", O_RDWR|O_SYNC);
    assert(fd != -1);
    dev = (uint8_t *) mmap(0, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd,
                           ZYNQ_BASE_PADDR);
    assert(dev != MAP_FAILED);
}
teaching_mmap_regs::~teaching_mmap_regs()
{
    munmap(dev, sysconf(_SC_PAGESIZE));
    close(fd);
}
uint32_t teaching_mmap_regs::read(int off)
{
    volatile uint32_t *p = (volatile uint32_t *) (dev + off); return *p;
}
void teaching_mmap_regs::write(int off, uint32_t word)
{
    volatile uint32_t *p = (volatile uint32_t *) (dev + off); *p = word;
}

bool     teaching_real_tsi::data_available()   { return t->data_available(); }
uint32_t teaching_real_tsi::recv_word()        { return t->recv_word(); }
void     teaching_real_tsi::send_word(uint32_t w) { t->send_word(w); }
void     teaching_real_tsi::switch_to_host()   { t->switch_to_host(); }
bool     teaching_real_tsi::done()             { return t->done(); }
int      teaching_real_tsi::exit_code()        { return t->exit_code(); }

void teaching_real_blk::send_request(struct blkdev_request &r) { b->send_request(r); }
void teaching_real_blk::send_data(struct blkdev_data &d)       { b->send_data(d); }
bool teaching_real_blk::resp_valid()                           { return b->resp_valid(); }
struct blkdev_data teaching_real_blk::recv_response()          { return b->recv_response(); }
void teaching_real_blk::switch_to_host()                       { b->switch_to_host(); }
uint32_t teaching_real_blk::nsectors()                         { return b->nsectors(); }
uint32_t teaching_real_blk::max_request_length()               { return b->max_request_length(); }
