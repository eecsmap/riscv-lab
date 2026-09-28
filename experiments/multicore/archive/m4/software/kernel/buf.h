struct buf {
  int valid; // has data been read from disk?
  int disk;  // does disk "own" buf?
  uint dev;
  uint blockno;
  struct sleeplock lock;
  uint refcnt;
  struct buf *prev; // LRU cache list
  struct buf *next;
  // Rocket port: data is a DMA target and MUST be 64-byte aligned.
  // testchipip's block device moves each 64-byte chunk with a single
  // edge.Put(lgSize = log2Ceil(cacheBlockBytes) = 6). TileLink requires a
  // 2^6-byte Put to be 64-byte aligned, but the RTL just advances req.addr by
  // 64 per burst and never checks, so with an unaligned destination the tail
  // of the transfer is silently never written -- the bytes are left untouched.
  //
  // Upstream's struct buf is 1112 bytes, so without this every buffer in
  // bcache sits at a different 64-byte phase and only *some* blocks come back
  // damaged, with varying amounts of tail missing. That is what made this look
  // like random file corruption. Aligning the field also rounds
  // sizeof(struct buf) up to a multiple of 64, keeping every element of the
  // bcache array aligned as well.
  uchar data[BSIZE] __attribute__((aligned(64)));
};
