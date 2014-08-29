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
{$I DnConfig.inc}
unit DnRegister;
interface
uses
  Classes,
  DnFileCachedLogger,
  DnCallbackLogger,
  DnSimpleExecutor,
  
  DnTcpRequestor,
  DnHttpRequestor,
  DnTcpReactor,
  DnTcpListener,
  DnTcpConnecter,
  DnTcpFileWriter,
  DnWinsockMgr,
  DnMsgServer,
  DnTcpRequest,
  DnMsgClient,
  DnStringList,
  DnHttpServer
{$IFDEF ENABLE_STREAMSEC}
  ,DnTlsRequestor
{$ENDIF}
  ;  

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('DNet',
    [TDnFileCachedLogger, TDnCallbackLogger, TDnSimpleExecutor, TDnTcpRequestor,
     TDnHttpRequestor, TDnTcpReactor, TDnTcpListener, TDnTcpConnecter, TDnTcpFileWriter,
     TDnWinsockMgr, TDnHttpServer]);
end;

end.
