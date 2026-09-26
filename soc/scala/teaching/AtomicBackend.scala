// CPU-A stage 1: the atomic / reservation backend -- a TileLink adapter placed on the DRAM path after every
// PL master has merged, so an AMO is serialised against the CPU, the TSI adapter and the block-device DMA
// alike. Strictly serial: one transaction of any kind at a time. Design: cpu-atomic-backend/DESIGN.md §2.
//
// Not rocket-chip's TLAtomicAutomata (which keeps going after a read error and only ORs the error at the end):
// here a Get that returns an error ends the AMO with one error response and no Put (CODEX_DECISIONS.md, 1).
//
// MC-M2a: N harts. Each hart is a CLIENT NAMED EXPLICITLY (cpuClientNames(h)), resolved on the inner edge by
// exact name at elaboration -- never by prefix, never by sorting source ranges (MC-M0 ruling D4). Per hart: a
// depth-1 mark queue, one LR/SC reservation, its own side-band slot (mark in, scResult out, resvClear in).
// The reservation rules are CONTRACT C5.2 (ruling D3): a hart's own write clears its reservation; ANOTHER
// hart's write -- including a SUCCESSFUL SC, which is a write -- clears every reservation it overlaps; an
// external (non-CPU) write clears every reservation it overlaps; a failed SC writes nothing and clears only
// its own hart's reservation; a hart's resvClear (trap / core reset) clears only its own; the module reset
// clears all. The backend stays globally serial; nothing here changes the response latency contract.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._

class AtomicBackendDebug extends Bundle {
  val state     = Output(UInt(4.W))
  val resvValid = Output(Bool())          // hart 0's, for the single-hart tests that read it
  val resvWord  = Output(UInt(29.W))
  val nAmo      = Output(UInt(32.W))
  val nScOk     = Output(UInt(32.W))
  val nScFail   = Output(UInt(32.W))
  val nKill     = Output(UInt(32.W))
  val busy      = Output(Bool())
}

