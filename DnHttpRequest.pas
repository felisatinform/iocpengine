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
unit DnHttpRequest;
interface
uses
  DnRtl, DnTcpReactor, DnTcpRequests, DnTcpChannel;

type
  IDnHttpHeaderHandler = interface (IDnTcpLineHandler)
  end;
  
  TDnReadHttpHeader = class (TDnTcpLineRequest)
  protected
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnHttpHeaderHandler; MaxSize: Cardinal = 65535);
  end;

implementation
var
  CRLFCRLFZero: PAnsiChar = #13#10#13#10#0;

constructor TDnReadHttpHeader.Create(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnHttpHeaderHandler; MaxSize: Cardinal);
begin
  inherited Create(Channel, Key, Handler, MaxSize);
  FEolSign := CRLFCRLFZero;
end;
//---------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------

end.
