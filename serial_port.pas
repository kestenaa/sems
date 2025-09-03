unit serial_port;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, serial;

type
  { TSerialPort }
  TSerialPort = class
  private
    FHandle: TSerialHandle;
    FPortName: string;
  public
    constructor Create(const APort: string; ABaud: LongInt);
    destructor Destroy; override;

    function Send(const Data: array of Byte): LongInt;
    function Receive(var Buffer: array of Byte; TimeoutMS: Integer = 1000): LongInt;
  end;

implementation

{ TSerialPort }

constructor TSerialPort.Create(const APort: string; ABaud: LongInt);
begin
  FPortName := APort;
  FHandle := SerOpen(APort);
  if FHandle = TSerialHandle(0) then
    raise Exception.CreateFmt('Unable to open %s', [APort]);

  if SerSetParams(FHandle, ABaud, 8, NoneParity, 1, []) <> 0 then
    raise Exception.Create('Unable to configure serial port');

  SerFlush(FHandle);
end;

destructor TSerialPort.Destroy;
begin
  if FHandle <> TSerialHandle(0) then
    SerClose(FHandle);
  inherited Destroy;
end;

function TSerialPort.Send(const Data: array of Byte): LongInt;
begin
  Result := SerWrite(FHandle, Data[0], Length(Data));
  if Result < 0 then
    raise Exception.Create('Write failed');
end;

function TSerialPort.Receive(var Buffer: array of Byte; TimeoutMS: Integer): LongInt;
begin
  Result := SerReadTimeout(FHandle, Buffer[0], Length(Buffer), TimeoutMS);
  if Result < 0 then
    raise Exception.Create('Read failed');
end;

end.

