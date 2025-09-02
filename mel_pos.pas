unit mel_pos;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, serial_port;

type
  TBytes = array of Byte;

  { TMelPos }
  TMelPos = class
  private
    FSerial: TSerialPort;
    function ReadByte(out B: Byte; TimeoutMS: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure InitSerial(const APort: string; ABaud: LongInt);
    procedure SendPacket(const Direction, Variant, Version: string; MsgType: Byte; const Payload: array of Byte);
    procedure SendSALE(const Payload: array of Byte);
    function ReceivePacket(out Direction, Variant, Version: string; out MsgType: Byte; out Payload: TBytes; TimeoutMS: Integer = 1000): Boolean;
  end;

implementation

{ TMelPos }

constructor TMelPos.Create;
begin
  inherited Create;
  FSerial := nil;
end;

destructor TMelPos.Destroy;
begin
  if Assigned(FSerial) then
    FSerial.Free;
  inherited Destroy;
end;

procedure TMelPos.InitSerial(const APort: string; ABaud: LongInt);
begin
  if Assigned(FSerial) then
    FreeAndNil(FSerial);
  FSerial := TSerialPort.Create(APort, ABaud);
end;

function TMelPos.ReadByte(out B: Byte; TimeoutMS: Integer): Boolean;
var
  Buf: array[0..0] of Byte;
  ReadCount: LongInt;
begin
  ReadCount := FSerial.Receive(Buf, TimeoutMS);
  Result := ReadCount = 1;
  if Result then
    B := Buf[0];
end;

procedure TMelPos.SendPacket(const Direction, Variant, Version: string; MsgType: Byte; const Payload: array of Byte);
var
  MsgSize, PayloadLen, i: Integer;
  SizeStr: string;
  Packet: TBytes;
  LRC: Byte;
begin
  if not Assigned(FSerial) then
    raise Exception.Create('Serial port not initialized');

  if (Length(Direction) <> 3) or (Length(Variant) <> 2) or (Length(Version) <> 2) then
    raise Exception.Create('Invalid header lengths');

  PayloadLen := Length(Payload);
  MsgSize := 13 + PayloadLen; // includes STX..ETX
  if MsgSize > 256 then
    raise Exception.Create('Packet too large');

  SizeStr := Format('%.3d', [MsgSize]);
  SetLength(Packet, MsgSize + 1); // add LRC byte

  Packet[0] := $02; // STX
  for i := 0 to 2 do
    Packet[1 + i] := Ord(SizeStr[i + 1]);
  for i := 0 to 2 do
    Packet[4 + i] := Ord(Direction[i + 1]);
  for i := 0 to 1 do
    Packet[7 + i] := Ord(Variant[i + 1]);
  for i := 0 to 1 do
    Packet[9 + i] := Ord(Version[i + 1]);
  Packet[11] := MsgType;
  for i := 0 to PayloadLen - 1 do
    Packet[12 + i] := Payload[i];
  Packet[12 + PayloadLen] := $03; // ETX

  LRC := 0;
  for i := 0 to 12 + PayloadLen do
    LRC := LRC xor Packet[i];
  Packet[13 + PayloadLen] := LRC;

  FSerial.Send(Packet);
end;

procedure TMelPos.SendSALE(const Payload: array of Byte);
begin
  SendPacket('MAC', '01', '01', 4, Payload);
end;

function TMelPos.ReceivePacket(out Direction, Variant, Version: string; out MsgType: Byte; out Payload: TBytes; TimeoutMS: Integer): Boolean;
var
  B: Byte;
  SizeBytes, Tmp: TBytes;
  SizeStr: string;
  MsgSize, RestLen, PayloadLen, i, ReadCount, TotalRead, DataCount: Integer;
  Buf: TBytes;
  CalcLRC, LRC: Byte;
begin
  if not Assigned(FSerial) then
    raise Exception.Create('Serial port not initialized');

  // Find STX
  repeat
    if not ReadByte(B, TimeoutMS) then
      Exit(False);
  until B = $02;

  CalcLRC := $02; // start LRC with STX

  // Read size bytes
  SetLength(SizeBytes, 3);
  TotalRead := 0;
  while TotalRead < 3 do
  begin
    SetLength(Tmp, 3 - TotalRead);
    ReadCount := FSerial.Receive(Tmp, TimeoutMS);
    if ReadCount <= 0 then
      Exit(False);
    Move(Tmp[0], SizeBytes[TotalRead], ReadCount);
    for i := 0 to ReadCount - 1 do
      CalcLRC := CalcLRC xor Tmp[i];
    Inc(TotalRead, ReadCount);
  end;
  SizeStr := Chr(SizeBytes[0]) + Chr(SizeBytes[1]) + Chr(SizeBytes[2]);
  MsgSize := StrToIntDef(SizeStr, 0);
  if MsgSize < 13 then
    Exit(False);

  RestLen := MsgSize - 4 + 1; // remaining bytes including LRC
  SetLength(Buf, RestLen);
  TotalRead := 0;
  while TotalRead < RestLen do
  begin
    SetLength(Tmp, RestLen - TotalRead);
    ReadCount := FSerial.Receive(Tmp, TimeoutMS);
    if ReadCount <= 0 then
      Exit(False);
    Move(Tmp[0], Buf[TotalRead], ReadCount);
    DataCount := ReadCount;
    if TotalRead + ReadCount > RestLen - 1 then
      DataCount := RestLen - 1 - TotalRead;
    for i := 0 to DataCount - 1 do
      CalcLRC := CalcLRC xor Tmp[i];
    Inc(TotalRead, ReadCount);
  end;

  Direction := Chr(Buf[0]) + Chr(Buf[1]) + Chr(Buf[2]);
  Variant := Chr(Buf[3]) + Chr(Buf[4]);
  Version := Chr(Buf[5]) + Chr(Buf[6]);
  MsgType := Buf[7];

  PayloadLen := MsgSize - 13;
  SetLength(Payload, PayloadLen);
  if PayloadLen > 0 then
    Move(Buf[8], Payload[0], PayloadLen);

  if Buf[8 + PayloadLen] <> $03 then
    Exit(False);

  LRC := Buf[9 + PayloadLen];

  Result := CalcLRC = LRC;
end;

end.

