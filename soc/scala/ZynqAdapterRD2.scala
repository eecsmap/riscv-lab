// RD2: the PS-facing adapter with the two experimental registers, as an isolated copy.
//
// Why a copy rather than a feature gate inside ZynqAdapter.scala. The gate worked -- with it disabled no RD2
// logic elaborated and the generated netlist was identical net for net -- but the generated Verilog carries
// `// @[ZynqAdapter.scala <line>:<col>]` annotations, so *adding lines* to that file moves them and the
// board RTL's hash changes. The accepted evidence for "the default path is untouched" is a byte-identical
// hash, and it is worth more than the duplication below. Measured, not assumed: the first attempt left the
// module list and every net name identical and still moved the hash, and the diff was entirely in those
// source-location comments.
//
// The register map is the existing one plus two words that are unused in it (it goes from 0x10 to 0x20):
//   0x14  RO  the design's status word  (bit0 CPU_RESTART_SAFE, bit1 PL_RECONFIG_SAFE, bit2 DRAINING,
//                                        bit3 TIMEOUT, 15:8 EPOCH, 31:16 NDRAINED)
//   0x18  RW  bit0 QUIESCE_REQ -- the sustained lock, not a snapshot
package zynq

import chisel3._
import chisel3.util._
import freechips.rocketchip.amba.axi4._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.subsystem.SlavePortParams
import freechips.rocketchip.diplomacy.{LazyModule, LazyModuleImp, IdRange}
import freechips.rocketchip.regmapper.{RegField, HasRegMap}
import testchipip._
import testchipip.SerialAdapter._

class ZynqRD2IO extends Bundle {
  val status     = Input(UInt(32.W))   // what the design reports at 0x14
  val quiesceReq = Output(Bool())      // 0x18 bit 0
}

trait ZynqAdapterRD2CoreBundle extends Bundle {
  implicit val p: Parameters
  val sys_reset = Output(Bool())
  val serial = Flipped(new SerialIO(SERIAL_IF_WIDTH))
  val bdev = Flipped(new BlockDeviceIO)
  val rd2 = new ZynqRD2IO
}

trait ZynqAdapterRD2CoreModule extends HasRegMap with HasBlockDeviceParameters {
  implicit val p: Parameters
  val io: ZynqAdapterRD2CoreBundle
  val w = SERIAL_IF_WIDTH

  val serDepth = p(SerialFIFODepth)
  val bdevDepth = p(BlockDeviceFIFODepth)
  val serCountBits = log2Ceil(serDepth + 1)
  val bdevCountBits = log2Ceil(bdevDepth + 1)

  val ser_out_fifo = Module(new Queue(UInt(w.W), serDepth))
  val ser_in_fifo  = Module(new Queue(UInt(w.W), serDepth))
  ser_out_fifo.io.enq <> io.serial.out
  io.serial.in <> ser_in_fifo.io.deq

  val sys_reset = RegInit(true.B)
  io.sys_reset := sys_reset

  val bdev_req_fifo  = Module(new Queue(UInt(w.W), bdevDepth))
  val bdev_data_fifo = Module(new Queue(UInt(w.W), bdevDepth))
  val bdev_resp_fifo = Module(new Queue(UInt(w.W), bdevDepth))
  val bdev_info = Reg(new BlockDeviceInfo)
  val bdev_serdes = Module(new BlockDeviceSerdes(w))

  bdev_serdes.io.bdev <> io.bdev
  bdev_req_fifo.io.enq <> bdev_serdes.io.ser.req
  bdev_data_fifo.io.enq <> bdev_serdes.io.ser.data
  bdev_serdes.io.ser.resp <> bdev_resp_fifo.io.deq
  io.bdev.info := bdev_info

  val ser_in_space = (serDepth.U - ser_in_fifo.io.count)
  val bdev_resp_space = (bdevDepth.U - bdev_resp_fifo.io.count)

  val quiesceReq = RegInit(false.B)
  io.rd2.quiesceReq := quiesceReq

  regmap(
    0x00 -> Seq(RegField.r(w, ser_out_fifo.io.deq)),
    0x04 -> Seq(RegField.r(serCountBits, ser_out_fifo.io.count)),
    0x08 -> Seq(RegField.w(w, ser_in_fifo.io.enq)),
    0x0C -> Seq(RegField.r(serCountBits, ser_in_space)),
    0x10 -> Seq(RegField(1, sys_reset)),
    0x14 -> Seq(RegField.r(32, io.rd2.status)),
    0x18 -> Seq(RegField(1, quiesceReq)),
    0x20 -> Seq(RegField.r(w, bdev_req_fifo.io.deq)),
    0x24 -> Seq(RegField.r(bdevCountBits, bdev_req_fifo.io.count)),
    0x28 -> Seq(RegField.r(w, bdev_data_fifo.io.deq)),
    0x2C -> Seq(RegField.r(bdevCountBits, bdev_data_fifo.io.count)),
    0x30 -> Seq(RegField.w(w, bdev_resp_fifo.io.enq)),
    0x34 -> Seq(RegField.r(bdevCountBits, bdev_resp_space)),
    0x38 -> Seq(RegField(sectorBits, bdev_info.nsectors)),
    0x3C -> Seq(RegField(sectorBits, bdev_info.max_req_len)))
}

class ZynqAdapterRD2Core(address: BigInt, beatBytes: Int)(implicit p: Parameters)
  extends AXI4RegisterRouter(address, beatBytes = beatBytes, concurrency = 1)(
    new AXI4RegBundle((), _)    with ZynqAdapterRD2CoreBundle)(
    new AXI4RegModule((), _, _) with ZynqAdapterRD2CoreModule)

class ZynqAdapterRD2(address: BigInt, config: SlavePortParams)(implicit p: Parameters) extends LazyModule {
  val node = AXI4MasterNode(Seq(AXI4MasterPortParameters(
    masters = Seq(AXI4MasterParameters(name = "Zynq Adapter", id = IdRange(0, 1 << config.idBits))))))
  val core = LazyModule(new ZynqAdapterRD2Core(address, config.beatBytes))
  core.node := AXI4Fragmenter() := node

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val sys_reset = Output(Bool())
      val serial = Flipped(new SerialIO(SERIAL_IF_WIDTH))
      val bdev = Flipped(new BlockDeviceIO)
      val rd2 = new ZynqRD2IO
    })
    val axi = IO(Flipped(node.out(0)._1.cloneType))
    node.out(0)._1 <> axi

    val coreIO = core.module.io
    io.sys_reset := coreIO.sys_reset
    coreIO.serial <> io.serial
    coreIO.bdev <> io.bdev
    coreIO.rd2.status := io.rd2.status
    io.rd2.quiesceReq := coreIO.rd2.quiesceReq
  }
}
