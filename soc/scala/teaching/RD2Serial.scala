// RD2-B: the serial (TSI) adapter as an isolated copy, with the drain contract applied to it.
//
// Derived from testchipip's SerialAdapter (which is left untouched). The state machine, the framing and the
// TileLink requests are the same, instruction for instruction; what is added is the part the SoC-level
// contract needs:
//
//   * d.ready is high whenever a D can legally arrive, so a beat that comes back when this master has
//     nothing outstanding is accepted and counted as an orphan instead of parking in the converter's single
//     D slot and blocking every other client. This is the same fault the CPU bridge had, and the serial
//     adapter is its second source: upstream, `mem.d.ready` is only high in s_write_ack / s_read_data.
//   * an admission gate: while `quiesceReq` is held, no *new* TSI command is accepted, but a command
//     already in progress runs to completion -- including its serial.out beats and the responses to
//     requests it has already issued. Refusing input must never be the reason a completion cannot arrive.
//   * `pendingWork`, so the SoC can tell whether this master is finished, and counters for the checker.
//
// There is deliberately no soft reset here. A CPU restart must not disturb TSI: fesvr loads the ELF while
// the CPU is held, and a half-assembled frame whose other half is still in the adapter's cold-domain FIFO
// would desynchronise the host. So this master's state is cold-domain only, and a write it has already put
// on the A channel completes exactly once -- it is never replayed, because nothing clears it.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.subsystem.BaseSubsystem
import freechips.rocketchip.util.UIntIsOneOf   // isOneOf, as testchipip gets it from rocketchip.util._
import testchipip.{SerialIO, TLHelper}
import testchipip.SerialAdapter.SERIAL_IF_WIDTH

class RD2SerialStatus extends Bundle {
  val pendingWork  = Output(Bool())   // a frame is being assembled, or a TL transaction is in flight
  val frameActive  = Output(Bool())   // mid-frame: the host is part-way through a command
  val tlOutstanding = Output(Bool())  // an A has been offered or accepted and its D has not come back
  val nCmds        = Output(UInt(32.W))
  val nWrites      = Output(UInt(32.W))
  val nOrphan      = Output(UInt(32.W))
  val nSameCyc     = Output(UInt(32.W))  // A and D in one cycle: measured, not assumed away
  val minLat       = Output(UInt(32.W))  // the smallest A-to-D gap this master actually saw
  // cycles, not commands: one per cycle in which a new command was offered and held off by the lock
  val nRefusedCycles = Output(UInt(32.W))
}

class RD2SerialAdapter(implicit p: Parameters) extends LazyModule {
  val node = TLHelper.makeClientNode(name = "rd2-serial", sourceId = IdRange(0, 1))
  lazy val module = new RD2SerialAdapterModule(this)
}

class RD2SerialAdapterModule(outer: RD2SerialAdapter) extends LazyModuleImp(outer) {
  val w = SERIAL_IF_WIDTH
  val io = IO(new Bundle {
    val serial     = new SerialIO(w)
    val quiesceReq = Input(Bool())
    val status     = new RD2SerialStatus
  })

  val (mem, edge) = outer.node.out(0)

  val pAddrBits = edge.bundle.addressBits
  val wordLen = 64
  val nChunksPerWord = wordLen / w
  val dataBits = mem.params.dataBits
  val beatBytes = dataBits / 8
  val nChunksPerBeat = dataBits / w
  val byteAddrBits = log2Ceil(beatBytes)
  require(nChunksPerWord > 0, s"Serial interface width must be <= $wordLen")

  val cmd = Reg(UInt(w.W))
  val addr = Reg(UInt(wordLen.W))
  val len = Reg(UInt(wordLen.W))
  val body = Reg(Vec(nChunksPerBeat, UInt(w.W)))
  val bodyValid = Reg(UInt(nChunksPerBeat.W))
  val idx = Reg(UInt(log2Up(nChunksPerBeat).W))

  val (cmd_read :: cmd_write :: Nil) = Enum(2)
  val (s_cmd :: s_addr :: s_len ::
       s_read_req  :: s_read_data :: s_read_body ::
       s_write_body :: s_write_data :: s_write_ack :: Nil) = Enum(9)
  val state = RegInit(s_cmd)

