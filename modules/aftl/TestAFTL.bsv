import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import BRAM::*;
import BRAMFIFO::*;

import GetPut::*;
import ClientServer::*;
import Connectable::*;
import DefaultValue::*;

import Vector::*;

import ControllerTypes::*;
import MyTypes::*;

import Clocks::*;

import AFTL::*;

Integer testMax = 1024;
Integer testMax2 = 1024+64;
Integer testMax3 = 129;
Integer testMax4 = 512+64;

module mkTestAFTL(Empty);
	let aftl <- mkAFTL128;

	Reg#(Bool) startReq <- mkReg(False);
	Reg#(Bit#(32)) lpa <- mkReg(0);
	Reg#(Bit#(32)) req_cnt <- mkReg(0);
	Reg#(Bit#(32)) req_cnt2 <- mkReg(0);
	Reg#(Bit#(32)) req_cnt3 <- mkReg(0);
	Reg#(Bit#(32)) req_cnt4 <- mkReg(0);

	rule init (!startReq);
		Vector#(BlkInfoEntriesPerWord, BlkInfoEntry) data = replicate(BlkInfoEntry{status: FREE_BLK, erase: 10});
		data[2].erase = 5;
		data[3].erase = 7;
		data[7].erase = 2;
		data[9].erase = 9;

		aftl.blkinfo_portB.request.put( 
			BRAMRequest{ write: True, responseOnWrite: False, address: 2, datain: data}
		);

		startReq <= True;
	endrule

	rule send_req (startReq && req_cnt < fromInteger(testMax));
		if (req_cnt == fromInteger(testMax-1)) begin
			lpa <= 0;
		end
		else if (lpa%256 == 255) begin
			lpa <= lpa - 255 + fromInteger(valueOf(PagesPerBlock))*128;
		end
		else begin
			lpa <= lpa + 1;
		end
		req_cnt <= req_cnt+1;

		$display("req1 sent lpa: %x", lpa);
		aftl.translateReq.put(FTLCmd{tag: 0, op: WRITE_PAGE, lpa: truncate(lpa)});

	endrule

	rule send_req2 (startReq && req_cnt == fromInteger(testMax) && req_cnt2 < fromInteger(testMax2));
		if (req_cnt2 == fromInteger(testMax2-1)) begin
			lpa <= 0;
		end
		else if (lpa%256 == 255) begin
			lpa <= lpa - 255 + fromInteger(valueOf(PagesPerBlock))*128;
		end
		else begin
			lpa <= lpa + 1;
		end
		req_cnt2 <= req_cnt2+1;

		$display("req2 sent lpa: %x", lpa);
		aftl.translateReq.put(FTLCmd{tag: 0, op: READ_PAGE, lpa: truncate(lpa)});
	endrule

	rule send_req3 (startReq && req_cnt == fromInteger(testMax) && req_cnt2 == fromInteger(testMax2) && req_cnt3 < fromInteger(testMax3));
		if (req_cnt3 == fromInteger(testMax3-1)) begin
			lpa <= 0;
		end
		else if (lpa%256 == 255) begin
			lpa <= lpa - 255 + fromInteger(valueOf(PagesPerBlock))*128;
		end
		else begin
			lpa <= lpa + 1;
		end
		req_cnt3 <= req_cnt3+1;

		$display("req3 sent lpa: %x", lpa);
		aftl.translateReq.put(FTLCmd{tag: 0, op: ERASE_BLOCK, lpa: truncate(lpa)});
	endrule

	rule send_req4 (startReq && req_cnt == fromInteger(testMax) && req_cnt2 == fromInteger(testMax2) && req_cnt3 == fromInteger(testMax3) && req_cnt4 < fromInteger(testMax4));
		if (req_cnt4 == fromInteger(testMax4-1)) begin
			lpa <= 0;
		end
		else if (lpa%256 == 255) begin
			lpa <= lpa - 255 + fromInteger(valueOf(PagesPerBlock))*128;
		end
		else begin
			lpa <= lpa + 1;
		end
		req_cnt4 <= req_cnt4+1;

		$display("req4 sent lpa: %x", lpa);
		aftl.translateReq.put(FTLCmd{tag: 0, op: READ_PAGE, lpa: truncate(lpa)});
	endrule

	Reg#(Bit#(32)) resp_cnt <- mkReg(0);
	rule proc_resp ;
		let ans <- aftl.resp.get;
		resp_cnt <= resp_cnt + 1;
		$display("OK - Card Bus Chip Block Page:  %d, %d, %d, %d, %d", ans.card, ans.fcmd.bus, ans.fcmd.chip, ans.fcmd.block, ans.fcmd.page);
		$display(fshow(ans.fcmd.op));
	endrule

	Reg#(Bit#(16)) resp_cnt_err <- mkReg(0);
	rule proc_resp_err ;
		let ans <- aftl.respError.get;
		resp_cnt_err <= resp_cnt_err + 1;
		$display("Error - lpa: %d", ans.lpa);
		$display(fshow(ans.op));
	endrule

endmodule