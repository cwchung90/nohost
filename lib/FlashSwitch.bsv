import Vector::*;
import FIFO::*;
import RenameTable::*;
import RegFile::*;
import GetPut::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;
import FlashCtrl::*;

interface FlashSwitch#(numeric type n);
	interface Vector#(n, FlashCtrlUser) users; // FlashReadMux will use some user ports (8224B IO)
	interface FlashCtrlClient flashCtrlClient; // talk to the controller
	method Bit#(32) readCnt;
	method Bit#(32) writeCnt;
endinterface

function FlashCtrlClient extractFlashCtrlClient(FlashSwitch#(n) a);
	return a.flashCtrlClient;
endfunction

function Vector#(n, FlashCtrlUser) extractFlashCtrlUsers(FlashSwitch#(n) a);
	return a.users;
endfunction

typedef union tagged {
	Tuple2#(Bit#(128), TagT) ReadWord;
	TagT WriteDataReq;
	Tuple2#(TagT, StatusT) AckStatus;
} FlashRespT deriving (Bits, Eq); // FShow?

Bool verbose = False;
module mkFlashSwitch(FlashSwitch#(n)) provisos(
	Alias#(Bit#(TLog#(n)), channelT)
	);
	Reg#(Bit#(32)) readBeatCnt <- mkReg(0);
	Reg#(Bit#(32)) writeBeatCnt <- mkReg(0);

	RenameTable#(128, Tuple3#(TagT, channelT, BusT)) reqRenameTb <- mkRenameTable;
	Vector#(n, RegFile#(TagT, TagT)) tagRenames <- replicateM(mkRegFileFull);

	FIFO#(FlashCmd) cmdOutputQ <- mkFIFO();
	FIFO#(Tuple2#(Bit#(128), TagT)) writeWordQ <- mkFIFO();

	//FIFO#(FlashRespT) flashRespQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(128), TagT)) flashRespQ0 <- mkFIFO;
	FIFO#(Bool) flashRespQ1 <- mkFIFO;
	FIFO#(Tuple2#(TagT, StatusT)) flashRespQ2 <- mkFIFO;

	Vector#(8, Reg#(Bit#(TLog#(PageWords)))) beatCnts <- replicateM(mkReg(0));
	Integer beatsPerPage = valueOf(PageWords);

	Vector#(n, FIFO#(Tuple2#(Bit#(128), TagT))) readWordQs <- replicateM(mkFIFO);
	rule distReadWord; // if ( flashRespQ.first matches tagged ReadWord .rsp);
		flashRespQ0.deq;
		let {orTag, channel, busId} <- reqRenameTb.readResp0;
		let {d, reTag} = flashRespQ0.first;// rsp;
		readWordQs[channel].enq(tuple2(d, orTag));
		if (verbose) $display("(%m) distReadWord orTag, channel, bus, reTag, beatCnt, beatMax = {%d, %d, %d, %d, %d, %d}", orTag, channel, busId, reTag, beatCnts[busId], beatsPerPage);
		if ( beatCnts[busId] == fromInteger(beatsPerPage - 1) ) begin
			beatCnts[busId] <= 0;
			reqRenameTb.invalidEntry(reTag);
			$display("(%m) distReadWord, one page read finished (beat=%d)", beatCnts[busId]);
		end
		else begin
			beatCnts[busId] <= beatCnts[busId] + 1;
		end
	endrule

	Vector#(n, FIFO#(TagT)) writeReqQs <- replicateM(mkFIFO);
	rule distWriteReq; // if ( flashRespQ.first matches tagged WriteDataReq .rsp);
		flashRespQ1.deq;
		let {orTag, channel, busId} <- reqRenameTb.readResp1;
		writeReqQs[channel].enq(orTag);
	endrule

	Vector#(n, FIFO#(Tuple2#(TagT, StatusT))) ackStatusQs <- replicateM(mkFIFO);
	rule distAckStatus;// if ( flashRespQ.first matches tagged AckStatus .rsp);
		flashRespQ2.deq;
		let {orTag, channel, busId} <- reqRenameTb.readResp2;
		let {reTag, d} = flashRespQ2.first;// rsp;
		ackStatusQs[channel].enq(tuple2(orTag, d));
		reqRenameTb.invalidEntry(reTag);
	endrule

	function FlashCtrlUser genFlashCtrl(Integer i);
		return (interface FlashCtrlUser;
					method Action sendCmd(FlashCmd req);
						let orTag = req.tag;
						let reTag <- reqRenameTb.writeEntry(tuple3(req.tag, fromInteger(i), req.bus));
						req.tag = reTag; // rename the tag
						cmdOutputQ.enq(req);
						tagRenames[i].upd(orTag, reTag);
					endmethod
					//TODO:: it might probably need a burst lock
					method Action writeWord(Tuple2#(Bit#(128), TagT) taggedData);
						let {d, orTag} = taggedData;
						let reTag = tagRenames[i].sub(orTag);
						writeWordQ.enq(tuple2(d, reTag));
					endmethod
					method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord();
						let v <- toGet(readWordQs[i]).get();
						return v;
					endmethod
					method ActionValue#(TagT) writeDataReq();
						let v <- toGet(writeReqQs[i]).get();
						return v;
					endmethod
					method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus();
						let v <- toGet(ackStatusQs[i]).get();
						return v;
					endmethod
				endinterface);
	endfunction

	interface users = genWith(genFlashCtrl);

	interface FlashCtrlClient flashCtrlClient;
		method ActionValue#(FlashCmd) sendCmd;
			let v <- toGet(cmdOutputQ).get;
			return v;
		endmethod
		method ActionValue#(Tuple2#(Bit#(128), TagT)) writeWord;
			writeBeatCnt <= writeBeatCnt + 1;
			let v <- toGet(writeWordQ).get;
			return v;
		endmethod
		method Action readWord (Tuple2#(Bit#(128), TagT) taggedData); 
			readBeatCnt <= readBeatCnt + 1;
			reqRenameTb.readEntry0(tpl_2(taggedData));
			flashRespQ0.enq(taggedData);
		endmethod
		method Action writeDataReq(TagT tag); 
			reqRenameTb.readEntry1(tag);
			flashRespQ1.enq(?);
		endmethod
		method Action ackStatus (Tuple2#(TagT, StatusT) taggedStatus); 
			reqRenameTb.readEntry2(tpl_1(taggedStatus));
			flashRespQ2.enq(taggedStatus);
		endmethod
	endinterface
	method Bit#(32) readCnt = readBeatCnt;
	method Bit#(32) writeCnt = writeBeatCnt;
endmodule