  // ---- the admission gate ----------------------------------------------------------------------------
  // Only the *first* chunk of a new command is refused. Every other state carries a command that has
  // already been accepted, and those run to completion: the host is mid-frame and stopping there would
  // strand it, and any TL transaction already issued still has its D to collect.
  val newCommand = state === s_cmd
  val admit = !(io.quiesceReq && newCommand)
  io.serial.in.ready := state.isOneOf(s_cmd, s_addr, s_len, s_write_body) && admit
  io.serial.out.valid := state === s_read_body
  io.serial.out.bits := body(idx)

  val beatAddr = addr(pAddrBits - 1, byteAddrBits)
  val nextAddr = Cat(beatAddr + 1.U, 0.U(byteAddrBits.W))

  val wmask = FillInterleaved(w/8, bodyValid)
  val addr_size = nextAddr - addr
  val len_size = Cat(len + 1.U, 0.U(log2Ceil(w/8).W))
  val raw_size = Mux(len_size < addr_size, len_size, addr_size)
  val rsize = MuxLookup(raw_size, byteAddrBits.U,
    (0 until log2Ceil(beatBytes)).map(i => ((1 << i).U -> i.U)))

  val pow2size = PopCount(raw_size) === 1.U
  val byteAddr = Mux(pow2size, addr(byteAddrBits - 1, 0), 0.U)

  val put_acquire = edge.Put(
    0.U, beatAddr << byteAddrBits.U, log2Ceil(beatBytes).U, body.asUInt, wmask)._2
  val get_acquire = edge.Get(0.U, Cat(beatAddr, byteAddr), rsize)._2

  mem.a.valid := state.isOneOf(s_write_data, s_read_req)
  mem.a.bits := Mux(state === s_write_data, put_acquire, get_acquire)
  mem.b.ready := false.B
  mem.c.valid := false.B
  mem.e.valid := false.B

  // ---- D: always ready, orphans swallowed -------------------------------------------------------------
  // Legal TileLink (ready may be high at any time) and it costs nothing: in the two states that expect a
  // response the beat is used, and anywhere else it is a beat this master no longer has a home for, which
  // is counted and dropped rather than left to block the shared converter.
  // "Expecting a D" is the two wait states *and* the cycle the request is accepted, because a manager with
  // minLatency 0 may answer in that cycle and that beat is legitimate, not an orphan. Counting it as one
  // would put a false orphan in the diagnostics -- the counter is evidence, so it has to mean what it says.
  val expectingD = state.isOneOf(s_write_ack, s_read_data) ||
                   (state.isOneOf(s_read_req, s_write_data) && mem.a.ready)
  mem.d.ready := true.B
  val nOrphan = RegInit(0.U(32.W))
  when (mem.d.fire() && !expectingD) { nOrphan := nOrphan + 1.U }

  def shiftBits(bits: UInt, idx: UInt): UInt =
    if (nChunksPerWord > 1) bits << Cat(idx(log2Ceil(nChunksPerWord) - 1, 0), 0.U(log2Up(w).W)) else bits
  def addrToIdx(addr: UInt): UInt =
    if (nChunksPerBeat > 1) addr(byteAddrBits - 1, log2Up(w/8)) else 0.U

  val nCmds = RegInit(0.U(32.W))
  val nWrites = RegInit(0.U(32.W))
  val nRefused = RegInit(0.U(32.W))
  when (io.quiesceReq && newCommand && io.serial.in.valid) { nRefused := nRefused + 1.U }

