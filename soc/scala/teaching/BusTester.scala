// M1-b: CPU-independent transaction tester for PHYSICAL_PORT_V1, with a byte-lane scoreboard.
// Phases: init (fill every RAM word so no read ever sees uninitialised memory)
//      -> directed (every size x every legal offset, write then read back)
//      -> random (LFSR size/offset/partial mask, random gaps and response back-pressure)
//      -> error region (read and write to the error slave: error expected, TL traffic expected)
//      -> illegal (mask 0 / mask outside range / misaligned / unmapped: error expected, NO TL traffic).
package teaching

import chisel3._
import chisel3.util._

// smallBase names a manager that is mapped but cannot serve some requests. In the unit configuration that is a
// read-only 8-byte-only device (both the write and the 1-byte read are rejected locally). In the SoC
// configuration it is the BootROM, which is mapped and read-only: the write is rejected locally, while a
// 1-byte read is perfectly legal there -- narrowReadUnsupported says which of the two applies.
class BusTester(ramBase: Long, ramWords: Int, errBase: Long, unmappedBase: Long, smallBase: Long,
                nRandom: Int, gapMask: Int, respMask: Int, seed: Int,
                narrowReadUnsupported: Boolean = true) extends Module {
  val io = IO(new Bundle {
    val phys     = new PhysPortIO
    val dbg      = Flipped(new BridgeDebug)
    val finished = Output(Bool())
    val failed   = Output(Bool())
  })
  val wordBits = log2Ceil(ramWords)
  val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
  val lf  = RegInit(seed.U(32.W)); lf := Cat(lf(30, 0), lf(31) ^ lf(21) ^ lf(1) ^ lf(0))

  val shadow = Mem(ramWords, UInt(64.W))
  def wordIdx(a: UInt) = (a - ramBase.U)(wordBits + 2, 3)

  val sInit :: sDirW :: sDirR :: sRndW :: sRndR :: sErrR :: sErrW :: sIll :: sDone :: Nil = Enum(9)
  val phase = RegInit(sInit)
  val idx   = RegInit(0.U(16.W))
  val busy  = RegInit(false.B); val offering = RegInit(false.B); val gap = RegInit(0.U(8.W))
  val errors = RegInit(0.U(16.W)); val issued = RegInit(0.U(16.W)); val responses = RegInit(0.U(16.W))
  val covSize = RegInit(VecInit(Seq.fill(4)(0.U(16.W))))
  val covPartial = RegInit(0.U(16.W)); val covReadback = RegInit(0.U(16.W)); val covErr = RegInit(0.U(16.W))
  val covIllegal = RegInit(0.U(16.W)); val covBp = RegInit(0.U(16.W)); val covReqWait = RegInit(0.U(16.W))

  val cur = Reg(new PhysReq)
  val expData = Reg(UInt(64.W)); val expErr = Reg(Bool()); val expNoTL = Reg(Bool()); val skipDataCheck = Reg(Bool())
  val aAtIssue = Reg(UInt(32.W)); val dAtIssue = Reg(UInt(32.W))

  // ---------------- next transaction ----------------
  val nDirected = 32                          // idx(4,3) = size, idx(2,0) = byte offset
  val dSize = idx(4, 3); val dOff = idx(2, 0); val dOk = PhysPort.aligned(dSize, dOff)
  val rSize = lf(1, 0)
  val rOff  = MuxLookup(rSize, 0.U(3.W), Seq(
    0.U -> lf(4, 2), 1.U -> Cat(lf(4, 3), 0.U(1.W)), 2.U -> Cat(lf(4), 0.U(2.W)), 3.U -> 0.U(3.W)))
  val rWord = lf(11, 5)(wordBits - 1, 0)
  val pattern = Cat(lf(15, 0), cyc(15, 0), idx(7, 0), lf(31, 8))(63, 0)

  val nx = Wire(new PhysReq); nx := DontCare
  val nxErr = Wire(Bool()); nxErr := false.B
  val nxNoTL = Wire(Bool()); nxNoTL := false.B
  switch (phase) {
    is (sInit) { nx.addr := ramBase.U + Cat(idx(wordBits - 1, 0), 0.U(3.W)); nx.write := true.B; nx.size := 3.U
                 nx.wdata := Cat("hA5A5".U(16.W), idx(15, 0), "h5A5A".U(16.W), idx(15, 0)); nx.wmask := "hff".U }
    is (sDirW) { nx.addr := ramBase.U + Cat(dSize, 0.U(3.W)) + dOff; nx.write := true.B; nx.size := dSize
                 nx.wdata := pattern; nx.wmask := PhysPort.laneMask(dSize, dOff) }
    is (sDirR) { nx.addr := cur.addr; nx.write := false.B; nx.size := cur.size; nx.wdata := 0.U; nx.wmask := 0.U }
    is (sRndW) { nx.addr := ramBase.U + Cat(rWord, 0.U(3.W)) + rOff; nx.write := true.B; nx.size := rSize; nx.wdata := pattern
                 val full = PhysPort.laneMask(rSize, rOff); val sub = full & lf(23, 16)
                 nx.wmask := Mux(sub === 0.U, full, sub) }
    is (sRndR) { nx.addr := cur.addr; nx.write := false.B; nx.size := cur.size; nx.wdata := 0.U; nx.wmask := 0.U }
    is (sErrR) { nx.addr := errBase.U; nx.write := false.B; nx.size := 3.U; nx.wdata := 0.U; nx.wmask := 0.U; nxErr := true.B }
    is (sErrW) { nx.addr := errBase.U + 8.U; nx.write := true.B; nx.size := 2.U; nx.wdata := pattern; nx.wmask := "h0f".U; nxErr := true.B }
    is (sIll)  { nx.write := true.B; nx.wdata := pattern; nxErr := true.B; nxNoTL := true.B
                 switch (idx(2, 0)) {
                   is (0.U) { nx.addr := ramBase.U + 16.U;     nx.size := 2.U; nx.wmask := 0.U }        // zero mask
                   is (1.U) { nx.addr := ramBase.U + 16.U;     nx.size := 1.U; nx.wmask := "h0c".U }    // mask outside the size window
                   is (2.U) { nx.addr := ramBase.U + 17.U;     nx.size := 2.U; nx.wmask := "h1e".U }    // misaligned 4-byte
                   is (3.U) { nx.addr := ramBase.U + 21.U;     nx.size := 3.U; nx.wmask := "hff".U }    // misaligned 8-byte
                   is (4.U) { nx.addr := unmappedBase.U;       nx.size := 3.U; nx.wmask := "hff".U }    // unmapped write
                   is (5.U) { nx.addr := unmappedBase.U + 8.U; nx.size := 3.U; nx.wmask := 0.U; nx.write := false.B } // unmapped read
                   is (6.U) { nx.addr := smallBase.U;          nx.size := 3.U; nx.wmask := "hff".U }    // mapped, but this manager serves no writes
                   is (7.U) { nx.addr := smallBase.U + 8.U;    nx.size := 0.U; nx.wmask := 0.U; nx.write := false.B; nxNoTL := narrowReadUnsupported.B; nxErr := narrowReadUnsupported.B }
                 } }
  }
  val skip = phase === sDirW && !dOk

  // ---------------- issue ----------------
  io.phys.req.valid := offering
  io.phys.req.bits  := cur
  when (!busy && !offering && gap === 0.U && phase =/= sDone) {
    when (skip) { idx := idx + 1.U; when (idx >= (nDirected - 1).U) { idx := 0.U; phase := sRndW } } .otherwise {
      cur := nx; expErr := nxErr; expNoTL := nxNoTL; offering := true.B
      skipDataCheck := (phase === sIll) && !nxErr          // a legal access to the mapped read-only device
      aAtIssue := io.dbg.aFires; dAtIssue := io.dbg.dFires
      val w = wordIdx(nx.addr)
      expData := Mux(nx.write || nxErr, 0.U, shadow(w) & FillInterleaved(8, PhysPort.laneMask(nx.size, nx.addr(2, 0))))
    }
  }
  when (io.phys.req.valid && !io.phys.req.ready) { covReqWait := covReqWait + 1.U }
  when (io.phys.req.fire()) {
    offering := false.B; busy := true.B; issued := issued + 1.U
    covSize(cur.size) := covSize(cur.size) + 1.U
    when (cur.write && !expErr) {
      val w = wordIdx(cur.addr); val lanes = FillInterleaved(8, cur.wmask)
      shadow(w) := (shadow(w) & (~lanes).asUInt) | (cur.wdata & lanes)
      when (cur.wmask =/= PhysPort.laneMask(cur.size, cur.addr(2, 0))) { covPartial := covPartial + 1.U }
    }
  }

  // ---------------- response ----------------
  io.phys.resp.ready := (respMask.U(8.W) >> cyc(2, 0))(0)
  when (io.phys.resp.valid && !io.phys.resp.ready) { covBp := covBp + 1.U }
  // "valid && !ready last cycle" obliges the producer to still assert valid this cycle with the same payload,
  // including the cycle the handshake finally happens. Deriving the check from the previous cycle (rather than
  // from this cycle's valid) is what catches a withdrawal; checking only while valid is still high misses it.
  val pPending = RegNext(io.phys.resp.valid && !io.phys.resp.ready, false.B)
  val pBits    = RegNext(io.phys.resp.bits.asUInt())
  val pFire    = RegNext(io.phys.resp.fire(), false.B)
  when (pPending && !io.phys.resp.valid) {
    errors := errors + 1.U; printf(p"TB ERR response valid withdrawn before the handshake cyc=$cyc\n") }
  when (pPending && io.phys.resp.valid && io.phys.resp.bits.asUInt() =/= pBits) {
    errors := errors + 1.U; printf(p"TB ERR response payload changed while waiting cyc=$cyc\n") }
  when (io.phys.resp.valid && io.phys.req.fire()) {
    errors := errors + 1.U; printf(p"TB ERR response asserted in the request handshake cycle cyc=$cyc\n") }
  when (io.phys.resp.fire() && io.phys.req.fire()) {
    errors := errors + 1.U; printf(p"TB ERR a new request was accepted in the response handshake cycle cyc=$cyc\n") }
  when (io.phys.resp.valid && !busy) {
    errors := errors + 1.U; printf(p"TB ERR response with nothing outstanding cyc=$cyc\n") }

  when (io.phys.resp.fire() && busy) {
    responses := responses + 1.U; busy := false.B; gap := (gapMask.U(8.W) & lf(7, 0))
    val r = io.phys.resp.bits
    when (r.error =/= expErr) { errors := errors + 1.U
      printf(p"TB ERR error=${r.error} expected=$expErr addr=0x${Hexadecimal(cur.addr)} size=${cur.size} write=${cur.write} phase=$phase cyc=$cyc\n") }
    when (!expErr && !cur.write && !skipDataCheck && r.rdata =/= expData) { errors := errors + 1.U
      printf(p"TB ERR data=0x${Hexadecimal(r.rdata)} expected=0x${Hexadecimal(expData)} addr=0x${Hexadecimal(cur.addr)} size=${cur.size} mask=0x${Hexadecimal(PhysPort.laneMask(cur.size, cur.addr(2,0)))} cyc=$cyc\n") }
    when ((cur.write || expErr) && r.rdata =/= 0.U) { errors := errors + 1.U
      printf(p"TB ERR non-zero rdata on a write/error response cyc=$cyc\n") }
    when (expNoTL) {
      when (io.dbg.aFires =/= aAtIssue) { errors := errors + 1.U; printf(p"TB ERR locally illegal request reached TileLink cyc=$cyc\n") }
      when (io.dbg.dFires =/= dAtIssue) { errors := errors + 1.U; printf(p"TB ERR locally illegal request took a TL response cyc=$cyc\n") }
      covIllegal := covIllegal + 1.U
    } .otherwise {
      when (io.dbg.aFires =/= aAtIssue + 1.U) { errors := errors + 1.U
        printf(p"TB ERR expected one TL A handshake, delta=${io.dbg.aFires - aAtIssue} cyc=$cyc\n") }
      when (io.dbg.dFires =/= dAtIssue + 1.U) { errors := errors + 1.U
        printf(p"TB ERR response not backed by exactly one TL D handshake, delta=${io.dbg.dFires - dAtIssue} write=${cur.write} cyc=$cyc\n") }
      when (expErr) { covErr := covErr + 1.U }
      when (!cur.write) { covReadback := covReadback + 1.U }
    }
    switch (phase) {
      is (sInit) { idx := idx + 1.U; when (idx >= (ramWords - 1).U) { idx := 0.U; phase := sDirW } }
      is (sDirW) { phase := sDirR }
      is (sDirR) { idx := idx + 1.U; when (idx >= (nDirected - 1).U) { idx := 0.U; phase := sRndW } .otherwise { phase := sDirW } }
      is (sRndW) { phase := sRndR }
      is (sRndR) { idx := idx + 1.U; when (idx >= (nRandom - 1).U) { idx := 0.U; phase := sErrR } .otherwise { phase := sRndW } }
      is (sErrR) { phase := sErrW }
      is (sErrW) { idx := 0.U; phase := sIll }
      is (sIll)  { idx := idx + 1.U; when (idx >= 7.U) { phase := sDone } }
    }
  }
  when (gap =/= 0.U) { gap := gap - 1.U }
  val waitCnt = RegInit(0.U(16.W))
  when (busy) { waitCnt := waitCnt + 1.U } .otherwise { waitCnt := 0.U }
  when (busy && waitCnt === 4000.U) { errors := errors + 1.U; printf(p"TB ERR response timeout cyc=$cyc\n"); busy := false.B; phase := sDone }

  val done = phase === sDone && !busy && !offering
  val doneCnt = RegInit(0.U(3.W)); when (done) { doneCnt := doneCnt + 1.U }
  io.finished := doneCnt === 4.U
  io.failed   := errors =/= 0.U || issued =/= responses
  when (doneCnt === 3.U) {
    printf(p"BUSTB issued=$issued responses=$responses errors=$errors covSize0=${covSize(0)} covSize1=${covSize(1)} covSize2=${covSize(2)} covSize3=${covSize(3)} covPartial=$covPartial covReadback=$covReadback covErr=$covErr covIllegal=$covIllegal covBp=$covBp covReqWait=$covReqWait covAWait=${io.dbg.aWaits} covSameCyc=${io.dbg.sameCyc} aFires=${io.dbg.aFires} dFires=${io.dbg.dFires} tlErrors=${io.dbg.tlErrors} bridgeIllegal=${io.dbg.illegal}\n")
    when (io.failed) { printf(p"TB RESULT FAIL\n") } .otherwise { printf(p"TB RESULT PASS\n") }
  }
}