// faultReadErrWrites: the rocket-chip behaviour -- a read error still issues the Put (negative control)
// faultNoKill:        an EXTERNAL write does not clear a reservation it overlaps (negative control)
// faultWrongSource:   hart 0 is identified by a hard-coded source (the wrong one) instead of by client name
// MC-M2a negatives (each one defect, each detectable only by a checker that binds requests to harts):
// faultNoCrossKill:   another HART's write does not clear the reservations it overlaps
// faultSwapSideband:  hart h's side-band is wired to slot h^1 (marks, scResult and resvClear all misbound)
// faultSwapDSource:   a synthesised D (AMO result, failed SC) is sent with the OTHER hart's source id
// faultAmoInterleave: between an AMO's Get and its Put, one plain single-beat Put from another source is let
//                     through and completed (the atomic pair is no longer atomic)
class AtomicBackend(faultReadErrWrites: Boolean = false, faultNoKill: Boolean = false,
                    faultWrongSource: Boolean = false, cpuClientNames: Seq[String] = Seq("teaching-phys"),
                    dramRegion: Seq[AddressSet] = Seq(AddressSet(0x80000000L, 0x0FFFFFFFL)),
                    // NOTE on how these are gated: use `if (trace)`, a Scala conditional, and never
                    // `when (trace.B)`. The Chisel form still elaborates the printf with a constant-false
                    // condition, so twelve $fwrite calls survived into a board netlist that is meant to
                    // have none. A printf inside an enclosing `when` is already emitted under that
                    // condition, so the two forms are identical at run time and differ only in whether the
                    // logic exists at all.
                    trace: Boolean = true,
                    faultNoCrossKill: Boolean = false, faultSwapSideband: Boolean = false,
                    faultSwapDSource: Boolean = false, faultAmoInterleave: Boolean = false)
                   (implicit p: Parameters) extends LazyModule {
  require(cpuClientNames.nonEmpty && cpuClientNames.distinct.size == cpuClientNames.size,
          s"AtomicBackend: hart client names must be non-empty and unique, got $cpuClientNames")
  val numHarts = cpuClientNames.size
  val atomicSizes = TransferSizes(4, 8)
  // atomics are added only to managers that lie entirely inside the declared DRAM window and can do Get+PutFull
  val node = TLAdapterNode(
    clientFn  = { cp => cp },
    managerFn = { mp => mp.copy(managers = mp.managers.map { m =>
      val inDram = m.address.forall(a => dramRegion.exists(d => d.contains(a)))
      val can = inDram && m.supportsGet.contains(atomicSizes) && m.supportsPutFull.contains(atomicSizes)
      if (can) m.copy(supportsArithmetic = atomicSizes, supportsLogical = atomicSizes) else m }) })

  lazy val module = new LazyModuleImp(this) {
    val n = numHarts
    val io = IO(new Bundle {
      val sb  = Flipped(Vec(n, new AtomicSideband))    // slot h belongs to hart h
      val dbg = new AtomicBackendDebug
    })
    val (in, edgeIn)   = node.in(0)
    val (out, edgeOut) = node.out(0)
    require(edgeIn.bundle.dataBits == 64, "AtomicBackend: 64-bit beats only")
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U

    // ---- who is which hart: by EXACT client name, checked at elaboration ----------------------------------
    val clients = edgeIn.client.clients
    val cpus = cpuClientNames.map { nm =>
      val cs = clients.filter(_.name == nm)
      require(cs.size == 1, s"AtomicBackend: client '$nm' must resolve to exactly one client on the inner edge, " +
              s"found ${cs.size}; clients = ${clients.map(_.name).mkString(",")}")
      cs.head
    }
    val strays = clients.filter(c => c.name.startsWith("teaching-phys") && !cpuClientNames.contains(c.name))
    require(strays.isEmpty, s"AtomicBackend: hart-like clients present but not bound: ${strays.map(_.name).mkString(",")}")
    for (i <- 0 until n; j <- 0 until n if i < j) {
      val a = cpus(i).sourceId; val b = cpus(j).sourceId
      require(a.end <= b.start || b.end <= a.start,
              s"AtomicBackend: source ranges of '${cpuClientNames(i)}' $a and '${cpuClientNames(j)}' $b overlap")
    }
    val loS = cpus.map(_.sourceId.start); val hiS = cpus.map(_.sourceId.end)
    // the negative control: hart 0 identified by a range nobody owns
    val lo = loS.zipWithIndex.map { case (l, h) => if (faultWrongSource && h == 0) hiS(0) + 1 else l }
    val hi = hiS.zipWithIndex.map { case (u, h) => if (faultWrongSource && h == 0) hiS(0) + 2 else u }
    val started = RegInit(false.B)
    when (!started) {
      started := true.B
      if (trace) for (h <- 0 until n) printf(p"AT ${cyc} CPU_SOURCE hart=${h.U} lo=${loS(h).U} hi=${hiS(h).U} clients=${clients.size.U} harts=${n.U}\n")
    }
    def hartHit(s: UInt): Vec[Bool] = VecInit((0 until n).map(h => (s >= lo(h).U) && (s < hi(h).U)))
    // side-band slot for hart h (the negative control misbinds it)
    def slot(h: Int): Int = if (faultSwapSideband && n > 1) h ^ 1 else h

    // ---- per-hart mark queues (depth 1: each hart has one transaction outstanding) ------------------------
    // The bridge pushes the mark when it accepts the CPU's request, at least one cycle before it offers the A,
    // so a registered queue is enough (a flow-through queue would tie the backend's decision to the bridge's A
    // handshake and, through the manager's ready, form a combinational loop).
    val markQ = Seq.tabulate(n) { h =>
      val q = Module(new Queue(new AtomicMark, 1))
      q.io.enq.valid := io.sb(slot(h)).mark.valid
      q.io.enq.bits  := io.sb(slot(h)).mark.bits
      assert(!(io.sb(slot(h)).mark.valid && !q.io.enq.ready), s"AtomicBackend: hart $h mark pushed while one is pending")
      q
    }

    // ---- state ------------------------------------------------------------------------------------------
    val sIdle :: sPass :: sPassD :: sGet :: sGetD :: sPut :: sPutD :: sResp :: sScFail :: sSneak :: sSneakD :: Nil = Enum(11)
    val state = RegInit(sIdle)
    val req     = Reg(new TLBundleA(edgeIn.bundle))
    val curHart = Reg(UInt(log2Ceil(n max 2).W))         // the hart of the transaction in progress (if a CPU's)
    val curIsCpu = RegInit(false.B)
    val kindLR  = RegInit(false.B); val kindSC = RegInit(false.B); val kindAMO = RegInit(false.B)
    val oldData = Reg(UInt(64.W)); val errAcc = RegInit(false.B)
    val nAmo = RegInit(0.U(32.W)); val nScOk = RegInit(0.U(32.W)); val nScFail = RegInit(0.U(32.W)); val nKill = RegInit(0.U(32.W))

    val resvValid = RegInit(VecInit(Seq.fill(n)(false.B)))
    val resvWord  = Reg(Vec(n, UInt(29.W)))
    def killResv(h: Int, why: String): Unit = {
      when (resvValid(h)) {
        if (trace) { printf(p"AT ${cyc} RESV kill hart=${h.U} word=0x${Hexadecimal(Cat(resvWord(h), 0.U(3.W)))} why=$why\n") }
        nKill := nKill + 1.U
      }
      resvValid(h) := false.B
    }

    // ---- classify the A offered by the inner side -------------------------------------------------------
    val a = in.a.bits
    val aHit     = hartHit(a.source)
    val aIsCpu   = aHit.asUInt.orR
    val aHart    = OHToUInt(aHit)
    val aIsAmo   = a.opcode === TLMessages.ArithmeticData || a.opcode === TLMessages.LogicalData
    val aIsPut   = a.opcode === TLMessages.PutFullData || a.opcode === TLMessages.PutPartialData
    val aIsGet   = a.opcode === TLMessages.Get
    val aWrites  = aIsAmo || aIsPut
    val aMarkV   = VecInit((0 until n).map(h => markQ(h).io.deq.valid))
    val aMarkB   = VecInit((0 until n).map(h => markQ(h).io.deq.bits))
    val aMark    = aIsCpu && aMarkV(aHart)
    val aIsLR    = aMark && aMarkB(aHart).lr && aIsGet
    val aIsSC    = aMark && aMarkB(aHart).sc && aIsPut
    assert(!(in.a.valid && aMark && !(aIsLR || aIsSC)),
           "AtomicBackend: a marked CPU transaction is neither an LR Get nor an SC Put")
    val aFirst = edgeIn.first(in.a); val aLast = edgeIn.last(in.a)
    // byte range of the offered A (single or multi-beat: size covers the whole transfer)
    val aLo = a.address; val aHi = a.address + (1.U << a.size)
    val overlaps = VecInit((0 until n).map { h =>
      val wLo = Cat(resvWord(h), 0.U(3.W)); val wHi = wLo + 8.U
      (aLo < wHi) && (aHi > wLo) })

    // accept one transaction at a time; a multi-beat Put streams its beats in sPass
    val acceptNew = state === sIdle
    // an AMO or an SC is accepted without being forwarded (the backend issues its own downstream transactions);
    // a plain transfer streams through and needs the outward ready; during an SC's own forward no inner beat
    // may be taken
    in.a.ready := Mux(acceptNew, Mux(aIsAmo || aIsSC, true.B, out.a.ready), (state === sPass) && !kindSC && out.a.ready)
    for (h <- 0 until n) markQ(h).io.deq.ready := in.a.fire() && aFirst && acceptNew && aMark && (aHart === h.U)

    // ---- reservation events on acceptance ----------------------------------------------------------------
    when (in.a.fire() && aFirst && acceptNew) {
      if (trace) printf(p"AT ${cyc} A_ACC src=${a.source} cpu=${aIsCpu} hart=${Mux(aIsCpu, aHart, 255.U)} op=${a.opcode} param=${a.param} addr=0x${Hexadecimal(a.address)} size=${a.size} " +
             p"data=0x${Hexadecimal(a.data)} mask=0x${Hexadecimal(a.mask)} kind=${Mux(aIsLR, 1.U, Mux(aIsSC, 2.U, Mux(aIsAmo, 3.U, 0.U)))}\n")
      when (aIsLR) {
        for (h <- 0 until n) when (aHart === h.U) {
          resvValid(h) := true.B; resvWord(h) := a.address(31, 3)
          if (trace) printf(p"AT ${cyc} RESV set hart=${h.U} word=0x${Hexadecimal(Cat(a.address(31, 3), 0.U(3.W)))}\n")
        }
      } .elsewhen (aIsSC) {
        // consumed whatever happens; the success decision, and the kills a successful SC causes, are below
      } .elsewhen (aWrites) {
        for (h <- 0 until n) when (resvValid(h) && overlaps(h)) {
          when (aIsCpu && aHart === h.U)        { killResv(h, "cpu-write") }
          .elsewhen (aIsCpu)                    { if (!faultNoCrossKill) killResv(h, "other-hart-write") }
          .otherwise                            { if (!faultNoKill) killResv(h, "external-write") }
        }
      }
    }
    // beats of a multi-beat transfer after the first: the range was already covered by the first beat's size
    when (in.a.fire() && !aFirst) { if (trace) { printf(p"AT ${cyc} A_BEAT src=${a.source} addr=0x${Hexadecimal(a.address)} data=0x${Hexadecimal(a.data)} mask=0x${Hexadecimal(a.mask)}\n") } }
    for (h <- 0 until n) when (io.sb(slot(h)).resvClear) { killResv(h, "core-clear") }

    // ---- the AMO ALU ------------------------------------------------------------------------------------------
    val shift  = Cat(req.address(2, 0), 0.U(3.W))
    val is32   = req.size === 2.U
    val oldLane = (oldData >> shift)(63, 0)
    val opdLane = (req.data >> shift)(63, 0)
    val oldV = Mux(is32, oldLane(31, 0).asSInt.pad(64).asUInt, oldLane)   // sign-extended views for signed compare
    val opdV = Mux(is32, opdLane(31, 0).asSInt.pad(64).asUInt, opdLane)
    val oldU = Mux(is32, oldLane(31, 0).pad(64), oldLane)
    val opdU = Mux(is32, opdLane(31, 0).pad(64), opdLane)
    val isArith = req.opcode === TLMessages.ArithmeticData
    val prm = req.param
    val resArith = MuxLookup(prm, oldU, Seq(
      TLAtomics.MIN  -> Mux(oldV.asSInt < opdV.asSInt, oldU, opdU),
      TLAtomics.MAX  -> Mux(oldV.asSInt > opdV.asSInt, oldU, opdU),
      TLAtomics.MINU -> Mux(oldU < opdU, oldU, opdU),
      TLAtomics.MAXU -> Mux(oldU > opdU, oldU, opdU),
      TLAtomics.ADD  -> (oldU + opdU)))
    val resLogic = MuxLookup(prm, oldU, Seq(
      TLAtomics.XOR  -> (oldU ^ opdU), TLAtomics.OR -> (oldU | opdU), TLAtomics.AND -> (oldU & opdU), TLAtomics.SWAP -> opdU))
    val res = Mux(isArith, resArith, resLogic)
    val laneBits = Mux(is32, "hFFFFFFFF".U(64.W), "hFFFFFFFFFFFFFFFF".U(64.W)) << shift
    val newData = ((oldData & (~laneBits).asUInt) | ((res << shift)(63, 0) & laneBits))(63, 0)

    // ---- outward A ----------------------------------------------------------------------------------------------
    val (_, getBits) = edgeOut.Get(req.source, req.address, req.size)
    val (_, putBits) = edgeOut.Put(req.source, req.address, req.size, newData)
    out.a.valid := false.B; out.a.bits := in.a.bits
    when (state === sIdle)      { out.a.valid := in.a.valid && !aIsAmo && !aIsSC; out.a.bits := in.a.bits }   // plain / LR pass straight through
    when (state === sPass)      { out.a.valid := in.a.valid; out.a.bits := in.a.bits }
    when (state === sGet)       { out.a.valid := true.B; out.a.bits := getBits }
    when (state === sPut)       { out.a.valid := true.B; out.a.bits := putBits }
    // an SC that passes is forwarded from the latched request (its single beat) in sPass as well
    val scPassBits = Wire(new TLBundleA(edgeOut.bundle)); scPassBits := req

    // ---- the negative control that breaks atomicity: a plain Put slipped between the AMO's halves -------------
    val sneaked = RegInit(false.B)
    val sneakBits = Reg(new TLBundleA(edgeIn.bundle))
    if (faultAmoInterleave) {
      val canSneak = (state === sPut) && !sneaked && in.a.valid && aIsPut && aFirst && aLast && !aIsSC
      when (canSneak) { in.a.ready := out.a.ready; out.a.valid := true.B; out.a.bits := in.a.bits }
    }

    // ---- inward D: pass-through or synthesised --------------------------------------------------------------
    val dPass = state === sPass || state === sPassD || state === sIdle || state === sSneakD
    in.d.valid := false.B; in.d.bits := out.d.bits; out.d.ready := false.B
    when (dPass) { in.d.valid := out.d.valid; out.d.ready := in.d.ready }
    when (state === sGetD || state === sPutD) { out.d.ready := true.B }   // consumed internally
    // the source a synthesised response carries: the requester's, or (negative control) the other hart's
    val otherHartSrc = if (n > 1) Mux(curHart === 0.U, loS(1).U, loS(0).U) else req.source
    val respSrc = if (faultSwapDSource && n > 1) Mux(curIsCpu, otherHartSrc, req.source) else req.source
    when (state === sResp)   { in.d.valid := true.B; in.d.bits := edgeIn.AccessAck(respSrc, req.size, Mux(errAcc, 0.U, oldData), errAcc) }
    when (state === sScFail) { in.d.valid := true.B; in.d.bits := edgeIn.AccessAck(respSrc, req.size) }
    for (h <- 0 until n) { io.sb(slot(h)).scResult.valid := false.B; io.sb(slot(h)).scResult.bits := false.B }
    def scResultTo(h: UInt, fail: Bool): Unit = for (i <- 0 until n) when (h === i.U) { io.sb(slot(i)).scResult.valid := true.B; io.sb(slot(i)).scResult.bits := fail }

    // ---- the state machine ---------------------------------------------------------------------------------------
    val dLast = edgeOut.last(out.d)
    switch (state) {
      is (sIdle) {
        when (in.a.valid) {
          req := in.a.bits; kindLR := aIsLR; kindSC := aIsSC; kindAMO := aIsAmo; errAcc := false.B
          curHart := aHart; curIsCpu := aIsCpu; sneaked := false.B
          when (aIsAmo) {
            when (in.a.ready) { state := sGet; nAmo := nAmo + 1.U; if (trace) { printf(p"AT ${cyc} AMO_START hart=${Mux(aIsCpu, aHart, 255.U)}\n") } }   // accepted, not forwarded
          } .elsewhen (aIsSC) {
            when (in.a.ready) {
              val okV = VecInit((0 until n).map(h => resvValid(h) && (resvWord(h) === a.address(31, 3))))
              val ok = okV(aHart)
              for (h <- 0 until n) when (aHart === h.U) { resvValid(h) := false.B }
              when (ok) {
                state := sPass; nScOk := nScOk + 1.U
                if (trace) { printf(p"AT ${cyc} SC_OK hart=${aHart} word=0x${Hexadecimal(a.address)}\n") }
                // a successful SC is a write: it clears every OTHER hart's reservation it overlaps
                for (h <- 0 until n) when (aHart =/= h.U && resvValid(h) && overlaps(h)) { if (!faultNoCrossKill) killResv(h, "sc-write") }
              } .otherwise {
                state := sScFail; nScFail := nScFail + 1.U
                if (trace) { printf(p"AT ${cyc} SC_FAIL hart=${aHart} word=0x${Hexadecimal(a.address)} resv=${ok}\n") }
              }
            }
          } .elsewhen (in.a.fire()) {
            state := Mux(aLast, sPassD, sPass)
          }
        }
      }
      is (sPass) {           // remaining A beats of a multi-beat transfer, or the SC's own single Put
        when (kindSC) {
          out.a.valid := true.B; out.a.bits := scPassBits
          when (out.a.fire()) { state := sPassD }
        } .otherwise {
          when (in.a.fire() && aLast) { state := sPassD }
        }
      }
      is (sPassD) {
        when (out.d.fire() && dLast) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${out.d.bits.source} data=0x${Hexadecimal(out.d.bits.data)} err=${out.d.bits.error} kind=${Mux(kindLR, 1.U, Mux(kindSC, 2.U, 0.U))}\n")
          when (kindLR && out.d.bits.error) { for (h <- 0 until n) when (curHart === h.U) { killResv(h, "lr-error") } }
          when (kindSC) { scResultTo(curHart, false.B) }
          state := sIdle
        }
      }
      is (sGet)  { when (out.a.fire()) { state := sGetD; if (trace) { printf(p"AT ${cyc} AMO_GET addr=0x${Hexadecimal(req.address)}\n") } } }
      is (sGetD) {
        when (out.d.fire()) {
          assert(out.d.bits.opcode === TLMessages.AccessAckData, "AtomicBackend: the AMO's Get was not answered with data")
          oldData := out.d.bits.data; errAcc := out.d.bits.error
          when (out.d.bits.error && !faultReadErrWrites.B) { state := sResp; if (trace) { printf(p"AT ${cyc} AMO_READ_ERROR no-put\n") } }
          .otherwise { state := sPut }
        }
      }
      is (sPut)  {
        if (faultAmoInterleave) {
          when (!sneaked && in.a.fire() && aIsPut) {
            sneaked := true.B; sneakBits := in.a.bits; state := sSneakD
            if (trace) { printf(p"AT ${cyc} INTERLEAVE src=${a.source} addr=0x${Hexadecimal(a.address)}\n") }
          } .elsewhen (out.a.fire()) { state := sPutD; if (trace) { printf(p"AT ${cyc} AMO_PUT addr=0x${Hexadecimal(req.address)} data=0x${Hexadecimal(newData)}\n") } }
        } else {
          when (out.a.fire()) { state := sPutD; if (trace) { printf(p"AT ${cyc} AMO_PUT addr=0x${Hexadecimal(req.address)} data=0x${Hexadecimal(newData)}\n") } }
        }
      }
      is (sSneakD) {          // negative control only: the interloper's D goes back to it, then the AMO's Put resumes
        when (out.d.fire()) { state := sPut }
      }
      is (sPutD) {
        when (out.d.fire()) {
          assert(out.d.bits.opcode === TLMessages.AccessAck, "AtomicBackend: the AMO's Put was not answered with AccessAck")
          errAcc := errAcc || out.d.bits.error
          state := sResp
        }
      }
      is (sResp) {
        when (in.d.fire()) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${respSrc} data=0x${Hexadecimal(Mux(errAcc, 0.U, oldData))} err=${errAcc} kind=3\n")
          state := sIdle
        }
      }
      is (sScFail) {
        when (in.d.fire()) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${respSrc} data=0x0 err=0 kind=2 scfail=1\n")
          scResultTo(curHart, true.B)
          state := sIdle
        }
      }
    }
    // a Put that is not accepted by the manager (a stuck a.ready) keeps its beat offered: TileLink irrevocability
    // is preserved by driving out.a from the *same* inner beat / latched request every cycle.
    in.b.valid := false.B; in.c.ready := true.B; in.e.ready := true.B
    out.b.ready := true.B; out.c.valid := false.B; out.e.valid := false.B

    io.dbg.state := state; io.dbg.resvValid := resvValid(0); io.dbg.resvWord := resvWord(0)
    io.dbg.nAmo := nAmo; io.dbg.nScOk := nScOk; io.dbg.nScFail := nScFail; io.dbg.nKill := nKill
    io.dbg.busy := state =/= sIdle
  }
}
