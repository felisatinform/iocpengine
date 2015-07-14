// The contents of this file are used with permission, subject to
// the Mozilla Public License Version 1.1 (the "License"); you may
// not use this file except in compliance with the License. You may
// obtain a copy of the License at
// http://www.mozilla.org/MPL/MPL-1.1.html
//
// Software distributed under the License is distributed on an
// "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
// implied. See the License for the specific language governing
// rights and limitations under the License.
unit DnUtils;

interface
uses
  Classes, SysUtils, Math,
  WinSock2, Windows;

procedure FreeInterface(Intf: IUnknown);

implementation

function UNIXTimeToDateTime(UnixTime: LongWord): TDateTime;
var
  TimeZoneInformation: TTimeZoneInformation;
begin
  GetTimeZoneInformation(TimeZoneInformation);
  Result := StrToDate('01/01/1970') + (UnixTime/(24*3600)) - ((TimeZoneInformation.Bias + TimeZoneInformation.DaylightBias) / (24 * 60));
end;

procedure DateTimeToUNIXTime(DelphiTime : TDateTime; var Seconds, Milliseconds: Cardinal);
var
  MyTimeZoneInformation: TTimeZoneInformation;
  Elapsed: TDateTime;
begin
  GetTimeZoneInformation(MyTimeZoneInformation);
  Elapsed := DelphiTime - StrToDate('01/01/1970') + ((MyTimeZoneInformation.Bias) / (24 * 60));
  Seconds := Trunc( Elapsed * (24 * 3600) );
  Milliseconds := Trunc((Elapsed * (24 * 3600) - Seconds) * 1000);
end;

type
  TIPv4Header = packed record
    FVersionAndLength: Byte;
    FTOS: Byte;
    FTotalLength: Word;
    FFragmentID: Word;
    FFragmentBits: Word;
    FTTL: Byte;
    FProtocol: Byte;
    FChecksum: Word;
    FSourceAddr: Cardinal;
    FDestAddr: Cardinal;
  end;

  TTcpHeader = packed record
    FSourcePort: Word;
    FDestPort: Word;
    FSequenceNumber: Cardinal;
    FAcknowledgementNumber: Cardinal;
    FOffset: Byte; //only left 4 bits. Header length in 32-bit segments
    FFlags: Byte;
    FWindow: Word;
    FChecksum: Word;  //includes speudo header instead of TCP header.
    FUrgentPointer: Word;
  end;

var
  PacketID: Word = 1;

function CalcCheckSum(var Buffer; Size: Integer): Word;
type
  TWordArray = array[0..1] of Word;
var
  ChkSum : LongWord;
  i : Integer;
begin
  ChkSum := 0;
  i := 0;
  while Size > 1 do
  begin
    ChkSum := ChkSum + TWordArray(Buffer)[i];
    inc(i);
    Size := Size - SizeOf(Word);
  end;

  if Size=1 then
    ChkSum := ChkSum + Byte(TWordArray(Buffer)[i]);

  ChkSum := (ChkSum shr 16) + (ChkSum and $FFFF);
  ChkSum := ChkSum + (Chksum shr 16);

  Result := Word(ChkSum);
end;



procedure BuildIPv4Header(var Buf; Length: Integer; SourceAddr, DestAddr: TSockAddrIn; var Hdr: TIPv4header);
begin
  Hdr.FVersionAndLength := 5 * 16 + 4; // Version 4 and length 5 (20 bytes)
  Hdr.FTOS := 0;
  Hdr.FTotalLength := WinSock2.htons(20) + Length + Sizeof(TTcpHeader);
  Hdr.FFragmentID := WinSock2.htons(PacketID);
  Inc(PacketID);
  Hdr.FFragmentBits := 0;
  Hdr.FTTL := 127;
  Hdr.FProtocol := 6; // TCP
  Hdr.FChecksum := 0;
  Hdr.FSourceAddr := SourceAddr.sin_addr.S_addr;
  Hdr.FDestAddr := DestAddr.sin_addr.S_addr;

  Hdr.FChecksum := CalcChecksum(Hdr, Sizeof(Hdr) div 2);
end;

procedure BuildTcpHeader(var Buf; Length: Integer; SourceAddr, DestAddr: TSockAddrIn; var Hdr: TTcpHeader);
begin
  Hdr.FSourcePort := SourceAddr.sin_port;
  Hdr.FDestPort := DestAddr.sin_port;

end;


procedure FreeInterface(Intf: IUnknown);
begin
  if Intf <> Nil then
    while Intf._Release <> 0 do
      ;
end;


end.