  // ---- the state machine, unchanged except that the serial handshakes honour `admit` ------------------
  when (state === s_cmd && io.serial.in.valid && admit) {
    cmd := io.serial.in.bits
    idx := 0.U; addr := 0.U; len := 0.U
    nCmds := nCmds + 1.U
    state := s_addr
  }
  when (state === s_addr && io.serial.in.valid) {
    addr := addr | shiftBits(io.serial.in.bits, idx)
    idx := idx + 1.U
    when (idx === (nChunksPerWord - 1).U) { idx := 0.U; state := s_len }
  }
  when (state === s_len && io.serial.in.valid) {
    len := len | shiftBits(io.serial.in.bits, idx)
    idx := idx + 1.U
    when (idx === (nChunksPerWord - 1).U) {
      idx := addrToIdx(addr)
      when (cmd === cmd_write) { bodyValid := 0.U; state := s_write_body }
      .elsewhen (cmd === cmd_read) { state := s_read_req }
      .otherwise { assert(false.B, "RD2SerialAdapter: bad TSI command") }
    }
  }
  // A and D in the same cycle. The CPU bridge already handles this (a manager with minLatency 0 makes it
  // real there); whether the *serial* adapter can see it depends on the path to DRAM, so the case is handled
  // here and measured below rather than argued about. Without this, the beat would be accepted -- d.ready is
  // always high -- and then not recognised as data, because the old code only looks at D in the wait states.
  val aFire = mem.a.fire()
  val dFire = mem.d.fire()
  val nSameCyc = RegInit(0.U(32.W))
  val latCnt = RegInit(0.U(32.W))
  val minLat = RegInit(~0.U(32.W))
  when (io.status.tlOutstanding) { latCnt := latCnt + 1.U } .otherwise { latCnt := 0.U }
  when (dFire && expectingD) { when (latCnt < minLat) { minLat := latCnt } }
  when (aFire && dFire) { nSameCyc := nSameCyc + 1.U }

  when (state === s_read_req && aFire) {
    when (dFire) {                       // the response arrived in the cycle the request was accepted
      body := mem.d.bits.data.asTypeOf(body)
      idx := addrToIdx(addr)
      addr := nextAddr
      state := s_read_body
    } .otherwise { state := s_read_data }
  }
  when (state === s_read_data && mem.d.valid) {
    body := mem.d.bits.data.asTypeOf(body)
    idx := addrToIdx(addr)
    addr := nextAddr
    state := s_read_body
  }
  when (state === s_read_body && io.serial.out.ready) {
    idx := idx + 1.U
    len := len - 1.U
    when (len === 0.U) { state := s_cmd }
    .elsewhen (idx === (nChunksPerBeat - 1).U) { state := s_read_req }
  }
  when (state === s_write_body && io.serial.in.valid) {
    body(idx) := io.serial.in.bits
    bodyValid := bodyValid | UIntToOH(idx)
    when (idx === (nChunksPerBeat - 1).U || len === 0.U) { state := s_write_data }
    .otherwise { idx := idx + 1.U; len := len - 1.U }
  }
  when (state === s_write_data && aFire) {
    nWrites := nWrites + 1.U
    when (dFire) {                       // acknowledged in the same cycle: finish the beat here
      when (len === 0.U) { state := s_cmd }
      .otherwise { addr := nextAddr; len := len - 1.U; idx := 0.U; bodyValid := 0.U; state := s_write_body }
    } .otherwise { state := s_write_ack }
  }
  when (state === s_write_ack && mem.d.valid) {
    when (len === 0.U) { state := s_cmd }
    .otherwise { addr := nextAddr; len := len - 1.U; idx := 0.U; bodyValid := 0.U; state := s_write_body }
  }

  io.status.frameActive   := state =/= s_cmd
  io.status.tlOutstanding := state.isOneOf(s_read_req, s_read_data, s_write_data, s_write_ack)
  io.status.pendingWork   := io.status.frameActive || io.status.tlOutstanding
  io.status.nCmds    := nCmds
  io.status.nWrites  := nWrites
  io.status.nOrphan  := nOrphan
  io.status.nSameCyc := nSameCyc
  io.status.minLat   := minLat
  io.status.nRefusedCycles := nRefused
}

trait HasRD2Serial { this: BaseSubsystem =>
  val rd2serial = LazyModule(new RD2SerialAdapter)
  // the loader's writes are the bulk of what reaches memory early in a run; they are identified, not
  // exempted, so a watcher sits in this master's path too
  val serialWatch = LazyModule(new RD2Watch("tsi", trace = p(RD2Key).busInstrumentation))
  sbus.fromPort(Some("rd2-serial-adapter"))() := serialWatch.node := rd2serial.node
}

trait HasRD2SerialModuleImp extends LazyModuleImp {
  implicit val p: Parameters
  val outer: HasRD2Serial
  val serial = IO(new SerialIO(SERIAL_IF_WIDTH))
  val rd2adapter = outer.rd2serial.module
  serial.out <> Queue(rd2adapter.io.serial.out)
  rd2adapter.io.serial.in <> Queue(serial.in)
}
